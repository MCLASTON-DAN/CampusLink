-- 0014: tutor grade checks and the 4 tutor levels.
--   1 New            grades typed in only      -> found by name/@username search only
--   2 Grade-checked  a results slip was checked -> suggested for the checked units
--   3 Experienced    + 10 lessons, rating >= 4.0 (3+ reviews)
--   4 Expert (tick)  + 30 lessons, rating >= 4.3, 5+ reviewers, no upheld reports
-- Tutors can teach from day one; the check only controls being SUGGESTED.
-- Safe to run more than once.

-- A. A checked flag on each unit a tutor offers. Only a reviewer can set it.
alter table public.tutor_modules
  add column if not exists grade_checked boolean not null default false,
  add column if not exists grade_checked_at timestamptz;

-- Guard (SECURITY INVOKER so it sees the real caller). App users cannot tick
-- their own units, and changing the grade or unit removes the check, so a
-- tutor can't be checked for a C and then change it to an A.
create or replace function public.tutor_modules_check_guard() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.grade_checked := false;
      new.grade_checked_at := null;
    else
      if new.grade_checked is distinct from old.grade_checked
         or new.grade_checked_at is distinct from old.grade_checked_at then
        raise exception 'Only a reviewer can mark a grade as checked.';
      end if;
      if public.norm_code(new.course_code) is distinct from public.norm_code(old.course_code)
         or coalesce(trim(new.grade_achieved), '') is distinct from coalesce(trim(old.grade_achieved), '') then
        new.grade_checked := false;
        new.grade_checked_at := null;
      end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists tutor_modules_check_guard on public.tutor_modules;
create trigger tutor_modules_check_guard before insert or update on public.tutor_modules
  for each row execute function public.tutor_modules_check_guard();
revoke execute on function public.tutor_modules_check_guard() from public, anon, authenticated;

-- B. Results slips. Private: only the tutor, staff, and lecturers of that unit.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('grade-proofs', 'grade-proofs', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Path is <tutor id>/<UNIT CODE>/<file>.
create or replace function public.can_review_unit(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_staff() or exists (
    select 1 from public.course_lecturers cl
    where cl.lecturer_id = (select auth.uid()) and cl.course_code = public.norm_code(p_code));
$$;
revoke execute on function public.can_review_unit(text) from public, anon;
grant execute on function public.can_review_unit(text) to authenticated;

drop policy if exists "grade proofs upload own" on storage.objects;
create policy "grade proofs upload own" on storage.objects for insert to authenticated
  with check (bucket_id = 'grade-proofs' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "grade proofs read" on storage.objects;
create policy "grade proofs read" on storage.objects for select to authenticated
  using (bucket_id = 'grade-proofs' and ((storage.foldername(name))[1] = (select auth.uid())::text
         or public.can_review_unit((storage.foldername(name))[2])));
drop policy if exists "grade proofs delete" on storage.objects;
create policy "grade proofs delete" on storage.objects for delete to authenticated
  using (bucket_id = 'grade-proofs' and ((storage.foldername(name))[1] = (select auth.uid())::text
         or public.can_review_unit((storage.foldername(name))[2])));

create table if not exists public.tutor_grade_proofs (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  course_code text not null check (course_code = public.norm_code(course_code) and char_length(course_code) between 3 and 20),
  grade_claimed text not null check (char_length(trim(grade_claimed)) between 1 and 10),
  file_path text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reason text check (reason is null or char_length(reason) <= 300),
  reviewer_id uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists grade_proofs_one_pending
  on public.tutor_grade_proofs (tutor_id, course_code) where status = 'pending';
create index if not exists grade_proofs_queue on public.tutor_grade_proofs (status, created_at);
create index if not exists fk_grade_proofs_reviewer on public.tutor_grade_proofs (reviewer_id);
alter table public.tutor_grade_proofs enable row level security;

drop policy if exists "tutor sends own proof" on public.tutor_grade_proofs;
create policy "tutor sends own proof" on public.tutor_grade_proofs for insert to authenticated
  with check (
    tutor_grade_proofs.tutor_id = (select auth.uid()) and tutor_grade_proofs.status = 'pending'
    and tutor_grade_proofs.reviewer_id is null and tutor_grade_proofs.reason is null
    and tutor_grade_proofs.file_path like (select auth.uid())::text || '/' || tutor_grade_proofs.course_code || '/%'
    and exists (select 1 from public.tutor_modules m
                where m.tutor_id = (select auth.uid())
                  and public.norm_code(m.course_code) = tutor_grade_proofs.course_code
                  and coalesce(trim(m.grade_achieved), '') = trim(tutor_grade_proofs.grade_claimed)));
drop policy if exists "proof seen by tutor and reviewers" on public.tutor_grade_proofs;
create policy "proof seen by tutor and reviewers" on public.tutor_grade_proofs for select to authenticated
  using (tutor_id = (select auth.uid()) or public.can_review_unit(course_code));
-- No update/delete for app users: decisions go through review_grade_proof().
grant select, insert on public.tutor_grade_proofs to authenticated;

-- C. Blue tick = Level 4. Worked out by the database only.
create or replace function public.recompute_tutor_verification(p_tutor uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s record; cur boolean; lessons int; upheld int; checked boolean;
begin
  select * into s from public.tutor_score(p_tutor);
  select tutor_verified into cur from public.profiles where id = p_tutor;
  select count(*) into lessons from public.tutor_requests where tutor_id = p_tutor and status = 'completed';
  select count(*) into upheld from public.tutor_reports where tutor_id = p_tutor and status = 'upheld';
  select exists (select 1 from public.tutor_modules where tutor_id = p_tutor and grade_checked and is_active) into checked;
  if not coalesce(cur, false) and checked and lessons >= 30 and s.score >= 4.3 and s.reviewers >= 5 and upheld = 0 then
    update public.profiles set tutor_verified = true, tutor_verified_at = now() where id = p_tutor;
  elsif coalesce(cur, false) and (not checked or s.score < 3.8 or upheld > 0) then
    update public.profiles set tutor_verified = false where id = p_tutor;
  end if;
end $$;
revoke execute on function public.recompute_tutor_verification(uuid) from public, anon, authenticated;

create or replace function public.tutor_trust_after() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.recompute_tutor_verification(new.tutor_id);
  return null;
end $$;
revoke execute on function public.tutor_trust_after() from public, anon, authenticated;
drop trigger if exists tutor_requests_trust on public.tutor_requests;
create trigger tutor_requests_trust after update of status on public.tutor_requests
  for each row when (new.status is distinct from old.status) execute function public.tutor_trust_after();
drop trigger if exists tutor_reports_trust on public.tutor_reports;
create trigger tutor_reports_trust after update of status on public.tutor_reports
  for each row when (new.status is distinct from old.status) execute function public.tutor_trust_after();
drop trigger if exists tutor_modules_trust on public.tutor_modules;
create trigger tutor_modules_trust after update of grade_checked, is_active on public.tutor_modules
  for each row execute function public.tutor_trust_after();

-- D. The reviewer's decision. Lecturer of the unit, or staff. Never yourself.
create or replace function public.review_grade_proof(p_proof uuid, p_approve boolean, p_reason text default null)
returns text language plpgsql security definer set search_path = public as $$
declare pr public.tutor_grade_proofs; n int;
begin
  select * into pr from public.tutor_grade_proofs where id = p_proof for update;
  if pr.id is null then raise exception 'That check was not found.'; end if;
  if pr.status <> 'pending' then raise exception 'Someone already decided this one.'; end if;
  if not public.can_review_unit(pr.course_code) then
    raise exception 'Only a lecturer of % or staff can check this.', pr.course_code;
  end if;
  if pr.tutor_id = (select auth.uid()) then raise exception 'You cannot check your own grades.'; end if;
  if not p_approve and char_length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'Say why it was not accepted, so the tutor can fix it.';
  end if;

  if p_approve then
    update public.tutor_modules set grade_checked = true, grade_checked_at = now()
     where tutor_id = pr.tutor_id and public.norm_code(course_code) = pr.course_code
       and coalesce(trim(grade_achieved), '') = trim(pr.grade_claimed);
    get diagnostics n = row_count;
    if n = 0 then
      raise exception 'The tutor changed this unit or grade after uploading. Reject it and ask them to upload again.';
    end if;
  end if;

  update public.tutor_grade_proofs
     set status = case when p_approve then 'approved' else 'rejected' end,
         reason = nullif(trim(coalesce(p_reason, '')), ''), reviewer_id = (select auth.uid()), reviewed_at = now()
   where id = p_proof;

  insert into public.notifications (user_id, kind, title, body, link)
  values (pr.tutor_id, 'tutor',
          case when p_approve then 'Grade checked: ' || pr.course_code else 'Grade not accepted: ' || pr.course_code end,
          case when p_approve then 'Students can now find you in tutor suggestions for ' || pr.course_code || '.'
               else trim(p_reason) end,
          '/tutors/profile');
  return pr.file_path;   -- the app deletes the slip; we don't keep it
end $$;
revoke execute on function public.review_grade_proof(uuid, boolean, text) from public, anon;
grant execute on function public.review_grade_proof(uuid, boolean, text) to authenticated;

-- E. Lessons, pause and upheld reports for each tutor, for the levels.
create or replace function public.tutor_trust()
returns table (tutor_id uuid, lessons int, paused boolean, upheld int)
language sql stable security definer set search_path = public as $$
  select p.id,
         (select count(*)::int from public.tutor_requests r where r.tutor_id = p.id and r.status = 'completed'),
         (select count(distinct t.reporter_id) >= 3 from public.tutor_reports t where t.tutor_id = p.id and t.status = 'open'),
         (select count(*)::int from public.tutor_reports t where t.tutor_id = p.id and t.status = 'upheld')
  from public.profiles p where p.is_tutor;
$$;
revoke execute on function public.tutor_trust() from public, anon;
grant execute on function public.tutor_trust() to authenticated;

-- F. Apply the new tick rule to everyone now.
do $$ declare r record; begin
  for r in select id from public.profiles where is_tutor or tutor_verified loop
    perform public.recompute_tutor_verification(r.id);
  end loop;
end $$;
