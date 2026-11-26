-- 0021: honest edits and retractions.
--
-- EDIT: the author fixes their own post or event. Everyone sees "Edited";
--   the old version is kept, readable by that office's lead, the author and
--   the super admin. Changing an event's time or place tells everyone who RSVP'd.
-- RETRACT (posts, announcements) / CANCEL (events): wrong or outdated official
--   information is not silently deleted. It is replaced by a public notice
--   "Retracted by <office>: <reason>", so people who already read it learn it
--   was wrong. Who: the author, the office lead (manage_members), or the
--   super admin. Every retraction is logged in the public moderation record.
-- DELETE for good: only through super-admin moderation, for content that must
--   not stay visible at all (personal data, abuse, illegal). Not for mistakes.
-- Safe to run more than once.

-- A. Who may retract content of an office.
create or replace function public.can_retract(p_publisher uuid, p_author uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_author = (select auth.uid()) or public.is_super_admin()
      or (p_publisher is not null and public.can_publish(p_publisher, 'manage_members'));
$$;
revoke execute on function public.can_retract(uuid, uuid) from public, anon;
grant execute on function public.can_retract(uuid, uuid) to authenticated;

alter table public.moderation_actions drop constraint if exists moderation_actions_target_type_check;
alter table public.moderation_actions add constraint moderation_actions_target_type_check
  check (target_type in ('post', 'comment', 'event', 'announcement'));
alter table public.moderation_actions drop constraint if exists moderation_actions_action_check;
alter table public.moderation_actions add constraint moderation_actions_action_check
  check (action in ('remove', 'restore', 'retract', 'cancel'));

-- B. Posts: retraction fields; edit history visible to the office lead too.
alter table public.posts add column if not exists retracted_at timestamptz,
  add column if not exists retract_reason text check (retract_reason is null or char_length(retract_reason) between 10 and 300);

drop policy if exists "read revisions" on public.post_revisions;
create policy "read revisions" on public.post_revisions for select to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id
                 and public.can_retract(p.publisher_id, p.author_id)));

-- Retracted posts are frozen, and nobody retracts or un-retracts by a plain update.
create or replace function public.posts_retract_guard() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.retracted_at is distinct from old.retracted_at or new.retract_reason is distinct from old.retract_reason then
      raise exception 'Use "Retract" to retract a post.';
    end if;
    if old.retracted_at is not null then
      raise exception 'A retracted post cannot be edited. Publish a corrected post instead.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists posts_retract_guard on public.posts;
create trigger posts_retract_guard before update on public.posts
  for each row execute function public.posts_retract_guard();

create or replace function public.retract_post(p_post uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare p public.posts;
begin
  select * into p from public.posts where id = p_post for update;
  if p.id is null then raise exception 'Post not found.'; end if;
  if not public.can_retract(p.publisher_id, p.author_id) then
    raise exception 'Only the author, the office lead or the super admin can retract this.';
  end if;
  if p.retracted_at is not null then return; end if;
  if char_length(trim(coalesce(p_reason, ''))) < 10 then raise exception 'Say what was wrong (at least 10 letters).'; end if;
  update public.posts set retracted_at = now(), retract_reason = trim(p_reason) where id = p_post;
  insert into public.moderation_actions (actor_id, target_type, target_id, target_title, action, reason)
  values ((select auth.uid()), 'post', p_post, left(p.title, 120), 'retract', rpad(trim(p_reason), 20, '.'));
end $$;
revoke execute on function public.retract_post(uuid, text) from public, anon;
grant execute on function public.retract_post(uuid, text) to authenticated;

-- C. Events: edit mark + history, cancel with reason, attendees told.
alter table public.events add column if not exists edited_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancel_reason text check (cancel_reason is null or char_length(cancel_reason) between 10 and 300);

create table if not exists public.event_revisions (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  title text not null,
  description text not null default '',
  starts_at timestamptz not null,
  ends_at timestamptz,
  location text,
  edited_by uuid references public.profiles(id),
  edited_at timestamptz not null default now()
);
create index if not exists event_revisions_event on public.event_revisions (event_id, edited_at desc);
create index if not exists fk_event_revisions_by on public.event_revisions (edited_by);
alter table public.event_revisions enable row level security;
drop policy if exists "read event revisions" on public.event_revisions;
create policy "read event revisions" on public.event_revisions for select to authenticated
  using (exists (select 1 from public.events e where e.id = event_id and public.can_retract(e.publisher_id, e.created_by)));
grant select on public.event_revisions to authenticated;

create or replace function public.events_keep_revision() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.title is distinct from old.title or new.description is distinct from old.description
     or new.starts_at is distinct from old.starts_at or new.ends_at is distinct from old.ends_at
     or new.location is distinct from old.location then
    insert into public.event_revisions (event_id, title, description, starts_at, ends_at, location, edited_by)
    values (old.id, old.title, old.description, old.starts_at, old.ends_at, old.location, (select auth.uid()));
    new.edited_at := now();
  end if;
  return new;
end $$;
revoke execute on function public.events_keep_revision() from public, anon, authenticated;
drop trigger if exists events_keep_revision on public.events;
create trigger events_keep_revision before update on public.events
  for each row execute function public.events_keep_revision();

create or replace function public.events_cancel_guard() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.cancelled_at is distinct from old.cancelled_at or new.cancel_reason is distinct from old.cancel_reason then
      raise exception 'Use "Cancel event" to cancel.';
    end if;
    if old.cancelled_at is not null then raise exception 'A cancelled event cannot be edited.'; end if;
  end if;
  return new;
end $$;
drop trigger if exists events_cancel_guard on public.events;
create trigger events_cancel_guard before update on public.events
  for each row execute function public.events_cancel_guard();

-- People who said "I'm going" hear about a new time/place or a cancellation.
create or replace function public.notify_event_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare what text;
begin
  if new.cancelled_at is not null and old.cancelled_at is null then
    what := 'Cancelled: ' || new.title;
  elsif new.starts_at is distinct from old.starts_at or new.location is distinct from old.location then
    what := 'Changed: ' || new.title;
  else
    return null;
  end if;
  insert into public.notifications (user_id, kind, title, body, link)
  select r.user_id, 'event', what,
         case when new.cancelled_at is not null then coalesce(new.cancel_reason, '')
              else to_char(new.starts_at at time zone 'Africa/Kampala', 'Dy DD Mon HH24:MI') || coalesce(' · ' || new.location, '') end,
         '/events/' || new.id
    from public.event_rsvps r where r.event_id = new.id;
  return null;
end $$;
revoke execute on function public.notify_event_change() from public, anon, authenticated;
drop trigger if exists notify_event_change on public.events;
create trigger notify_event_change after update on public.events
  for each row execute function public.notify_event_change();

create or replace function public.cancel_event(p_event uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare e public.events;
begin
  select * into e from public.events where id = p_event for update;
  if e.id is null then raise exception 'Event not found.'; end if;
  if not public.can_retract(e.publisher_id, e.created_by) then
    raise exception 'Only the organiser, the office lead or the super admin can cancel this.';
  end if;
  if e.cancelled_at is not null then return; end if;
  if char_length(trim(coalesce(p_reason, ''))) < 10 then raise exception 'Say why it is cancelled (at least 10 letters).'; end if;
  update public.events set cancelled_at = now(), cancel_reason = trim(p_reason) where id = p_event;
  insert into public.moderation_actions (actor_id, target_type, target_id, target_title, action, reason)
  values ((select auth.uid()), 'event', p_event, left(e.title, 120), 'cancel', rpad(trim(p_reason), 20, '.'));
end $$;
revoke execute on function public.cancel_event(uuid, text) from public, anon;
grant execute on function public.cancel_event(uuid, text) to authenticated;

-- D. Announcements: retract instead of silent delete.
alter table public.announcements add column if not exists edited_at timestamptz,
  add column if not exists retracted_at timestamptz,
  add column if not exists retract_reason text check (retract_reason is null or char_length(retract_reason) between 10 and 300);
drop policy if exists "author deletes announcements" on public.announcements;
create policy "author deletes announcements" on public.announcements for delete to authenticated
  using (public.is_super_admin());

create or replace function public.announcements_edit_mark() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.retracted_at is distinct from old.retracted_at or new.retract_reason is distinct from old.retract_reason then
      raise exception 'Use "Retract" to retract an announcement.';
    end if;
    if old.retracted_at is not null then raise exception 'A retracted announcement cannot be edited.'; end if;
  end if;
  if new.title is distinct from old.title or new.body is distinct from old.body then new.edited_at := now(); end if;
  return new;
end $$;
drop trigger if exists announcements_edit_mark on public.announcements;
create trigger announcements_edit_mark before update on public.announcements
  for each row execute function public.announcements_edit_mark();

create or replace function public.retract_announcement(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare a public.announcements;
begin
  select * into a from public.announcements where id = p_id for update;
  if a.id is null then raise exception 'Announcement not found.'; end if;
  if not (a.author_id = (select auth.uid()) or public.is_super_admin()) then
    raise exception 'Only the author or the super admin can retract this.';
  end if;
  if a.retracted_at is not null then return; end if;
  if char_length(trim(coalesce(p_reason, ''))) < 10 then raise exception 'Say what was wrong (at least 10 letters).'; end if;
  update public.announcements set retracted_at = now(), retract_reason = trim(p_reason) where id = p_id;
  insert into public.moderation_actions (actor_id, target_type, target_id, target_title, action, reason)
  values ((select auth.uid()), 'announcement', p_id, left(a.title, 120), 'retract', rpad(trim(p_reason), 20, '.'));
end $$;
revoke execute on function public.retract_announcement(uuid, text) from public, anon;
grant execute on function public.retract_announcement(uuid, text) to authenticated;
