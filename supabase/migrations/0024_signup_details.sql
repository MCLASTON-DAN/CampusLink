-- 0024: details typed on the sign-up form (programme, year, student number)
-- reach the profile even when email confirmation is on.
--
-- Before: the app wrote them after sign-up, but with confirmation on nobody is
-- signed in yet, so the write was refused and the details were lost.
-- Now: they travel with the sign-up and the database copies them, checking
-- each one. Role, badges and the like are never taken from sign-up data.
-- Safe to run more than once.

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  md jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  yr int;
  sn text := nullif(left(trim(md ->> 'student_number'), 20), '');
  prog text := nullif(left(trim(md ->> 'programme'), 80), '');
begin
  begin
    yr := (md ->> 'year_of_study')::int;
    if yr not between 1 and 7 then yr := null; end if;
  exception when others then yr := null;
  end;
  if sn is not null and sn !~ '^[A-Za-z0-9/-]{3,20}$' then sn := null; end if;
  insert into public.profiles (id, full_name, institution_id, student_number, programme, year_of_study)
  values (new.id,
          left(coalesce(md ->> 'full_name', md ->> 'name', ''), 120),
          (select m.institution_id from public.match_school_email(new.email) m limit 1),
          sn, prog, yr)
  on conflict (id) do nothing;
  return new;
end $$;
