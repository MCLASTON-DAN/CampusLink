-- CampusLink 0006: lecturers (orange badge), course-unit notices that reach
-- only the students taking that unit, and a personal notification inbox.

-- Profile photo is stored as its public link, which can be a bit long.
alter table public.profiles drop constraint if exists profiles_avatar_path_check;
alter table public.profiles
  add constraint profiles_avatar_path_check check (avatar_path is null or char_length(avatar_path) <= 400);

-- Course codes are compared without spaces or case: "bda 1202" = "BDA1202".
create or replace function public.norm_code(c text) returns text
language sql immutable set search_path = public as $$
  select upper(regexp_replace(coalesce(c, ''), '\s+', '', 'g'));
$$;

-- ---------------------------------------------------------------------
-- A. Lecturers: staff assign a lecturer to the units they teach.
-- ---------------------------------------------------------------------
create table if not exists public.course_lecturers (
  course_code text not null check (course_code = public.norm_code(course_code) and char_length(course_code) between 3 and 20),
  lecturer_id uuid not null references public.profiles(id) on delete cascade,
  assigned_by uuid references public.profiles(id) default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (course_code, lecturer_id)
);
alter table public.course_lecturers enable row level security;
drop policy if exists "read lecturers" on public.course_lecturers;
create policy "read lecturers" on public.course_lecturers for select to authenticated using (true);
drop policy if exists "staff assign lecturers" on public.course_lecturers;
create policy "staff assign lecturers" on public.course_lecturers for all to authenticated
  using (public.is_staff()) with check (public.is_staff());
grant select, insert, delete on public.course_lecturers to authenticated;

-- The units I take, from my own timetable.
create or replace function public.my_course_codes() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct public.norm_code(course_code)), '{}')
  from public.timetable_entries where user_id = auth.uid();
$$;

-- Orange badge for lecturers (after the red administration badge).
drop view if exists public.public_profiles;
create view public.public_profiles with (security_invoker = true) as
select p.id, p.full_name, p.programme, p.year_of_study, p.faculty,
       p.is_tutor, p.tutor_subjects, p.is_buddy_mentor, p.tutor_verified,
       p.avatar_path,
       case when p.status_until is null or p.status_until > now() then p.status_text end as status_text,
       case when p.status_until > now() then p.status_until end as status_until,
       coalesce(o.position_title, case when l.is_lecturer then 'Lecturer' end) as office_title,
       o.office_name,
       case when p.role = 'super_admin' or o.kind = 'administration' then 'red'
            when l.is_lecturer then 'orange'
            when o.kind = 'guild' then 'green'
            when o.kind = 'press' then 'purple'
            when p.tutor_verified then 'blue' end as badge
from public.profiles p
left join lateral (
  select m.position_title, pb.kind, pb.name as office_name
  from public.publisher_members m
  join public.publishers pb on pb.id = m.publisher_id and pb.is_active
  where m.user_id = p.id and m.revoked_at is null
    and now() between m.starts_at and m.expires_at
  order by (pb.kind = 'administration') desc, (pb.kind = 'guild') desc, (pb.kind = 'press') desc
  limit 1) o on true
left join lateral (
  select exists (select 1 from public.course_lecturers cl where cl.lecturer_id = p.id) as is_lecturer) l on true;
grant select on public.public_profiles to authenticated;

-- ---------------------------------------------------------------------
-- B. Course notices: one message, many units (shared units are common:
--    e.g. Machine Learning taken by BSE, BCS and BDSAI students).
-- ---------------------------------------------------------------------
create table if not exists public.course_notices (
  id uuid primary key default gen_random_uuid(),
  lecturer_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  course_codes text[] not null check (cardinality(course_codes) between 1 and 10),
  title text not null check (char_length(title) between 3 and 120),
  body text not null check (char_length(body) between 5 and 4000),
  link_url text check (link_url is null or link_url ~* '^https://'),
  priority text not null default 'normal' check (priority in ('normal','important','urgent')),
  created_at timestamptz not null default now()
);
create index if not exists course_notices_codes on public.course_notices using gin (course_codes);
create index if not exists course_notices_time on public.course_notices (created_at desc);
alter table public.course_notices enable row level security;

-- Codes are tidied on the way in.
create or replace function public.course_notices_clean() returns trigger
language plpgsql set search_path = public as $$
begin
  new.course_codes := (select array_agg(distinct public.norm_code(c)) from unnest(new.course_codes) c
                       where public.norm_code(c) <> '');
  return new;
end $$;
drop trigger if exists course_notices_clean on public.course_notices;
create trigger course_notices_clean before insert or update on public.course_notices
  for each row execute function public.course_notices_clean();

-- A lecturer may only post to units they are assigned to (staff to any).
drop policy if exists "lecturer posts to own units" on public.course_notices;
create policy "lecturer posts to own units" on public.course_notices for insert to authenticated
  with check (lecturer_id = auth.uid() and (public.is_staff() or not exists (
    select 1 from unnest(course_codes) c
    where public.norm_code(c) not in (select cl.course_code from public.course_lecturers cl
                                      where cl.lecturer_id = auth.uid()))));
-- Students see notices for units in their own timetable; lecturers see their own.
drop policy if exists "read my unit notices" on public.course_notices;
create policy "read my unit notices" on public.course_notices for select to authenticated
  using (lecturer_id = auth.uid() or public.is_staff() or course_codes && public.my_course_codes());
drop policy if exists "lecturer deletes own" on public.course_notices;
create policy "lecturer deletes own" on public.course_notices for delete to authenticated
  using (lecturer_id = auth.uid() or public.is_super_admin());
grant select, insert, delete on public.course_notices to authenticated;

-- ---------------------------------------------------------------------
-- C. Personal notification inbox. Rows are only made by the triggers below.
-- ---------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('course','official','event','tutor','request')),
  title text not null,
  body text not null default '',
  link text,                                   -- in-app path, e.g. /news/<id>
  priority text not null default 'normal',
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists notifications_user on public.notifications (user_id, created_at desc);
alter table public.notifications enable row level security;
drop policy if exists "own notifications" on public.notifications;
create policy "own notifications" on public.notifications for select to authenticated using (user_id = auth.uid());
drop policy if exists "mark own read" on public.notifications;
create policy "mark own read" on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "delete own" on public.notifications;
create policy "delete own" on public.notifications for delete to authenticated using (user_id = auth.uid());
grant select, delete on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

-- Live delivery to open apps.
do $$ begin
  alter publication supabase_realtime add table public.notifications;
exception when duplicate_object or undefined_object then null; end $$;

-- Course notice -> everyone whose timetable has one of the units.
create or replace function public.notify_course_notice() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, kind, title, body, link, priority)
  select distinct t.user_id, 'course',
         array_to_string(new.course_codes, ', ') || ': ' || new.title,
         left(new.body, 200), '/courses', new.priority
  from public.timetable_entries t
  where public.norm_code(t.course_code) = any (new.course_codes)
    and t.user_id <> new.lecturer_id;
  return null;
end $$;
drop trigger if exists notify_course_notice on public.course_notices;
create trigger notify_course_notice after insert on public.course_notices
  for each row execute function public.notify_course_notice();

-- Official notices from the Administration -> everyone.
create or replace function public.notify_official_post() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'published' and new.kind in ('notice','official_record')
     and (select kind from public.publishers where id = new.publisher_id) = 'administration' then
    insert into public.notifications (user_id, kind, title, body, link)
    select p.id, 'official', new.title, left(new.body, 200), '/news/' || new.id
    from public.profiles p where p.id <> new.author_id;
  end if;
  return null;
end $$;
drop trigger if exists notify_official_post on public.posts;
create trigger notify_official_post after insert on public.posts
  for each row execute function public.notify_official_post();

-- A major event approved for the home screen -> everyone.
create or replace function public.notify_major_event() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.major_status = 'approved' and old.major_status is distinct from 'approved' then
    insert into public.notifications (user_id, kind, title, body, link)
    select p.id, 'event', new.title,
           'Starts ' || to_char(new.starts_at at time zone 'Africa/Kampala', 'Dy DD Mon, HH24:MI'),
           '/events/' || new.id
    from public.profiles p;
  end if;
  return null;
end $$;
drop trigger if exists notify_major_event on public.events;
create trigger notify_major_event after update on public.events
  for each row execute function public.notify_major_event();

-- Tutor requests: tell the tutor about a new request, the student about the answer.
create or replace function public.notify_tutor_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.notifications (user_id, kind, title, body, link)
    values (new.tutor_id, 'tutor', 'New tutoring request for ' || new.course_code,
            left(new.message, 200), '/tutors/mine');
  elsif new.status is distinct from old.status and new.status in ('accepted','declined') then
    insert into public.notifications (user_id, kind, title, body, link)
    values (new.student_id, 'tutor', 'Your tutor ' || new.status || ' your request',
            new.course_code, '/tutors/mine');
  end if;
  return null;
end $$;
drop trigger if exists notify_tutor_request on public.tutor_requests;
create trigger notify_tutor_request after insert or update on public.tutor_requests
  for each row execute function public.notify_tutor_request();

-- Help requests: tell the student when an office changes the status.
create or replace function public.notify_help_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    insert into public.notifications (user_id, kind, title, body, link)
    values (new.student_id, 'request', 'Your request is now ' || replace(new.status, '_', ' '),
            new.title, '/requests/' || new.id);
  end if;
  return null;
end $$;
drop trigger if exists notify_help_request on public.help_requests;
create trigger notify_help_request after update on public.help_requests
  for each row execute function public.notify_help_request();

-- Trigger helpers are never called directly.
revoke execute on function public.course_notices_clean() from public, anon, authenticated;
revoke execute on function public.notify_course_notice() from public, anon, authenticated;
revoke execute on function public.notify_official_post() from public, anon, authenticated;
revoke execute on function public.notify_major_event() from public, anon, authenticated;
revoke execute on function public.notify_tutor_request() from public, anon, authenticated;
revoke execute on function public.notify_help_request() from public, anon, authenticated;
revoke execute on function public.my_course_codes() from public, anon;
grant execute on function public.my_course_codes() to authenticated;

-- Staff assign a lecturer by the email they sign in with.
create or replace function public.assign_lecturer(p_email text, p_course text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid;
begin
  if not public.is_staff() then
    raise exception 'Only staff can assign lecturers' using errcode = '42501';
  end if;
  select id into uid from auth.users where lower(email) = lower(trim(p_email));
  if uid is null then
    raise exception 'No account with that email yet. Ask the lecturer to sign in to CampusLink once first.';
  end if;
  insert into public.course_lecturers (course_code, lecturer_id) values (public.norm_code(p_course), uid)
  on conflict do nothing;
end $$;
revoke execute on function public.assign_lecturer(text, text) from public, anon;
grant execute on function public.assign_lecturer(text, text) to authenticated;
