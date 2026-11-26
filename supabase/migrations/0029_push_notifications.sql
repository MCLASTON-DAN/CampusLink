-- 0029: phone alerts that arrive even when CampusLink is closed (Firebase Cloud Messaging).
--
-- How it flows:
--   1. The app gives the server its device token (register_push_token).
--   2. Any new row in notifications fires one statement-level trigger, which
--      queues a call to the send-push edge function with the new ids
--      (pg_net only sends it after the transaction commits).
--   3. send-push calls claim_push_batch, which marks each notification as
--      pushed exactly once and returns only the devices that should ring
--      (respects the person's kinds and quiet hours; urgent always rings).
-- The secret Firebase key lives only in the edge function's secrets.

create extension if not exists pg_net with schema extensions;

-- ---------------------------------------------------------------- tokens
create table if not exists public.push_tokens (
  token text primary key check (char_length(token) between 20 and 4096),
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null default 'android' check (platform in ('android', 'ios', 'web')),
  updated_at timestamptz not null default now()
);
create index if not exists push_tokens_user on public.push_tokens (user_id);
alter table public.push_tokens enable row level security;
-- Nobody reads or writes this table directly; only the functions below.
revoke all on public.push_tokens from public, anon, authenticated;

create or replace function public.register_push_token(p_token text, p_platform text default 'android')
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Please sign in first.' using errcode = '42501'; end if;
  if p_token is null or char_length(p_token) not between 20 and 4096 then raise exception 'That device code is not valid.'; end if;
  if p_platform not in ('android', 'ios', 'web') then raise exception 'Unknown device type.'; end if;
  -- A shared phone moves to whoever signed in last.
  insert into public.push_tokens (token, user_id, platform, updated_at)
  values (p_token, me, p_platform, now())
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
  -- At most 5 devices per person; the oldest drop off.
  delete from public.push_tokens
  where user_id = me
    and token in (select token from public.push_tokens where user_id = me order by updated_at desc offset 5);
end $$;

create or replace function public.unregister_push_token(p_token text)
returns void language sql security definer set search_path = public as $$
  delete from public.push_tokens where token = p_token and user_id = auth.uid();
$$;

revoke execute on function public.register_push_token(text, text) from public, anon;
revoke execute on function public.unregister_push_token(text) from public, anon;
grant execute on function public.register_push_token(text, text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;

-- ---------------------------------------------------------------- settings
-- Replies and mentions (kind 'social', added in 0028) are on by default.
alter table public.user_settings
  alter column notify_kinds set default '{course,official,event,tutor,request,office,access,group,social}';
update public.user_settings set notify_kinds = notify_kinds || '{social}'
where not ('social' = any (notify_kinds));

-- Same rule as the app: an overnight window (22:00-06:00) wraps past midnight.
create or replace function public.in_quiet_hours(p_on boolean, p_start time, p_end time, p_at timestamptz default now())
returns boolean language sql stable set search_path = public as $$
  select p_on and case
    when p_start <= p_end then (p_at at time zone 'Africa/Kampala')::time >= p_start and (p_at at time zone 'Africa/Kampala')::time < p_end
    else (p_at at time zone 'Africa/Kampala')::time >= p_start or (p_at at time zone 'Africa/Kampala')::time < p_end
  end;
$$;

-- ---------------------------------------------------------------- claim
alter table public.notifications add column if not exists pushed_at timestamptz;

-- Marks each notification pushed once (so a repeated call never rings twice)
-- and returns one row per device that should ring. Only the edge function
-- (service role) may call it.
create or replace function public.claim_push_batch(p_ids uuid[])
returns table (notification_id uuid, token text, title text, body text, link text, kind text, urgent boolean)
language sql security definer set search_path = public as $$
  with claimed as (
    update public.notifications n set pushed_at = now()
    where n.id = any (p_ids)
      and n.pushed_at is null
      and n.read_at is null
      and n.created_at > now() - interval '15 minutes'
    returning n.id, n.user_id, n.title, n.body, n.link, n.kind, n.priority
  )
  select c.id, t.token, c.title, c.body, c.link, c.kind, c.priority = 'urgent'
  from claimed c
  join public.push_tokens t on t.user_id = c.user_id
  join public.profiles p on p.id = c.user_id
  left join public.user_settings s on s.user_id = c.user_id
  where p.closing_at is null                                   -- closing accounts stay quiet
    and (p.access_until is null or p.access_until > now())     -- guests whose time ended
    and (
      c.priority = 'urgent'
      or (
        c.kind = any (coalesce(s.notify_kinds, '{course,official,event,tutor,request,office,access,group,social}'))
        and not public.in_quiet_hours(coalesce(s.quiet_enabled, true), coalesce(s.quiet_start, '22:00'), coalesce(s.quiet_end, '06:00'))
      )
    );
$$;

-- Firebase says a device code is dead (app removed, signed out): forget it.
create or replace function public.drop_push_tokens(p_tokens text[])
returns void language sql security definer set search_path = public as $$
  delete from public.push_tokens where token = any (p_tokens);
$$;

revoke execute on function public.claim_push_batch(uuid[]) from public, anon, authenticated;
revoke execute on function public.drop_push_tokens(text[]) from public, anon, authenticated;
grant execute on function public.claim_push_batch(uuid[]) to service_role;
grant execute on function public.drop_push_tokens(text[]) to service_role;

-- ---------------------------------------------------------------- trigger
create or replace function public.push_new_notifications() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare
  ids uuid[];
  i int := 1;
begin
  select array_agg(id) into ids from new_rows
  where read_at is null and exists (select 1 from public.push_tokens t where t.user_id = new_rows.user_id);
  if ids is null then return null; end if;
  -- 300 per call keeps each edge-function run short.
  while i <= array_length(ids, 1) loop
    perform net.http_post(
      url := 'https://feklgmhzowwjwzuoscmy.supabase.co/functions/v1/send-push',
      body := jsonb_build_object('ids', ids[i:i + 299]),
      headers := '{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds := 10000
    );
    i := i + 300;
  end loop;
  return null;
end $$;
revoke execute on function public.push_new_notifications() from public, anon, authenticated;

drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push
  after insert on public.notifications
  referencing new table as new_rows
  for each statement execute function public.push_new_notifications();
