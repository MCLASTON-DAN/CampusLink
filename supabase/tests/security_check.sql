-- CampusLink security check. Paste into the Supabase SQL editor and run.
-- It acts as a normal student and tries things that must be blocked, then
-- undoes everything. Expected: the error message lists only "blocked" / "OK".
-- Any line marked (BAD) is a security hole: stop and fix it.
-- Change the two emails to any existing student and super admin.
do $$
declare stu uuid; admin uuid; n int; out text := '';
begin
  select id into stu from auth.users where email = 'opolotemmanuel288@gmail.com';
  select id into admin from auth.users where email = 'againmeag@gmail.com';

  perform set_config('request.jwt.claims', json_build_object('sub', stu, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin update public.profiles set role = 'super_admin' where id = stu; out := out || 'SELF-PROMOTE (BAD)';
  exception when others then out := out || 'self-promote blocked'; end;
  begin update public.profiles set tutor_verified = true where id = stu; out := out || ' | FAKE BLUE TICK (BAD)';
  exception when others then out := out || ' | fake blue tick blocked'; end;
  begin update public.profiles set avatar_path = 'https://evil.example/x.jpg' where id = stu; out := out || ' | FOREIGN PHOTO (BAD)';
  exception when others then out := out || ' | foreign photo blocked'; end;
  begin update public.profiles set username = 'admin.boss' where id = stu; out := out || ' | RESERVED NAME (BAD)';
  exception when others then out := out || ' | reserved name blocked'; end;
  begin perform * from public.search_people('a'); out := out || ' | STUDENT SEARCH (BAD)';
  exception when others then out := out || ' | student search blocked'; end;
  update public.posts set title = 'x' where true; get diagnostics n = row_count;
  out := out || case when n > 0 then ' | EDITED OTHERS POSTS (BAD)' else ' | others posts locked' end;
  select count(*) into n from public.notifications where user_id <> stu;
  out := out || case when n > 0 then ' | SEES OTHERS NOTIFICATIONS (BAD)' else ' | notifications private' end;
  select count(*) into n from public.timetable_entries where user_id <> stu;
  out := out || case when n > 0 then ' | SEES OTHERS TIMETABLES (BAD)' else ' | timetables private' end;
  begin update public.profiles set status_text = 'test' where id = stu; out := out || ' | normal edit OK';
  exception when others then out := out || ' | NORMAL EDIT BROKEN'; end;
  reset role;

  perform set_config('request.jwt.claims', json_build_object('sub', admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.set_user_role(admin, 'student'); out := out || ' | LAST SUPER ADMIN DEMOTED (BAD)';
  exception when others then out := out || ' | last super admin protected'; end;
  reset role;

  raise exception 'RESULT (nothing was saved): %', out;
end $$;
