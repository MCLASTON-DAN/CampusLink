-- 0023: student numbers stop being visible to other students.
--
-- !! Run ONLY after the app version that reads profiles with named columns
-- !! (not select *) is live on web and Android. Older apps would fail to load
-- !! profiles after this. Safe to run more than once.
--
-- Before: any signed-in user could read every column of every profile,
-- including student_number. RLS works on rows, not columns, so the fix is
-- column privileges: everything except student_number stays readable.

revoke select on public.profiles from authenticated;
grant select (id, full_name, programme, year_of_study, faculty, role, is_tutor, tutor_subjects,
              is_buddy_mentor, created_at, tutor_verified, tutor_verified_at, avatar_path,
              status_text, status_until, username, username_changed_at, institution_id)
  on public.profiles to authenticated;

-- Your own student number (and only yours).
create or replace function public.my_private_profile() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('student_number', p.student_number)
  from public.profiles p where p.id = (select auth.uid());
$$;
revoke execute on function public.my_private_profile() from public, anon;
grant execute on function public.my_private_profile() to authenticated;

-- Staff who handle a student's request may need the number to find their file.
create or replace function public.request_student_number(p_request uuid) returns text
language sql stable security definer set search_path = public as $$
  select p.student_number
  from public.help_requests r join public.profiles p on p.id = r.student_id
  where r.id = p_request and public.can_handle_request(r.office_id);
$$;
revoke execute on function public.request_student_number(uuid) from public, anon;
grant execute on function public.request_student_number(uuid) to authenticated;

-- The old WhatsApp field was readable by every signed-in user. Move any
-- numbers into the private tutor_contacts table, then empty the old field.
insert into public.tutor_contacts (tutor_id, phone, phone_whatsapp)
select tp.tutor_id,
       case
         when d ~ '^0[0-9]{9}$' then '+256' || substr(d, 2)
         when d ~ '^256[0-9]{9}$' then '+' || d
         when d ~ '^7[0-9]{8}$' then '+256' || d
         else null
       end,
       true
from public.tutor_profiles tp,
     lateral (select regexp_replace(coalesce(tp.contact_whatsapp, ''), '[^0-9]', '', 'g') as d) x
where coalesce(tp.contact_whatsapp, '') <> ''
on conflict (tutor_id) do nothing;
update public.tutor_profiles set contact_whatsapp = null where contact_whatsapp is not null;
-- Keep it empty from now on (the new app saves numbers in tutor_contacts).
alter table public.tutor_profiles drop constraint if exists tutor_profiles_no_public_phone;
alter table public.tutor_profiles add constraint tutor_profiles_no_public_phone check (contact_whatsapp is null);
