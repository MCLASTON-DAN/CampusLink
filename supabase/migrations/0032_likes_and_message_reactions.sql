-- 0032: likes like Instagram, reactions like WhatsApp.
--
--   Posts, events, comments: a single ♡ like. One per person. Anyone signed in
--   can see who liked something. The owner gets one grouped alert per item
--   per hour ("Amina and 3 others liked your post"), never one per tap.
--   Study group messages: one emoji reaction per person, from 6
--   (👍 ❤️ 😂 😮 😢 🙏), stored on the message so the live chat updates by
--   itself. Only members can react; visitors can't.
--   Announcements have neither: they keep "Seen by".

-- ---------------------------------------------------------------- likes only
update public.reactions set emoji = 'like' where emoji <> 'like';
alter table public.reactions drop constraint if exists reactions_emoji_check;
alter table public.reactions alter column emoji set default 'like';
alter table public.reactions add constraint reactions_emoji_check check (emoji = 'like');

-- Older app versions still call react(): it now only ever likes or unlikes.
create or replace function public.react(p_type text, p_id uuid, p_emoji text) returns text
language plpgsql security invoker set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Please sign in first.' using errcode = '42501'; end if;
  if exists (select 1 from public.reactions where user_id = me and target_type = p_type and target_id = p_id) then
    delete from public.reactions where user_id = me and target_type = p_type and target_id = p_id;
    return null;
  end if;
  insert into public.reactions (user_id, target_type, target_id) values (me, p_type, p_id);
  return 'like';
end $$;

-- Like counts and "liked by me" for a batch of items (used for comments).
create or replace function public.like_counts(p_type text, p_ids uuid[])
returns table (target_id uuid, likes int, liked boolean)
language sql stable security invoker set search_path = public as $$
  select r.target_id, count(*)::int, bool_or(r.user_id = (select auth.uid()))
  from public.reactions r
  where r.target_type = p_type and r.target_id = any (p_ids)
  group by r.target_id;
$$;

-- Who liked something, newest first (like Instagram's "Liked by").
create or replace function public.likers(p_type text, p_id uuid)
returns table (user_id uuid, full_name text, username text, avatar_path text, badge text, liked_at timestamptz)
language sql stable security invoker set search_path = public as $$
  select r.user_id, p.full_name, p.username, p.avatar_path, p.badge, r.created_at
  from public.reactions r
  join public.public_profiles p on p.id = r.user_id
  where r.target_type = p_type and r.target_id = p_id and (select auth.uid()) is not null
  order by r.created_at desc
  limit 300;
$$;

revoke execute on function public.like_counts(text, uuid[]) from public, anon;
revoke execute on function public.likers(text, uuid) from public, anon;
grant execute on function public.like_counts(text, uuid[]) to authenticated;
grant execute on function public.likers(text, uuid) to authenticated;

-- ---------------------------------------------------------------- like alerts
-- One alert per item per hour. Later likes in that hour update the same alert
-- (an update doesn't ring the phone again).
create or replace function public.notify_like() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  owner uuid;
  what text;
  v_link text;
  liker text;
  n public.notifications;
  others int;
begin
  if new.target_type = 'post' then
    select author_id, '/news/' || id into owner, v_link from public.posts where id = new.target_id;
    what := 'your post';
  elsif new.target_type = 'comment' then
    select c.author_id,
           case c.target_type when 'post' then '/news/' || c.target_id || '?comments=1' else '/events/' || c.target_id end
      into owner, v_link
      from public.comments c where c.id = new.target_id;
    what := 'your comment';
  else
    return new; -- events are official; no like alerts
  end if;
  if owner is null or owner = new.user_id then return new; end if;

  select coalesce(nullif(display_name, ''), full_name) into liker from public.profiles where id = new.user_id;

  select * into n from public.notifications
  where user_id = owner and kind = 'social' and link = v_link and title like 'New like%'
    and read_at is null and created_at > now() - interval '1 hour'
  order by created_at desc limit 1;

  if not found then
    insert into public.notifications (user_id, kind, title, body, link)
    values (owner, 'social', 'New like', coalesce(liker, 'Someone') || ' liked ' || what || '.', v_link);
  else
    select count(distinct r.user_id) - 1 into others from public.reactions r
    where r.target_type = new.target_type and r.target_id = new.target_id
      and r.user_id <> owner and r.created_at >= n.created_at;
    update public.notifications
    set title = 'New likes',
        body = coalesce(liker, 'Someone') || case when others > 0
                 then ' and ' || others || case when others = 1 then ' other' else ' others' end else '' end
               || ' liked ' || what || '.'
    where id = n.id;
  end if;
  return new;
end $$;
revoke execute on function public.notify_like() from public, anon, authenticated;

drop trigger if exists reactions_notify_like on public.reactions;
create trigger reactions_notify_like after insert on public.reactions
  for each row execute function public.notify_like();

-- ---------------------------------------------------------------- chat reactions
-- {"<user id>": "love", ...} on each message.
alter table public.study_group_messages add column if not exists reactions jsonb not null default '{}'::jsonb;

-- A new message always starts with no reactions (no faking them on send).
create or replace function public.group_message_clean_reactions() returns trigger
language plpgsql set search_path = public as $$
begin
  new.reactions := '{}'::jsonb;
  return new;
end $$;
drop trigger if exists group_message_clean_reactions on public.study_group_messages;
create trigger group_message_clean_reactions before insert on public.study_group_messages
  for each row execute function public.group_message_clean_reactions();

-- React, switch, or remove (same emoji again). Members only, not visitors.
create or replace function public.react_to_message(p_message uuid, p_emoji text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  m public.study_group_messages;
  key text := me::text;
begin
  if me is null then raise exception 'Please sign in first.' using errcode = '42501'; end if;
  if p_emoji not in ('like', 'love', 'haha', 'wow', 'sad', 'pray') then raise exception 'Unknown reaction.'; end if;
  select * into m from public.study_group_messages where id = p_message for update;
  if not found or m.deleted then raise exception 'That message is gone.'; end if;
  if not public.is_group_member(m.group_id) then raise exception 'Only members can react.' using errcode = '42501'; end if;
  if public.is_visitor() then
    raise exception 'Visitors can read CampusLink but not react.' using errcode = '42501';
  end if;
  update public.study_group_messages
  set reactions = case when reactions ->> key = p_emoji then reactions - key
                       else reactions || jsonb_build_object(key, p_emoji) end
  where id = p_message
  returning reactions into m.reactions;
  return m.reactions;
end $$;
revoke execute on function public.react_to_message(uuid, text) from public, anon;
grant execute on function public.react_to_message(uuid, text) to authenticated;
