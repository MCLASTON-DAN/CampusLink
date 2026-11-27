-- 0030: sign-in security.
--   1. New sign-in alert: every new sign-in (a new session) is recorded by the
--      database itself, so a changed app can't skip it. About a minute later
--      the owner gets an in-app alert + phone alert (urgent, ignores quiet
--      hours) and an email.
--   2. "This wasn't me": the email carries a one-time link (7 days) that signs
--      out every device.
--   3. Your devices: list where you're signed in and sign any of them out.
-- A brand-new account's first sign-in is not alerted (that's the person
-- signing up). Records are kept 90 days.

-- ------------------------------------------------------------------ kinds
do $$
declare c text;
begin
  select conname into c from pg_constraint
  where conrelid = 'public.notifications'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%kind%';
  if c is not null then execute format('alter table public.notifications drop constraint %I', c); end if;
end $$;
alter table public.notifications add constraint notifications_kind_check check (kind in
  ('course', 'official', 'event', 'tutor', 'request', 'office', 'access', 'group', 'social', 'security'));

-- ------------------------------------------------------------------ naming
-- "Chrome on Windows", "the CampusLink app"… from the browser's user agent.
create or replace function public.describe_user_agent(p_ua text)
returns text language sql immutable set search_path = public as $$
  select case
    when p_ua is null or p_ua = '' then 'an unknown device'
    when p_ua ilike 'Dart/%' or p_ua ilike '%CampusLink%' then 'the CampusLink app'
    else
      case
        when p_ua ~* 'Edg/' then 'Edge'
        when p_ua ~* 'OPR/|Opera' then 'Opera'
        when p_ua ~* 'SamsungBrowser' then 'Samsung Internet'
        when p_ua ~* 'Firefox/' then 'Firefox'
        when p_ua ~* 'Chrome/|CriOS/' then 'Chrome'
        when p_ua ~* 'Safari/' then 'Safari'
        else 'A browser'
      end || ' on ' ||
      case
        when p_ua ~* 'Android' then 'Android'
        when p_ua ~* 'iPhone|iPad|iPod' then 'iPhone/iPad'
        when p_ua ~* 'Windows' then 'Windows'
        when p_ua ~* 'Macintosh|Mac OS' then 'Mac'
        when p_ua ~* 'CrOS' then 'Chromebook'
        when p_ua ~* 'Linux' then 'Linux'
        else 'an unknown system'
      end
  end;
$$;

-- The app names its own session ("Samsung SM-A515F"), because every phone app
-- reports the same user agent.
create table if not exists public.session_labels (
  session_id uuid primary key references auth.sessions (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  label text not null check (char_length(label) between 1 and 80),
  updated_at timestamptz not null default now()
);
alter table public.session_labels enable row level security;
revoke all on public.session_labels from public, anon, authenticated;

create or replace function public.current_session_id()
returns uuid language sql stable set search_path = public as $$
  select nullif(auth.jwt() ->> 'session_id', '')::uuid;
$$;

create or replace function public.label_my_session(p_label text)
returns void language plpgsql security definer set search_path = public as $$
declare sid uuid := public.current_session_id();
begin
  if auth.uid() is null or sid is null then return; end if;
  if not exists (select 1 from auth.sessions where id = sid and user_id = auth.uid()) then return; end if;
  insert into public.session_labels (session_id, user_id, label)
  values (sid, auth.uid(), left(btrim(p_label), 80))
  on conflict (session_id) do update set label = excluded.label, updated_at = now();
end $$;

-- Phone alerts follow the session: when a device is signed out (by itself or
-- remotely), its alert code goes too.
alter table public.push_tokens add column if not exists session_id uuid references auth.sessions (id) on delete cascade;

create or replace function public.register_push_token(p_token text, p_platform text default 'android')
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Please sign in first.' using errcode = '42501'; end if;
  if p_token is null or char_length(p_token) not between 20 and 4096 then raise exception 'That device code is not valid.'; end if;
  if p_platform not in ('android', 'ios', 'web') then raise exception 'Unknown device type.'; end if;
  insert into public.push_tokens (token, user_id, platform, session_id, updated_at)
  values (p_token, me, p_platform, public.current_session_id(), now())
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform,
    session_id = excluded.session_id, updated_at = now();
  delete from public.push_tokens
  where user_id = me
    and token in (select token from public.push_tokens where user_id = me order by updated_at desc offset 5);
end $$;

-- ------------------------------------------------------------------ events
create table if not exists public.signin_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  session_id uuid,                 -- no link: the record outlives the session
  user_agent text,
  ip inet,
  created_at timestamptz not null default now(),
  alerted_at timestamptz,          -- in-app + phone alert made
  emailed_at timestamptz,          -- email handed to Brevo
  secure_token_hash text,          -- sha256 of the "this wasn't me" link
  secured_at timestamptz           -- that link was used
);
create index if not exists signin_events_pending on public.signin_events (created_at) where alerted_at is null;
create index if not exists signin_events_user on public.signin_events (user_id, created_at desc);
alter table public.signin_events enable row level security;
revoke all on public.signin_events from public, anon, authenticated;

create or replace function public.record_signin() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Never let this block a sign-in.
  begin
    if exists (select 1 from public.profiles p where p.id = new.user_id)
       and not exists (select 1 from auth.users u where u.id = new.user_id and u.created_at > now() - interval '10 minutes') then
      insert into public.signin_events (user_id, session_id, user_agent, ip)
      values (new.user_id, new.id, left(new.user_agent, 400), new.ip);
    end if;
  exception when others then
    raise warning 'record_signin: %', sqlerrm;
  end;
  return new;
end $$;
revoke execute on function public.record_signin() from public, anon, authenticated;

drop trigger if exists campuslink_record_signin on auth.sessions;
create trigger campuslink_record_signin after insert on auth.sessions
  for each row execute function public.record_signin();

-- What a sign-in is called in alerts and in Your devices.
create or replace function public.signin_label(p_session uuid, p_ua text)
returns text language sql stable set search_path = public as $$
  select coalesce((select label || ' (CampusLink app)' from public.session_labels where session_id = p_session),
                  public.describe_user_agent(p_ua));
$$;

-- Runs every minute. Waits 20 seconds so the app can name its device first.
create or replace function public.process_signin_alerts()
returns int language plpgsql security definer set search_path = public, extensions as $$
declare
  ids uuid[];
begin
  with due as (
    update public.signin_events e set alerted_at = now()
    where e.alerted_at is null
      and e.created_at < now() - interval '20 seconds'
      and e.created_at > now() - interval '1 hour'
    returning e.*
  ), made as (
    insert into public.notifications (user_id, kind, priority, title, body, link)
    select d.user_id, 'security', 'urgent', 'New sign-in to your account',
           'Signed in on ' || public.signin_label(d.session_id, d.user_agent) || ', '
             || to_char(d.created_at at time zone 'Africa/Kampala', 'FMDay DD Mon "at" HH24:MI')
             || '. Not you? Open Your devices and sign it out.',
           '/account/devices'
    from due d
    returning 1
  )
  select array_agg(d.id) into ids from due d, (select count(*) from made) m;

  if ids is not null then
    perform net.http_post(
      url := 'https://feklgmhzowwjwzuoscmy.supabase.co/functions/v1/security-alert',
      body := jsonb_build_object('ids', ids),
      headers := '{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds := 10000
    );
  end if;
  -- Forget old records.
  delete from public.signin_events where created_at < now() - interval '90 days';
  return coalesce(array_length(ids, 1), 0);
end $$;
revoke execute on function public.process_signin_alerts() from public, anon, authenticated;

-- ------------------------------------------------------------------ email
-- For the security-alert function only: claims each email once and makes the
-- one-time "this wasn't me" code (only its hash is kept).
create or replace function public.claim_signin_emails(p_ids uuid[])
returns table (event_id uuid, email text, name text, device text, at_text text, ip text, token text)
language plpgsql security definer set search_path = public, extensions as $$
declare r record; t text;
begin
  for r in
    update public.signin_events e set emailed_at = now()
    where e.id = any (p_ids) and e.emailed_at is null and e.alerted_at is not null
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

-- "This wasn't me": signs out every device of that account. One use, 7 days.
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
  update public.signin_events set secured_at = now() where id = e.id;
  insert into public.notifications (user_id, kind, priority, title, body, link)
  values (e.user_id, 'security', 'urgent', 'All devices were signed out',
          'You used "This wasn''t me". Every device (' || n || ') was signed out. Secure your Google account or change your password.',
          '/account/devices');
  return 'ok';
end $$;

revoke execute on function public.claim_signin_emails(uuid[]) from public, anon, authenticated;
revoke execute on function public.secure_account(text) from public, anon, authenticated;
grant execute on function public.claim_signin_emails(uuid[]) to service_role;
grant execute on function public.secure_account(text) to service_role;

-- ------------------------------------------------------------------ devices
create or replace function public.my_sessions()
returns table (id uuid, device text, signed_in_at timestamptz, last_active_at timestamptz, ip text, current boolean)
language sql stable security definer set search_path = public as $$
  select s.id, public.signin_label(s.id, s.user_agent), s.created_at,
         greatest(s.created_at, s.updated_at, (s.refreshed_at at time zone 'utc')),
         host(s.ip), s.id = public.current_session_id()
  from auth.sessions s
  where s.user_id = auth.uid() and (s.not_after is null or s.not_after > now())
  order by s.id = public.current_session_id() desc, greatest(s.created_at, s.updated_at) desc;
$$;

-- Sign out one other device (not this one: use the normal sign-out for that).
create or replace function public.end_session(p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'Please sign in first.' using errcode = '42501'; end if;
  if p_id = public.current_session_id() then raise exception 'Use Sign out to leave this device.'; end if;
  delete from auth.sessions where id = p_id and user_id = auth.uid();
  get diagnostics n = row_count;
  return n > 0;
end $$;

create or replace function public.end_other_sessions()
returns int language plpgsql security definer set search_path = public as $$
declare n int; sid uuid := public.current_session_id();
begin
  if auth.uid() is null or sid is null then raise exception 'Please sign in first.' using errcode = '42501'; end if;
  delete from auth.sessions where user_id = auth.uid() and id <> sid;
  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function public.label_my_session(text) from public, anon;
revoke execute on function public.my_sessions() from public, anon;
revoke execute on function public.end_session(uuid) from public, anon;
revoke execute on function public.end_other_sessions() from public, anon;
grant execute on function public.label_my_session(text) to authenticated;
grant execute on function public.my_sessions() to authenticated;
grant execute on function public.end_session(uuid) to authenticated;
grant execute on function public.end_other_sessions() to authenticated;

-- ------------------------------------------------------------------ schedule
select cron.unschedule(jobid) from cron.job where jobname = 'campuslink-signin-alerts';
select cron.schedule('campuslink-signin-alerts', '* * * * *', 'select public.process_signin_alerts()');
