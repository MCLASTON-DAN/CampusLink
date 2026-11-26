-- 0020: study groups that can be invite-only, and a members-only group chat
-- with replies, pinned messages, @mentions (incl. @all) and a typing signal.
-- Safe to run more than once.

-- A. Open or invite-only.
alter table public.study_groups add column if not exists privacy text not null default 'open';
alter table public.study_groups drop constraint if exists study_groups_privacy_check;
alter table public.study_groups add constraint study_groups_privacy_check check (privacy in ('open', 'invite'));

create or replace function public.is_group_member(p_group uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.study_group_members m where m.group_id = p_group and m.user_id = (select auth.uid()));
$$;
create or replace function public.is_group_owner(p_group uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.study_groups g where g.id = p_group and g.owner_id = (select auth.uid()));
$$;
revoke execute on function public.is_group_member(uuid) from public, anon;
revoke execute on function public.is_group_owner(uuid) from public, anon;
grant execute on function public.is_group_member(uuid) to authenticated;
grant execute on function public.is_group_owner(uuid) to authenticated;

-- Joining yourself only works for open groups with room. (SECURITY INVOKER so
-- it sees the real caller; approvals run inside a definer function.)
create or replace function public.group_join_guard() returns trigger
language plpgsql security invoker set search_path = public as $$
declare g public.study_groups; n int;
begin
  select * into g from public.study_groups where id = new.group_id;
  select count(*) into n from public.study_group_members where group_id = new.group_id;
  if n >= g.max_members then raise exception 'This group is full.'; end if;
  if current_user in ('authenticated', 'anon') and g.privacy = 'invite' and g.owner_id <> new.user_id then
    raise exception 'This group is invite-only. Ask to join instead.';
  end if;
  return new;
end $$;
drop trigger if exists group_join_guard on public.study_group_members;
create trigger group_join_guard before insert on public.study_group_members
  for each row execute function public.group_join_guard();

create table if not exists public.study_group_requests (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.study_groups(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  message text check (message is null or char_length(message) <= 300),
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined')),
  created_at timestamptz not null default now()
);
create unique index if not exists group_requests_one_pending on public.study_group_requests (group_id, user_id) where status = 'pending';
create index if not exists group_requests_user on public.study_group_requests (user_id);
alter table public.study_group_requests enable row level security;
drop policy if exists "ask to join" on public.study_group_requests;
create policy "ask to join" on public.study_group_requests for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'pending' and not public.is_group_member(group_id));
drop policy if exists "see join requests" on public.study_group_requests;
create policy "see join requests" on public.study_group_requests for select to authenticated
  using (user_id = (select auth.uid()) or public.is_group_owner(group_id));
grant select, insert on public.study_group_requests to authenticated;

create or replace function public.decide_group_request(p_request uuid, p_approve boolean) returns void
language plpgsql security definer set search_path = public as $$
declare r public.study_group_requests; gname text;
begin
  select * into r from public.study_group_requests where id = p_request for update;
  if r.id is null or r.status <> 'pending' then raise exception 'That request was already handled.'; end if;
  if not public.is_group_owner(r.group_id) then raise exception 'Only the group owner decides.'; end if;
  select name into gname from public.study_groups where id = r.group_id;
  if p_approve then
    insert into public.study_group_members (group_id, user_id) values (r.group_id, r.user_id) on conflict do nothing;
  end if;
  update public.study_group_requests set status = case when p_approve then 'approved' else 'declined' end where id = p_request;
  insert into public.notifications (user_id, kind, title, body, link)
  values (r.user_id, 'group',
          case when p_approve then 'You joined ' || gname else 'Your request to join ' || gname || ' was declined' end,
          case when p_approve then 'Say hello in the group chat.' else 'You can look for another group.' end,
          '/groups/' || r.group_id);
end $$;
revoke execute on function public.decide_group_request(uuid, boolean) from public, anon;
grant execute on function public.decide_group_request(uuid, boolean) to authenticated;

-- Owner hears about new join requests.
create or replace function public.notify_group_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, kind, title, body, link)
  select g.owner_id, 'group', 'Someone asked to join ' || g.name, coalesce(left(new.message, 200), ''), '/groups/' || g.id
    from public.study_groups g where g.id = new.group_id and g.owner_id is not null;
  return null;
end $$;
revoke execute on function public.notify_group_request() from public, anon, authenticated;
drop trigger if exists notify_group_request on public.study_group_requests;
create trigger notify_group_request after insert on public.study_group_requests
  for each row execute function public.notify_group_request();

-- B. Messages: members only.
create table if not exists public.study_group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.study_groups(id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  reply_to uuid references public.study_group_messages(id) on delete set null,
  mentions uuid[] not null default '{}',
  mention_all boolean not null default false,
  pinned boolean not null default false,
  deleted boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists group_messages_group on public.study_group_messages (group_id, created_at desc);
create index if not exists group_messages_author on public.study_group_messages (author_id);
create index if not exists group_messages_reply on public.study_group_messages (reply_to);
alter table public.study_group_messages enable row level security;
drop policy if exists "members read chat" on public.study_group_messages;
create policy "members read chat" on public.study_group_messages for select to authenticated
  using (public.is_group_member(group_id));
drop policy if exists "members write chat" on public.study_group_messages;
create policy "members write chat" on public.study_group_messages for insert to authenticated
  with check (author_id = (select auth.uid()) and public.is_group_member(group_id) and not pinned and not deleted);
-- Deleting your own message (soft). Pinning goes through pin_group_message().
drop policy if exists "delete own message" on public.study_group_messages;
create policy "delete own message" on public.study_group_messages for update to authenticated
  using (author_id = (select auth.uid())) with check (author_id = (select auth.uid()));
grant select, insert, update (deleted) on public.study_group_messages to authenticated;

-- Mentions: only real members count; @all at most once per 10 minutes per group.
-- A reply must point at a message in the same group. Mentioned people are notified.
create or replace function public.group_message_rules() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.reply_to is not null and not exists (
       select 1 from public.study_group_messages m where m.id = new.reply_to and m.group_id = new.group_id) then
    new.reply_to := null;
  end if;
  new.mentions := coalesce(array(select distinct u from unnest(new.mentions) u
                                 where exists (select 1 from public.study_group_members m
                                               where m.group_id = new.group_id and m.user_id = u)
                                   and u <> new.author_id), '{}');
  if new.mention_all and exists (select 1 from public.study_group_messages m
                                 where m.group_id = new.group_id and m.mention_all
                                   and m.created_at > now() - interval '10 minutes') then
    new.mention_all := false;   -- the message still sends, just without the @all alert
  end if;
  return new;
end $$;
revoke execute on function public.group_message_rules() from public, anon, authenticated;
drop trigger if exists group_message_rules on public.study_group_messages;
create trigger group_message_rules before insert on public.study_group_messages
  for each row execute function public.group_message_rules();

create or replace function public.notify_group_mentions() returns trigger
language plpgsql security definer set search_path = public as $$
declare gname text; who text;
begin
  select name into gname from public.study_groups where id = new.group_id;
  select full_name into who from public.profiles where id = new.author_id;
  insert into public.notifications (user_id, kind, title, body, link)
  select m.user_id, 'group', coalesce(who, 'Someone') || ' mentioned you in ' || gname, left(new.body, 200), '/groups/' || new.group_id
    from public.study_group_members m
   where m.group_id = new.group_id and m.user_id <> new.author_id
     and (new.mention_all or m.user_id = any (new.mentions));
  return null;
end $$;
revoke execute on function public.notify_group_mentions() from public, anon, authenticated;
drop trigger if exists notify_group_mentions on public.study_group_messages;
create trigger notify_group_mentions after insert on public.study_group_messages
  for each row when (new.mention_all or cardinality(new.mentions) > 0)
  execute function public.notify_group_mentions();

create or replace function public.pin_group_message(p_message uuid, p_pin boolean) returns void
language plpgsql security definer set search_path = public as $$
declare g uuid;
begin
  select group_id into g from public.study_group_messages where id = p_message;
  if g is null then raise exception 'Message not found.'; end if;
  if not public.is_group_owner(g) then raise exception 'Only the group owner pins messages.'; end if;
  if p_pin and (select count(*) from public.study_group_messages where group_id = g and pinned) >= 3 then
    raise exception 'Up to 3 pinned messages. Unpin one first.';
  end if;
  update public.study_group_messages set pinned = p_pin where id = p_message;
end $$;
revoke execute on function public.pin_group_message(uuid, boolean) from public, anon;
grant execute on function public.pin_group_message(uuid, boolean) to authenticated;

alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('course', 'official', 'event', 'tutor', 'request', 'office', 'access', 'group'));

-- Live updates for chat.
do $$ begin
  alter publication supabase_realtime add table public.study_group_messages;
exception when duplicate_object then null; end $$;

-- C. Typing signal: a PRIVATE realtime channel "group:<id>" that only members
--    can join (no one else can listen in or fake typing).
drop policy if exists "group members use typing channel" on realtime.messages;
create policy "group members use typing channel" on realtime.messages for select to authenticated
  using (realtime.topic() like 'group:%'
         and public.is_group_member(nullif(split_part(realtime.topic(), ':', 2), '')::uuid));
drop policy if exists "group members send typing" on realtime.messages;
create policy "group members send typing" on realtime.messages for insert to authenticated
  with check (realtime.topic() like 'group:%'
              and public.is_group_member(nullif(split_part(realtime.topic(), ':', 2), '')::uuid));

-- D. Owners may now edit their group (incl. privacy); members still leave themselves.
drop policy if exists "owner edit group" on public.study_groups;
create policy "owner edit group" on public.study_groups for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
drop policy if exists "owner removes member" on public.study_group_members;
create policy "owner removes member" on public.study_group_members for delete to authenticated
  using (public.is_group_owner(group_id));
