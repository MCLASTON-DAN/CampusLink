-- CampusLink 0010: never lose the last super admin; drop an unused door.
create or replace function public.set_user_role(p_user uuid, p_role text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_super_admin() then
    raise exception 'Only a super admin can change roles' using errcode = '42501';
  end if;
  if p_role not in ('student','staff','admin','super_admin') then
    raise exception 'Unknown role';
  end if;
  if p_role <> 'super_admin'
     and (select role from public.profiles where id = p_user) = 'super_admin'
     and (select count(*) from public.profiles where role = 'super_admin') <= 1 then
    raise exception 'This is the only super admin. Make someone else super admin first.';
  end if;
  update public.profiles set role = p_role where id = p_user;
end $$;
revoke execute on function public.set_user_role(uuid, text) from public, anon;
grant execute on function public.set_user_role(uuid, text) to authenticated;

-- Lecturers are now chosen by username search; the email lookup is unused.
drop function if exists public.assign_lecturer(text, text);
