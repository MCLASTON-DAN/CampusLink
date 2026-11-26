-- 0025: required app updates, enforced by the database.
--
-- The super admin can say "Android apps older than build N must update"
-- (optionally from a future date, so people get a warning first). The app
-- shows a full-screen "Update required" page, and this gate makes sure an old
-- app that ignores that page still gets no data: every API request from it is
-- refused with HTTP 426 "Upgrade Required".
--
-- Never blocks: the website (browsers send an Origin header), iOS/desktop
-- builds, people not signed in, or the update-policy call itself. Any error
-- inside the check lets the request through, so a mistake here can't take
-- the whole app down. Safe to run more than once.

insert into public.app_settings (key, value) values
  ('android_min_build', '0'),           -- 0 = no update required
  ('android_min_build_from', '')        -- empty = required straight away
on conflict (key) do nothing;

-- What the app asks on start-up: "must I update, and from when?"
create or replace function public.app_update_policy() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare minb int := 0; frm timestamptz;
begin
  begin
    select coalesce(nullif(value, '')::int, 0) into minb from public.app_settings where key = 'android_min_build';
    select nullif(value, '')::timestamptz into frm from public.app_settings where key = 'android_min_build_from';
  exception when others then
    minb := 0; frm := null;
  end;
  return jsonb_build_object('min_build', coalesce(minb, 0), 'required_from', frm);
end $$;
revoke execute on function public.app_update_policy() from public;
grant execute on function public.app_update_policy() to anon, authenticated;

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
    h := nullif(current_setting('request.headers', true), '')::json;
    if h is null then return; end if;
    if coalesce(current_setting('request.path', true), '') like '%app_update_policy%' then return; end if;
    if coalesce(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role', 'anon') <> 'authenticated' then
      return;
    end if;
    select nullif(value, '')::int into minb from public.app_settings where key = 'android_min_build';
    if coalesce(minb, 0) <= 0 then return; end if;
    select nullif(value, '')::timestamptz into frm from public.app_settings where key = 'android_min_build_from';
    if frm is not null and now() < frm then return; end if;
    plat := lower(coalesce(h ->> 'x-app-platform', ''));
    if plat = '' then
      if (h ->> 'origin') is not null then return; end if; -- a browser: the website
      b := 0;                                               -- an Android app from before this check
    elsif plat <> 'android' then
      return;
    else
      b := coalesce(nullif(h ->> 'x-app-build', '')::int, 0);
    end if;
    if b >= minb then return; end if;
  exception when others then
    return; -- never lock everyone out because of a bug in this check
  end;
  raise sqlstate 'PT426' using message = 'CAMPUSLINK_UPDATE_REQUIRED',
    hint = 'This version of CampusLink is too old. Update the app to keep using it.';
end $$;
revoke execute on function public.app_version_gate() from public;
grant execute on function public.app_version_gate() to anon, authenticated;

-- Run the gate before every API request.
alter role authenticator set pgrst.db_pre_request = 'public.app_version_gate';
notify pgrst, 'reload config';
