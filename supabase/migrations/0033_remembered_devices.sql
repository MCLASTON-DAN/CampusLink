-- 0033: alert only on NEW devices (how Google, banks and Instagram do it).
--
-- Each phone or browser keeps a random secret "device code" (it survives
-- sign-out; clearing the browser or using incognito makes a new one).
-- Right after signing in, the app tells the server the code. The server keeps
-- only a hash of it (mixed with the account id), so a database leak can't be
-- used to pretend to be a known device.
--
-- About a minute after a sign-in, process_signin_alerts decides:
--   * the session came with a device code this account has used before
--     -> no alert (just recorded);
--   * no code arrived (older app): same kind of browser on the same network
--     as an earlier sign-in in the last 90 days -> no alert;
--   * otherwise -> alert by app, phone and email, as before.
-- Signing a device out from "Your devices", or "This wasn't me", forgets it,
-- so its next sign-in alerts again.

create table if not exists public.known_devices (
  user_id uuid not null references public.profiles (id) on delete cascade,
  device_hash text not null check (char_length(device_hash) = 64),
  label text,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (user_id, device_hash)
);
alter table public.known_devices enable row level security;
revoke all on public.known_devices from public, anon, authenticated;

create table if not exists public.session_devices (
  session_id uuid primary key references auth.sessions (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  device_hash text not null
);
alter table public.session_devices enable row level security;
revoke all on public.session_devices from public, anon, authenticated;

alter table public.signin_events add column if not exists outcome text
  check (outcome in ('alerted', 'known_device', 'known_network'));

-- Called by the app right after sign-in. Also names the session for
-- "Your devices" (phone model). Returns true if this device was known before.
create or replace function public.remember_device(p_code text, p_label text default null)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare
  me uuid := auth.uid();
  sid uuid := public.current_session_id();
  h text;
  seen timestamptz;
begin
  if me is null or sid is null then return false; end if;
  if p_code is null or p_code !~ '^[0-9a-f]{64}$' then raise exception 'Bad device code.'; end if;
  if not exists (select 1 from auth.sessions where id = sid and user_id = me) then return false; end if;
  h := encode(digest(me::text || ':' || p_code, 'sha256'), 'hex');

  select first_seen into seen from public.known_devices where user_id = me and device_hash = h;
  insert into public.known_devices (user_id, device_hash, label)
  values (me, h, nullif(left(btrim(coalesce(p_label, '')), 80), ''))
  on conflict (user_id, device_hash) do update
    set last_seen = now(), label = coalesce(excluded.label, known_devices.label);
  insert into public.session_devices (session_id, user_id, device_hash) values (sid, me, h)
  on conflict (session_id) do update set device_hash = excluded.device_hash;
  if p_label is not null and btrim(p_label) <> '' then
    insert into public.session_labels (session_id, user_id, label) values (sid, me, left(btrim(p_label), 80))
    on conflict (session_id) do update set label = excluded.label, updated_at = now();
  end if;
  -- At most 20 remembered devices per account; the oldest are forgotten.
  delete from public.known_devices where user_id = me and device_hash in
    (select device_hash from public.known_devices where user_id = me order by last_seen desc offset 20);
  return seen is not null;
end $$;
revoke execute on function public.remember_device(text, text) from public, anon;
grant execute on function public.remember_device(text, text) to authenticated;

-- How a sign-in should be treated (see top of file).
create or replace function public.signin_outcome(e public.signin_events)
returns text language sql stable set search_path = public as $$
  select case
    when exists (
      select 1 from public.session_devices sd
      join public.known_devices kd on kd.user_id = sd.user_id and kd.device_hash = sd.device_hash
      where sd.session_id = e.session_id and kd.first_seen < e.created_at - interval '5 seconds'
    ) then 'known_device'
    when not exists (select 1 from public.session_devices sd where sd.session_id = e.session_id)
     and exists (
      select 1 from public.signin_events p
      where p.user_id = e.user_id and p.id <> e.id
        and p.created_at < e.created_at and p.created_at > e.created_at - interval '90 days'
        and public.describe_user_agent(p.user_agent) = public.describe_user_agent(e.user_agent)
        and p.ip is not null and e.ip is not null
        and network(set_masklen(p.ip, case when family(p.ip) = 4 then 24 else 48 end))
            = network(set_masklen(e.ip, case when family(e.ip) = 4 then 24 else 48 end))
        and p.secured_at is null
    ) then 'known_network'
    else 'alerted'
  end;
$$;

-- Runs every minute. Waits 45 seconds so the app can report its device code.
create or replace function public.process_signin_alerts()
returns int language plpgsql security definer set search_path = public, extensions as $$
declare
  ids uuid[];
begin
  with due as (
    select e.* from public.signin_events e
    where e.alerted_at is null
      and e.created_at < now() - interval '45 seconds'
      and e.created_at > now() - interval '1 hour'
    for update skip locked
  ), decided as (
    update public.signin_events s
    set alerted_at = now(), outcome = public.signin_outcome(s)
    from due d where s.id = d.id
    returning s.*
  ), made as (
    insert into public.notifications (user_id, kind, priority, title, body, link)
    select d.user_id, 'security', 'urgent', 'New sign-in to your account',
           'Signed in on ' || public.signin_label(d.session_id, d.user_agent) || ', '
             || to_char(d.created_at at time zone 'Africa/Kampala', 'FMDay DD Mon "at" HH24:MI')
             || '. Not you? Open Your devices and sign it out.',
           '/account/devices'
    from decided d where d.outcome = 'alerted'
    returning 1
  )
  select array_agg(d.id) into ids from decided d, (select count(*) from made) m where d.outcome = 'alerted';

  if ids is not null then
    perform net.http_post(
      url := 'https://feklgmhzowwjwzuoscmy.supabase.co/functions/v1/security-alert',
      body := jsonb_build_object('ids', ids),
      headers := '{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds := 10000
    );
  end if;
  delete from public.signin_events where created_at < now() - interval '90 days';
  return coalesce(array_length(ids, 1), 0);
end $$;
revoke execute on function public.process_signin_alerts() from public, anon, authenticated;

-- Emails only for real alerts.
create or replace function public.claim_signin_emails(p_ids uuid[])
returns table (event_id uuid, email text, name text, device text, at_text text, ip text, token text)
language plpgsql security definer set search_path = public, extensions as $$
declare r record; t text;
begin
  for r in
    update public.signin_events e set emailed_at = now()
    where e.id = any (p_ids) and e.emailed_at is null and e.outcome = 'alerted'
      and e.created_at > now() - interval '2 hours'
    returning e.*
  loop
    t := encode(gen_random_bytes(24), 'hex');
    update public.signin_events set secure_token_hash = encode(digest(t, 'sha256'), 'hex') where id = r.id;
    return query
      select r.id, u.email::text, coalesce(nullif(p.display_name, ''), p.full_name, 'there'),
             public.signin_label(r.session_id, r.user_agent),
             to_char(r.created_at at time zone 'Africa/Kampala', 'FMDay DD Mon YYYY "at" HH24:MI') || ' (Kampala time)',
             host(r.ip), t
      from auth.users u join public.profiles p on p.id = u.id
      where u.id = r.user_id and u.email is not null;
  end loop;
end $$;
revoke execute on function public.claim_signin_emails(uuid[]) from public, anon, authenticated;
grant execute on function public.claim_signin_emails(uuid[]) to service_role;

-- Signing a device out from "Your devices" also stops trusting it.
create or replace function public.end_session(p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'Please sign in first.' using errcode = '42501'; end if;
  if p_id = public.current_session_id() then raise exception 'Use Sign out to leave this device.'; end if;
  delete from public.known_devices kd using public.session_devices sd
  where sd.session_id = p_id and sd.user_id = auth.uid() and kd.user_id = sd.user_id and kd.device_hash = sd.device_hash;
  delete from auth.sessions where id = p_id and user_id = auth.uid();
  get diagnostics n = row_count;
  return n > 0;
end $$;

create or replace function public.end_other_sessions()
returns int language plpgsql security definer set search_path = public as $$
declare n int; sid uuid := public.current_session_id();
begin
  if auth.uid() is null or sid is null then raise exception 'Please sign in first.' using errcode = '42501'; end if;
  delete from public.known_devices kd
  where kd.user_id = auth.uid()
    and kd.device_hash is distinct from (select device_hash from public.session_devices where session_id = sid);
  delete from auth.sessions where user_id = auth.uid() and id <> sid;
  get diagnostics n = row_count;
  return n;
end $$;

-- "This wasn't me": sign out everywhere and trust no device.
create or replace function public.secure_account(p_token text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare e public.signin_events; n int;
begin
  select * into e from public.signin_events
  where secure_token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if not found or e.created_at < now() - interval '7 days' then return 'expired'; end if;
  if e.secured_at is not null then return 'done'; end if;
  delete from auth.sessions where user_id = e.user_id;
  get diagnostics n = row_count;
  delete from public.push_tokens where user_id = e.user_id;
  delete from public.known_devices where user_id = e.user_id;
  update public.signin_events set secured_at = now() where id = e.id;
  insert into public.notifications (user_id, kind, priority, title, body, link)
  values (e.user_id, 'security', 'urgent', 'All devices were signed out',
          'You used "This wasn''t me". Every device (' || n || ') was signed out and must sign in again. Secure your Google account or change your password.',
          '/account/devices');
  return 'ok';
end $$;
revoke execute on function public.secure_account(text) from public, anon, authenticated;
grant execute on function public.secure_account(text) to service_role;
