-- 0018: tutor results by grade band.
-- After a semester, students who had confirmed lessons say which band they got
-- in that unit. Tutors are judged on how their students did, not only stars.
--   bands: 0 = below 50, 1 = 50-59, 2 = 60-69, 3 = 70-79, 4 = 80+
-- Safeguards: only students with a completed lesson for that tutor and unit;
-- one report per student, tutor, unit and semester; bands are shown only once
-- 5+ students reported, and nobody (not the tutor) sees who reported what.
-- Safe to run more than once.

create table if not exists public.tutor_outcomes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  tutor_id uuid not null references public.profiles(id) on delete cascade,
  course_code text not null check (course_code = public.norm_code(course_code)),
  semester text not null check (semester ~ '^[0-9]{4}-S[12]$'),
  band smallint not null check (band between 0 and 4),
  created_at timestamptz not null default now(),
  unique (student_id, tutor_id, course_code, semester)
);
create index if not exists tutor_outcomes_tutor on public.tutor_outcomes (tutor_id);
alter table public.tutor_outcomes enable row level security;

drop policy if exists "report own result" on public.tutor_outcomes;
create policy "report own result" on public.tutor_outcomes for insert to authenticated
  with check (
    tutor_outcomes.student_id = (select auth.uid()) and tutor_outcomes.tutor_id <> (select auth.uid())
    and exists (select 1 from public.tutor_requests r
                where r.student_id = (select auth.uid()) and r.tutor_id = tutor_outcomes.tutor_id
                  and public.norm_code(r.course_code) = tutor_outcomes.course_code and r.status = 'completed'));
drop policy if exists "see own results" on public.tutor_outcomes;
create policy "see own results" on public.tutor_outcomes for select to authenticated
  using (student_id = (select auth.uid()));
drop policy if exists "fix own result" on public.tutor_outcomes;
create policy "fix own result" on public.tutor_outcomes for update to authenticated
  using (student_id = (select auth.uid())) with check (student_id = (select auth.uid()));
grant select, insert, update (band) on public.tutor_outcomes to authenticated;

-- Share of students at 60+ we can be confident about (Wilson lower bound, 95%).
-- 1 of 1 is not "100%": it gives about 0.21. 9 of 10 gives about 0.60.
create or replace function public.outcome_confidence(p_good int, p_n int) returns numeric
language sql immutable as $$
  select case when p_n = 0 then 0 else
    ((p_good::numeric / p_n) + 1.9208 / p_n
     - 1.96 * sqrt(((p_good::numeric / p_n) * (1 - p_good::numeric / p_n) + 0.9604 / p_n) / p_n))
    / (1 + 3.8416 / p_n) end;
$$;

-- Per tutor: number of reports and, from 5 reports up, the band counts.
create or replace function public.tutor_outcome_bands()
returns table (tutor_id uuid, reports int, bands int[], confidence numeric)
language sql stable security definer set search_path = public as $$
  select o.tutor_id, count(*)::int,
         case when count(*) >= 5 then array[
           count(*) filter (where band = 0), count(*) filter (where band = 1), count(*) filter (where band = 2),
           count(*) filter (where band = 3), count(*) filter (where band = 4)]::int[] end,
         public.outcome_confidence((count(*) filter (where band >= 2))::int, count(*)::int)
  from public.tutor_outcomes o group by o.tutor_id;
$$;
revoke execute on function public.tutor_outcome_bands() from public, anon;
grant execute on function public.tutor_outcome_bands() to authenticated;

-- Blue tick (Level 4) now also needs results: 10+ reports, confidence >= 0.5.
create or replace function public.recompute_tutor_verification(p_tutor uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s record; cur boolean; lessons int; upheld int; checked boolean; n int; good int; conf numeric;
begin
  select * into s from public.tutor_score(p_tutor);
  select tutor_verified into cur from public.profiles where id = p_tutor;
  select count(*) into lessons from public.tutor_requests where tutor_id = p_tutor and status = 'completed';
  select count(*) into upheld from public.tutor_reports where tutor_id = p_tutor and status = 'upheld';
  select exists (select 1 from public.tutor_modules where tutor_id = p_tutor and grade_checked and is_active) into checked;
  select count(*), count(*) filter (where band >= 2) into n, good from public.tutor_outcomes where tutor_id = p_tutor;
  conf := public.outcome_confidence(good, n);
  if not coalesce(cur, false) and checked and lessons >= 30 and s.score >= 4.3 and s.reviewers >= 5
     and upheld = 0 and n >= 10 and conf >= 0.5 then
    update public.profiles set tutor_verified = true, tutor_verified_at = now() where id = p_tutor;
  elsif coalesce(cur, false) and (not checked or s.score < 3.8 or upheld > 0 or (n >= 10 and conf < 0.4)) then
    update public.profiles set tutor_verified = false where id = p_tutor;
  end if;
end $$;
revoke execute on function public.recompute_tutor_verification(uuid) from public, anon, authenticated;
drop trigger if exists tutor_outcomes_trust on public.tutor_outcomes;
create trigger tutor_outcomes_trust after insert or update on public.tutor_outcomes
  for each row execute function public.tutor_trust_after();

-- Tutor asks a student how the unit went (at most once a week per lesson).
alter table public.tutor_requests add column if not exists asked_progress_at timestamptz;
create or replace function public.ask_student_progress(p_request uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.tutor_requests;
begin
  select * into r from public.tutor_requests where id = p_request for update;
  if r.id is null or r.tutor_id <> (select auth.uid()) then raise exception 'Not your lesson.'; end if;
  if r.status <> 'completed' then raise exception 'Only after the lesson is confirmed.'; end if;
  if r.asked_progress_at > now() - interval '7 days' then raise exception 'You already asked this week.'; end if;
  update public.tutor_requests set asked_progress_at = now() where id = p_request;
  insert into public.notifications (user_id, kind, title, body, link)
  values (r.student_id, 'tutor', 'How did ' || r.course_code || ' go?',
          'Your tutor would like to know. Tap to share your grade band – only totals are shown.', '/tutors/mine');
end $$;
revoke execute on function public.ask_student_progress(uuid) from public, anon;
grant execute on function public.ask_student_progress(uuid) to authenticated;

-- Semester end date (set by the super admin). 3 and 10 days after it,
-- students who had lessons and haven't reported are reminded.
create table if not exists public.app_settings (key text primary key, value text not null, updated_at timestamptz not null default now());
alter table public.app_settings enable row level security;
drop policy if exists "read settings" on public.app_settings;
create policy "read settings" on public.app_settings for select to authenticated using (true);
drop policy if exists "super admin settings" on public.app_settings;
create policy "super admin settings" on public.app_settings for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());
grant select, insert, update on public.app_settings to authenticated;

create or replace function public.remind_outcome_reports() returns void
language plpgsql security definer set search_path = public as $$
declare ends date; sem text;
begin
  select value::date into ends from public.app_settings where key = 'semester_end';
  if ends is null or current_date not in (ends + 3, ends + 10) then return; end if;
  sem := extract(year from ends)::text || '-S' || case when extract(month from ends) <= 6 then '1' else '2' end;
  insert into public.notifications (user_id, kind, title, body, link)
  select distinct r.student_id, 'tutor', 'Semester done: how did ' || r.course_code || ' go?',
         'Share your grade band for the tutor who helped you. It takes 5 seconds and only totals are shown.', '/tutors/mine'
    from public.tutor_requests r
   where r.status = 'completed' and r.created_at >= ends - interval '6 months'
     and not exists (select 1 from public.tutor_outcomes o
                     where o.student_id = r.student_id and o.tutor_id = r.tutor_id
                       and o.course_code = public.norm_code(r.course_code) and o.semester = sem);
end $$;
revoke execute on function public.remind_outcome_reports() from public, anon, authenticated;
do $$ begin
  perform cron.unschedule('campuslink-outcome-reminders');
exception when others then null; end $$;
select cron.schedule('campuslink-outcome-reminders', '0 7 * * *', 'select public.remind_outcome_reports()');
