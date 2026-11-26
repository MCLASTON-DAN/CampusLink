-- 0028: emoji reactions, reply and @mention alerts, event reminders,
-- "seen by" counts on announcements. Safe to run more than once.

-- =========================================================================
-- 1. Emoji reactions (one per person per post/event; tap again to remove)
-- =========================================================================
alter table public.reactions add column if not exists emoji text not null default 'like';
alter table public.reactions drop constraint if exists reactions_emoji_check;
alter table public.reactions add constraint reactions_emoji_check
  check (emoji in ('like', 'love', 'haha', 'wow', 'celebrate', 'sad'));

create or replace function public.react(p_type text, p_id uuid, p_emoji text) returns text
language plpgsql security invoker set search_path = public as $$
declare cur text; me uuid := auth.uid();
begin
  if me is null then raise exception 'Please sign in first.' using errcode = '42501'; end if;
  select emoji into cur from public.reactions where user_id = me and target_type = p_type and target_id = p_id;
  if cur = p_emoji then
    delete from public.reactions where user_id = me and target_type = p_type and target_id = p_id;
    return null;
  elsif cur is not null then
    update public.reactions set emoji = p_emoji, created_at = now()
     where user_id = me and target_type = p_type and target_id = p_id;
  else
    insert into public.reactions (user_id, target_type, target_id, emoji) values (me, p_type, p_id, p_emoji);
  end if;
  return p_emoji;
end $$;

create or replace function public.reaction_summary(p_type text, p_id uuid)
returns table (emoji text, n int, mine boolean)
language sql stable security definer set search_path = public as $$
  select r.emoji, count(*)::int, bool_or(r.user_id = (select auth.uid()))
  from public.reactions r where r.target_type = p_type and r.target_id = p_id and (select auth.uid()) is not null
  group by r.emoji order by count(*) desc;
$$;

revoke execute on function public.react(text, uuid, text) from public, anon;
revoke execute on function public.reaction_summary(text, uuid) from public, anon;
grant execute on function public.react(text, uuid, text) to authenticated;
grant execute on function public.reaction_summary(text, uuid) to authenticated;
grant update (emoji, created_at) on public.reactions to authenticated;
drop policy if exists "change own reaction" on public.reactions;
create policy "change own reaction" on public.reactions for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- =========================================================================
-- 2. Replies stay one level deep; replies and @mentions notify people
-- =========================================================================
alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('course', 'official', 'event', 'tutor', 'request', 'office', 'access', 'group', 'social'));

create or replace function public.comment_reply_check() returns trigger
language plpgsql security invoker set search_path = public as $$
declare p public.comments;
begin
  if new.parent_id is null then return new; end if;
  select * into p from public.comments where id = new.parent_id;
  if p.id is null or p.target_type <> new.target_type or p.target_id <> new.target_id then
    raise exception 'You can only reply to a comment on the same post.';
  end if;
  -- Replying to a reply attaches to the top comment, like most apps.
  if p.parent_id is not null then new.parent_id := p.parent_id; end if;
  return new;
end $$;
drop trigger if exists comment_reply_check on public.comments;
create trigger comment_reply_check before insert on public.comments
  for each row execute function public.comment_reply_check();

create or replace function public.notify_comment() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  link text := case new.target_type when 'post' then '/news/' else '/events/' end || new.target_id;
  who text := (select coalesce(p.display_name, p.full_name) from public.profiles p where p.id = new.author_id);
  parent_author uuid;
  m record;
begin
  if new.parent_id is not null then
    select author_id into parent_author from public.comments where id = new.parent_id;
    if parent_author is not null and parent_author <> new.author_id then
      insert into public.notifications (user_id, kind, title, body, link)
      values (parent_author, 'social', coalesce(who, 'Someone') || ' replied to your comment', left(new.body, 160), link);
    end if;
  end if;
  -- @username mentions: at most 5 people, never yourself or closing accounts.
  for m in
    select distinct p.id from regexp_matches(lower(new.body), '@([a-z0-9._]{3,20})', 'g') as x(u)
    join public.profiles p on p.username = x.u[1]
    where p.id <> new.author_id and p.id is distinct from parent_author and p.closing_at is null and p.closed_at is null
    limit 5
  loop
    insert into public.notifications (user_id, kind, title, body, link)
    values (m.id, 'social', coalesce(who, 'Someone') || ' mentioned you', left(new.body, 160), link);
  end loop;
  return null;
end $$;
revoke execute on function public.notify_comment() from public, anon, authenticated;
drop trigger if exists notify_comment on public.comments;
create trigger notify_comment after insert on public.comments
  for each row execute function public.notify_comment();

-- =========================================================================
-- 3. Event reminders: one hour before, to everyone who said they're going
-- =========================================================================
alter table public.event_rsvps add column if not exists reminded_at timestamptz;

create or replace function public.send_event_reminders() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with due as (
    select r.event_id, r.user_id, e.title, e.location, e.online_url, e.starts_at
    from public.event_rsvps r join public.events e on e.id = r.event_id
    where r.reminded_at is null and e.status = 'published' and e.cancelled_at is null
      and e.starts_at between now() + interval '40 minutes' and now() + interval '80 minutes'
  ), sent as (
    insert into public.notifications (user_id, kind, title, body, link)
    select d.user_id, 'event', 'Starts at ' || to_char(d.starts_at at time zone 'Africa/Kampala', 'HH24:MI') || ': ' || d.title,
           coalesce(d.location, case when d.online_url is not null then 'Online' end, 'See the event for details'),
           '/events/' || d.event_id
    from due d
    returning 1
  )
  update public.event_rsvps r set reminded_at = now()
  from due d where r.event_id = d.event_id and r.user_id = d.user_id;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.send_event_reminders() from public, anon, authenticated;

select cron.unschedule('campuslink-event-reminders') where exists (select 1 from cron.job where jobname = 'campuslink-event-reminders');
select cron.schedule('campuslink-event-reminders', '*/10 * * * *', 'select public.send_event_reminders()');

-- =========================================================================
-- 4. "Seen by" on announcements (posts already have post_views)
-- =========================================================================
create table if not exists public.announcement_views (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (announcement_id, user_id)
);
create index if not exists announcement_views_user on public.announcement_views (user_id);
alter table public.announcement_views enable row level security;
revoke all on public.announcement_views from anon, authenticated;
alter table public.announcements add column if not exists reminded_at timestamptz;

create or replace function public.record_announcement_views(p_ids uuid[]) returns void
language sql security definer set search_path = public as $$
  insert into public.announcement_views (announcement_id, user_id)
  select a.id, (select auth.uid()) from public.announcements a
  where a.id = any (p_ids) and (select auth.uid()) is not null
  on conflict do nothing;
$$;

-- Author or staff only: how many people have seen each announcement.
create or replace function public.announcement_seen_counts(p_ids uuid[])
returns table (announcement_id uuid, seen int, reminded_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.id, (select count(*)::int from public.announcement_views v where v.announcement_id = a.id), a.reminded_at
  from public.announcements a
  where a.id = any (p_ids) and (a.author_id = (select auth.uid()) or public.is_staff());
$$;

-- Once per announcement: nudge everyone who hasn't opened it yet.
create or replace function public.remind_announcement(p_id uuid) returns int
language plpgsql security definer set search_path = public as $$
declare a public.announcements; n int;
begin
  select * into a from public.announcements where id = p_id;
  if a.id is null then raise exception 'Announcement not found.'; end if;
  if not (a.author_id = auth.uid() or public.is_super_admin()) then
    raise exception 'Only the author or the super admin can send a reminder.';
  end if;
  if a.retracted_at is not null then raise exception 'This announcement was retracted.'; end if;
  if a.reminded_at is not null then raise exception 'A reminder was already sent for this announcement.'; end if;
  insert into public.notifications (user_id, kind, title, body, link)
  select p.id, 'official', 'Reminder: ' || a.title, left(a.body, 160), '/announcements'
  from public.profiles p
  where p.closed_at is null and p.closing_at is null and p.id <> a.author_id
    and not exists (select 1 from public.announcement_views v where v.announcement_id = a.id and v.user_id = p.id)
  limit 10000;
  get diagnostics n = row_count;
  update public.announcements set reminded_at = now() where id = a.id;
  return n;
end $$;

revoke execute on function public.record_announcement_views(uuid[]) from public, anon;
revoke execute on function public.announcement_seen_counts(uuid[]) from public, anon;
revoke execute on function public.remind_announcement(uuid) from public, anon;
grant execute on function public.record_announcement_views(uuid[]) to authenticated;
grant execute on function public.announcement_seen_counts(uuid[]) to authenticated;
grant execute on function public.remind_announcement(uuid) to authenticated;
