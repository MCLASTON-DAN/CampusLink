-- 0016: least privilege. Each office has its own handlers; staff no longer
-- see or change everything.
--
-- Who sees a help request:
--   * the student who sent it;
--   * the handlers of the office it is sent to (help_office_staff);
--   * staff, only while it is at the general desk (no office yet), to route it;
--   * the super admin, EXCEPT for confidential offices (e.g. Counselling).
-- Moving a request moves the access: the old office stops seeing it.
-- Role and handler changes take effect at once (rules read live data) and
-- the person is notified so their app refreshes.
-- Safe to run more than once.

-- A. Offices: confidential flag + handlers.
alter table public.help_offices add column if not exists confidential boolean not null default false;
update public.help_offices set confidential = true
 where (name ilike '%counsel%' or name ilike '%wellness%' or category = 'health') and not confidential;

create table if not exists public.help_office_staff (
  office_id uuid not null references public.help_offices(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  added_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key (office_id, user_id)
);
create index if not exists help_office_staff_user on public.help_office_staff (user_id);
create index if not exists fk_help_office_staff_added_by on public.help_office_staff (added_by);
alter table public.help_office_staff enable row level security;

create or replace function public.handles_office(p_office uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_office is not null and exists (
    select 1 from public.help_office_staff s where s.office_id = p_office and s.user_id = (select auth.uid()));
$$;

-- Can act on a request as the office (not as the student who sent it).
create or replace function public.can_handle_request(p_office uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when p_office is null then public.is_staff()
    else public.handles_office(p_office)
      or (public.is_super_admin()
          and not coalesce((select o.confidential from public.help_offices o where o.id = p_office), false))
  end;
$$;

create or replace function public.can_see_request(p_student uuid, p_office uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_student = (select auth.uid()) or public.can_handle_request(p_office);
$$;

revoke execute on function public.handles_office(uuid) from public, anon;
revoke execute on function public.can_handle_request(uuid) from public, anon;
revoke execute on function public.can_see_request(uuid, uuid) from public, anon;
grant execute on function public.handles_office(uuid) to authenticated;
grant execute on function public.can_handle_request(uuid) to authenticated;
grant execute on function public.can_see_request(uuid, uuid) to authenticated;

drop policy if exists "see office handlers" on public.help_office_staff;
create policy "see office handlers" on public.help_office_staff for select to authenticated
  using (user_id = (select auth.uid()) or public.is_super_admin() or public.handles_office(office_id));
grant select on public.help_office_staff to authenticated;   -- changes only via set_office_handler()

-- B. Help requests.
drop policy if exists "student own requests" on public.help_requests;
create policy "student own requests" on public.help_requests for select to authenticated
  using (public.can_see_request(student_id, office_id));
drop policy if exists "staff update request" on public.help_requests;
create policy "staff update request" on public.help_requests for update to authenticated
  using (public.can_see_request(student_id, office_id))
  with check (public.can_see_request(student_id, office_id));

-- Students: status only open/closed, nothing else of theirs changes hands.
-- Offices: may not rewrite what the student wrote. Nobody moves a request by a
-- plain update: moving goes through move_help_request() so it is logged.
create or replace function public.help_request_student_limits() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.office_id is distinct from old.office_id then
      raise exception 'Use "Change office" to move a request.';
    end if;
    if new.student_id is distinct from old.student_id then
      raise exception 'A request cannot be handed to another student.';
    end if;
    if (new.title is distinct from old.title or new.description is distinct from old.description)
       and old.student_id <> (select auth.uid()) then
      raise exception 'Only the student can change what they wrote.';
    end if;
    if not public.can_handle_request(old.office_id)
       and new.status is distinct from old.status and new.status not in ('open', 'closed') then
      raise exception 'Only the office can change the status of a request.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists help_request_student_limits on public.help_requests;
create trigger help_request_student_limits before update on public.help_requests
  for each row execute function public.help_request_student_limits();

drop policy if exists "request updates visible" on public.help_request_updates;
create policy "request updates visible" on public.help_request_updates for select to authenticated
  using (exists (select 1 from public.help_requests r
                 where r.id = request_id and public.can_see_request(r.student_id, r.office_id)));
drop policy if exists "request updates insert" on public.help_request_updates;
create policy "request updates insert" on public.help_request_updates for insert to authenticated
  with check (author_id = (select auth.uid())
              and exists (select 1 from public.help_requests r
                          where r.id = request_id and public.can_see_request(r.student_id, r.office_id)));

-- Move a request: the student (while open), or whoever handles it now.
create or replace function public.move_help_request(p_request uuid, p_office uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.help_requests; oname text;
begin
  select * into r from public.help_requests where id = p_request for update;
  if r.id is null then raise exception 'Request not found.'; end if;
  if not ((r.student_id = (select auth.uid()) and r.status in ('open', 'in_progress'))
          or public.can_handle_request(r.office_id)) then
    raise exception 'You cannot move this request.';
  end if;
  if p_office is not null then
    select name into oname from public.help_offices where id = p_office;
    if oname is null then raise exception 'That office does not exist.'; end if;
  end if;
  if p_office is not distinct from r.office_id then return; end if;
  update public.help_requests set office_id = p_office, updated_at = now() where id = p_request;
  insert into public.help_request_updates (request_id, author_id, message)
  values (p_request, (select auth.uid()), 'Sent to ' || coalesce(oname, 'the general desk') || '.');
end $$;
revoke execute on function public.move_help_request(uuid, uuid) from public, anon;
grant execute on function public.move_help_request(uuid, uuid) to authenticated;

-- C. Notifications: handlers hear about new or moved requests; people hear
--    when their access changes (so the app refreshes).
alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('course', 'official', 'event', 'tutor', 'request', 'office', 'access'));

create or replace function public.notify_office_handlers() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.office_id is not null and (tg_op = 'INSERT' or new.office_id is distinct from old.office_id) then
    insert into public.notifications (user_id, kind, title, body, link)
    select s.user_id, 'request', 'New request for your office', left(new.title, 200), '/requests/' || new.id
      from public.help_office_staff s
     where s.office_id = new.office_id and s.user_id <> new.student_id;
  end if;
  return null;
end $$;
revoke execute on function public.notify_office_handlers() from public, anon, authenticated;
drop trigger if exists notify_office_handlers on public.help_requests;
create trigger notify_office_handlers after insert or update of office_id on public.help_requests
  for each row execute function public.notify_office_handlers();

create or replace function public.set_office_handler(p_office uuid, p_user uuid, p_add boolean) returns void
language plpgsql security definer set search_path = public as $$
declare oname text;
begin
  if not public.is_super_admin() then raise exception 'Only the super admin chooses who handles an office.'; end if;
  select name into oname from public.help_offices where id = p_office;
  if oname is null then raise exception 'That office does not exist.'; end if;
  if p_add then
    insert into public.help_office_staff (office_id, user_id, added_by)
    values (p_office, p_user, (select auth.uid())) on conflict do nothing;
  else
    delete from public.help_office_staff where office_id = p_office and user_id = p_user;
  end if;
  insert into public.notifications (user_id, kind, title, body, link)
  values (p_user, 'access',
          case when p_add then 'You now handle requests for ' || oname else 'You no longer handle ' || oname end,
          case when p_add then 'Requests sent to this office will show in your Requests.' else 'Its requests are no longer visible to you.' end,
          '/requests');
end $$;
revoke execute on function public.set_office_handler(uuid, uuid, boolean) from public, anon;
grant execute on function public.set_office_handler(uuid, uuid, boolean) to authenticated;

create or replace function public.notify_role_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role is distinct from old.role then
    insert into public.notifications (user_id, kind, title, body, link)
    values (new.id, 'access', 'Your access changed',
            'Your role is now ' || replace(new.role, '_', ' ') || '.', '/profile');
  end if;
  return null;
end $$;
revoke execute on function public.notify_role_change() from public, anon, authenticated;
drop trigger if exists notify_role_change on public.profiles;
create trigger notify_role_change after update of role on public.profiles
  for each row execute function public.notify_role_change();

-- D. Office details: the super admin, or that office's own handlers.
--    Only the super admin can switch "confidential" on or off.
drop policy if exists "staff write offices" on public.help_offices;
drop policy if exists "super admin offices" on public.help_offices;
create policy "super admin offices" on public.help_offices for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());
drop policy if exists "handlers edit own office" on public.help_offices;
create policy "handlers edit own office" on public.help_offices for update to authenticated
  using (public.handles_office(id)) with check (public.handles_office(id));

create or replace function public.help_office_guard() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') and not public.is_super_admin()
     and new.confidential is distinct from old.confidential then
    raise exception 'Only the super admin can change whether an office is confidential.';
  end if;
  return new;
end $$;
drop trigger if exists help_office_guard on public.help_offices;
create trigger help_office_guard before update on public.help_offices
  for each row execute function public.help_office_guard();

-- E. Announcements: staff post; only the author (or the super admin) edits or deletes.
drop policy if exists "staff write announcements" on public.announcements;
drop policy if exists "staff post announcements" on public.announcements;
create policy "staff post announcements" on public.announcements for insert to authenticated
  with check (public.is_staff() and author_id = (select auth.uid()));
drop policy if exists "author edits announcements" on public.announcements;
create policy "author edits announcements" on public.announcements for update to authenticated
  using (author_id = (select auth.uid()) or public.is_super_admin())
  with check (author_id = (select auth.uid()) or public.is_super_admin());
drop policy if exists "author deletes announcements" on public.announcements;
create policy "author deletes announcements" on public.announcements for delete to authenticated
  using (author_id = (select auth.uid()) or public.is_super_admin());
