-- 0026: the update gate runs before every API request, so make the common
-- case (no update required) as cheap as possible: one indexed lookup, then
-- stop. Same rules as 0025 otherwise. Safe to run more than once.
create or replace function public.app_version_gate() returns void
language plpgsql stable security definer set search_path = public as $$
declare
  h json;
  plat text;
  b int;
  minb int;
  frm timestamptz;
begin
  begin
    -- Fast path: nothing required -> nothing to check.
    select nullif(value, '')::int into minb from public.app_settings where key = 'android_min_build';
    if coalesce(minb, 0) <= 0 then return; end if;

    h := nullif(current_setting('request.headers', true), '')::json;
    if h is null then return; end if;
    if coalesce(current_setting('request.path', true), '') like '%app_update_policy%' then return; end if;
    if coalesce(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role', 'anon') <> 'authenticated' then
      return;
    end if;
    select nullif(value, '')::timestamptz into frm from public.app_settings where key = 'android_min_build_from';
    if frm is not null and now() < frm then return; end if;
    plat := lower(coalesce(h ->> 'x-app-platform', ''));
    if plat = '' then
      if (h ->> 'origin') is not null then return; end if;
      b := 0;
    elsif plat <> 'android' then
      return;
    else
      b := coalesce(nullif(h ->> 'x-app-build', '')::int, 0);
    end if;
    if b >= minb then return; end if;
  exception when others then
    return;
  end;
  raise sqlstate 'PT426' using message = 'CAMPUSLINK_UPDATE_REQUIRED',
    hint = 'This version of CampusLink is too old. Update the app to keep using it.';
end $$;
