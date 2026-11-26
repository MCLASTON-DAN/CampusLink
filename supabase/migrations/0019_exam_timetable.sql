-- 0019: exam timetable. Exams happen on a DATE (not "every Thursday").
-- * exam_papers: the official list, one row per paper, entered once by the
--   Examinations office (its handlers) or the super admin. Everyone can read.
-- * my_exams: a student's own extra entries (e.g. a retake, a practical).
-- A student's exams = official papers for the units on their timetable + their own.
-- Safe to run more than once.

create or replace function public.can_manage_exams() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_super_admin() or exists (
    select 1 from public.help_office_staff s join public.help_offices o on o.id = s.office_id
    where s.user_id = (select auth.uid()) and o.name ilike '%exam%');
$$;
revoke execute on function public.can_manage_exams() from public, anon;
grant execute on function public.can_manage_exams() to authenticated;

create table if not exists public.exam_papers (
  id uuid primary key default gen_random_uuid(),
  course_code text not null check (course_code = public.norm_code(course_code) and char_length(course_code) between 3 and 20),
  course_name text check (course_name is null or char_length(course_name) <= 120),
  exam_date date not null,
  start_time time not null,
  end_time time not null check (end_time > start_time),
  room text check (room is null or char_length(room) <= 80),
  campus text check (campus is null or char_length(campus) <= 80),
  notes text check (notes is null or char_length(notes) <= 300),
  created_by uuid default auth.uid() references public.profiles(id),
  updated_at timestamptz not null default now()
);
create index if not exists exam_papers_code_date on public.exam_papers (course_code, exam_date);
create index if not exists fk_exam_papers_created_by on public.exam_papers (created_by);
alter table public.exam_papers enable row level security;
drop policy if exists "read exam papers" on public.exam_papers;
create policy "read exam papers" on public.exam_papers for select to authenticated using (true);
drop policy if exists "exams office writes papers" on public.exam_papers;
create policy "exams office writes papers" on public.exam_papers for all to authenticated
  using (public.can_manage_exams()) with check (public.can_manage_exams());
grant select, insert, update, delete on public.exam_papers to authenticated;

create table if not exists public.my_exams (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  course_code text not null check (char_length(course_code) between 2 and 20),
  course_name text check (course_name is null or char_length(course_name) <= 120),
  exam_date date not null,
  start_time time not null,
  end_time time not null check (end_time > start_time),
  room text check (room is null or char_length(room) <= 80),
  campus text check (campus is null or char_length(campus) <= 80),
  created_at timestamptz not null default now()
);
create index if not exists my_exams_user on public.my_exams (user_id, exam_date);
alter table public.my_exams enable row level security;
drop policy if exists "own exams" on public.my_exams;
create policy "own exams" on public.my_exams for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
grant select, insert, update, delete on public.my_exams to authenticated;

-- Tell students when a paper for one of their units is added or moved.
create or replace function public.notify_exam_paper() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.exam_date is distinct from old.exam_date
     or new.start_time is distinct from old.start_time or new.room is distinct from old.room then
    insert into public.notifications (user_id, kind, title, body, link)
    select distinct t.user_id, 'course',
           case when tg_op = 'INSERT' then 'Exam date out: ' else 'Exam changed: ' end || new.course_code,
           to_char(new.exam_date, 'Dy DD Mon') || ' at ' || to_char(new.start_time, 'HH24:MI')
             || coalesce(' · ' || new.room, ''),
           '/exams'
      from public.timetable_entries t
     where public.norm_code(t.course_code) = new.course_code;
  end if;
  return null;
end $$;
revoke execute on function public.notify_exam_paper() from public, anon, authenticated;
drop trigger if exists notify_exam_paper on public.exam_papers;
create trigger notify_exam_paper after insert or update on public.exam_papers
  for each row execute function public.notify_exam_paper();
