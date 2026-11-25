-- 0013: one complaint = one row, and an office list to choose from.
-- Safe to run more than once.

-- A. The first timeline line ("Request submitted.") is written by the
--    database in the same step as the request. The app no longer sends it
--    separately, so a failure can't leave a half-saved request that the
--    student then submits again.
create or replace function public.help_request_first_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.help_request_updates (request_id, author_id, message, new_status)
  values (new.id, new.student_id, 'Request submitted.', 'open');
  return new;
end $$;
revoke execute on function public.help_request_first_update() from public, anon, authenticated;
drop trigger if exists help_request_first_update on public.help_requests;
create trigger help_request_first_update after insert on public.help_requests
  for each row execute function public.help_request_first_update();

-- B. Students may move their own OPEN request to another office, but may not
--    mark it resolved/closed themselves or hand it to someone else.
--    Staff keep full control.
drop policy if exists "staff update request" on public.help_requests;
create policy "staff update request" on public.help_requests for update to authenticated
  using (public.is_staff() or (student_id = (select auth.uid()) and status in ('open', 'in_progress')))
  with check (public.is_staff() or student_id = (select auth.uid()));

create or replace function public.help_request_student_limits() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  -- Guard only applies to normal app users who are not staff.
  if current_user in ('authenticated', 'anon') and not public.is_staff() then
    if new.status is distinct from old.status and new.status not in ('open', 'closed') then
      raise exception 'Only the office can change the status of a request.';
    end if;
    if new.student_id is distinct from old.student_id then
      raise exception 'A request cannot be handed to another student.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists help_request_student_limits on public.help_requests;
create trigger help_request_student_limits before update on public.help_requests
  for each row execute function public.help_request_student_limits();

-- C. Offices: only if the list is empty. Names and what each office handles;
--    contact details are left empty on purpose for the super admin to fill
--    in with the real ones (Directory -> office -> Edit).
insert into public.help_offices (name, description, category, location, building, keywords)
select * from (values
  ('Registrar''s Office', 'Registration, course add/drop, transcripts, ID cards, admission letters.', 'admin', 'Main Block', 'Main Block', '{registration,transcript,id card,admission letter,add,drop,enrol,defer}'::text[]),
  ('Finance Office', 'Tuition payments, fee statements, payment plans, bursaries.', 'finance', 'Main Block', 'Main Block', '{fees,tuition,payment,receipt,bursary,scholarship,balance}'::text[]),
  ('ICT Help Desk', 'Student portal login, email, Wi-Fi, e-learning problems.', 'it', 'Library Block', 'Library Block', '{portal,password,wifi,email,elearning,login,laptop}'::text[]),
  ('Library', 'Borrowing, e-resources, study spaces, printing.', 'library', 'Library Block', 'Library Block', '{books,borrow,ebook,journal,print,study room}'::text[]),
  ('Dean of Students', 'Welfare, accommodation, discipline, clubs and societies, complaints.', 'welfare', 'Students'' Centre', 'Students'' Centre', '{hostel,accommodation,welfare,club,complaint,discipline}'::text[]),
  ('Counselling & Wellness', 'Confidential counselling and wellbeing support.', 'health', 'Students'' Centre', 'Students'' Centre', '{counselling,stress,mental health,wellbeing,talk}'::text[]),
  ('Faculty of Science & Technology Office', 'Course advising, timetables and exam queries for FST programmes.', 'academic', 'FST Block', 'FST Block', '{timetable,exam,results,missing marks,lecturer,course unit,fst}'::text[]),
  ('Examinations Office', 'Exam cards, results, remarking, missing marks.', 'academic', 'Main Block', 'Main Block', '{exam card,results,remark,missing marks,retake}'::text[]),
  ('Careers & Internships', 'CV reviews, internship placement, job board.', 'academic', 'Students'' Centre', 'Students'' Centre', '{internship,cv,job,career,placement}'::text[])
) as v(name, description, category, location, building, keywords)
where not exists (select 1 from public.help_offices);
