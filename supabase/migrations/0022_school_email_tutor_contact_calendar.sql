-- 0022: school emails only, institutions and their email types, tutor price and
-- private contact details, "do I have a password?", and a private calendar feed.
-- Safe to run more than once. Existing accounts are never locked out.

-- =========================================================================
-- 1. Institutions and the email types they use
-- =========================================================================
create table if not exists public.institutions (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(name) between 3 and 120),
  short_name text check (short_name is null or char_length(short_name) <= 20),
  -- Who runs the school's email. 'google' means a school Google account can
  -- also open Google Calendar.
  calendar_provider text not null default 'none' check (calendar_provider in ('google', 'microsoft', 'none')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.institution_email_domains (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  -- e.g. 'students.cavendish.ac.ug' (exact) or 'cavendish.ac.ug' + include_subdomains
  -- (which then also accepts staff.cavendish.ac.ug, fst.cavendish.ac.ug, ...).
  domain text not null unique
    check (domain ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'),
  include_subdomains boolean not null default false,
  account_kind text not null default 'any' check (account_kind in ('student', 'staff', 'any')),
  -- Optional rule for the part before @, e.g. '^[a-z]{2}[0-9]{6}$' for od251945.
  local_part_pattern text check (local_part_pattern is null or char_length(local_part_pattern) <= 100),
  example text check (example is null or char_length(example) <= 120),
  is_active boolean not null default true,
  added_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists institution_email_domains_inst on public.institution_email_domains (institution_id);
create index if not exists fk_institution_email_domains_added_by on public.institution_email_domains (added_by);

-- Named people allowed in without a school email (a visiting lecturer, the
-- founding super admin). Everyone who already has an account keeps it anyway.
create table if not exists public.email_exceptions (
  email text primary key check (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  reason text not null check (char_length(reason) between 3 and 200),
  expires_at timestamptz,
  added_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists fk_email_exceptions_added_by on public.email_exceptions (added_by);

-- Clean up and check what a super admin types before it is saved.
create or replace function public.email_domain_tidy() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  new.domain := lower(trim(both '.@ ' from new.domain));
  if new.local_part_pattern is not null then
    new.local_part_pattern := nullif(trim(new.local_part_pattern), '');
    begin
      perform 'test' ~ new.local_part_pattern;
    exception when others then
      raise exception 'That email rule is not a valid pattern.';
    end;
  end if;
  return new;
end $$;
drop trigger if exists email_domain_tidy on public.institution_email_domains;
create trigger email_domain_tidy before insert or update on public.institution_email_domains
  for each row execute function public.email_domain_tidy();

alter table public.institutions enable row level security;
alter table public.institution_email_domains enable row level security;
alter table public.email_exceptions enable row level security;
revoke all on public.institutions, public.institution_email_domains, public.email_exceptions from anon;
grant select, insert, update, delete on public.institutions, public.institution_email_domains, public.email_exceptions to authenticated;

drop policy if exists "read institutions" on public.institutions;
create policy "read institutions" on public.institutions for select to authenticated using (true);
drop policy if exists "super admin institutions" on public.institutions;
create policy "super admin institutions" on public.institutions for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

drop policy if exists "read email types" on public.institution_email_domains;
create policy "read email types" on public.institution_email_domains for select to authenticated using (true);
drop policy if exists "super admin email types" on public.institution_email_domains;
create policy "super admin email types" on public.institution_email_domains for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

drop policy if exists "super admin exceptions" on public.email_exceptions;
create policy "super admin exceptions" on public.email_exceptions for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

-- Starter data: Cavendish University Uganda (its mail runs on Google).
insert into public.institutions (name, short_name, calendar_provider)
values ('Cavendish University Uganda', 'CUU', 'google')
on conflict (name) do nothing;

insert into public.institution_email_domains (institution_id, domain, include_subdomains, account_kind, example)
select i.id, d.domain, d.subs, d.kind, d.example
from public.institutions i,
     (values ('students.cavendish.ac.ug', false, 'student', 'od251945@students.cavendish.ac.ug'),
             ('cavendish.ac.ug', true, 'staff', 'name@cavendish.ac.ug')) as d(domain, subs, kind, example)
where i.name = 'Cavendish University Uganda'
on conflict (domain) do nothing;

-- The kill switch: super admin can turn the school-email rule off in an emergency.
insert into public.app_settings (key, value) values ('school_email_only', 'on')
on conflict (key) do nothing;

-- Which institution an email belongs to. The most specific domain wins, so
-- students.cavendish.ac.ug beats cavendish.ac.ug.
create or replace function public.match_school_email(p_email text)
returns table (institution_id uuid, institution_name text, account_kind text, domain text, calendar_provider text)
language plpgsql stable security definer set search_path = public as $$
declare
  em text := lower(trim(coalesce(p_email, '')));
  lp text;
  dom text;
  d record;
begin
  if em !~ '^[a-z0-9._%+-]{1,64}@[a-z0-9.-]{3,190}$' then return; end if;
  lp := split_part(em, '@', 1);
  dom := split_part(em, '@', 2);
  select x.*, i.name as iname, i.calendar_provider as cal into d
  from public.institution_email_domains x
  join public.institutions i on i.id = x.institution_id
  where x.is_active and i.is_active
    and (dom = x.domain or (x.include_subdomains and right(dom, char_length(x.domain) + 1) = '.' || x.domain))
  order by char_length(x.domain) desc
  limit 1;
  if d.id is null then return; end if;
  if d.local_part_pattern is not null and lp !~ d.local_part_pattern then return; end if;
  return query select d.institution_id, d.iname, d.account_kind, d.domain, d.cal;
end $$;

create or replace function public.email_allowed(p_email text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select value from public.app_settings where key = 'school_email_only'), 'on') = 'off'
      or exists (select 1 from public.match_school_email(p_email))
      or exists (select 1 from public.email_exceptions e
                 where e.email = lower(trim(p_email)) and (e.expires_at is null or e.expires_at > now()));
$$;

-- For the sign-up page: "is this email accepted?" before trying.
create or replace function public.check_signup_email(p_email text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m record; ex text;
begin
  select * into m from public.match_school_email(p_email) limit 1;
  if m.institution_id is not null then
    return jsonb_build_object('allowed', true, 'institution', m.institution_name, 'kind', m.account_kind);
  end if;
  if public.email_allowed(p_email) then
    return jsonb_build_object('allowed', true);
  end if;
  select example into ex from public.institution_email_domains where is_active and example is not null
   order by (account_kind = 'student') desc, created_at limit 1;
  return jsonb_build_object('allowed', false,
    'message', 'Use your school email address' || coalesce(', like ' || ex, '') || '.');
end $$;

-- For the sign-up page: list the accepted email types.
create or replace function public.allowed_email_types()
returns table (institution text, domain text, include_subdomains boolean, account_kind text, example text)
language sql stable security definer set search_path = public as $$
  select i.name, d.domain, d.include_subdomains, d.account_kind, d.example
  from public.institution_email_domains d join public.institutions i on i.id = d.institution_id
  where d.is_active and i.is_active
  order by i.name, (d.account_kind = 'student') desc, d.domain;
$$;

revoke execute on function public.match_school_email(text) from public, anon, authenticated;
revoke execute on function public.email_allowed(text) from public, anon, authenticated;
revoke execute on function public.check_signup_email(text) from public;
revoke execute on function public.allowed_email_types() from public;
grant execute on function public.check_signup_email(text) to anon, authenticated;
grant execute on function public.allowed_email_types() to anon, authenticated;

-- The rule itself, inside the database: no app (or modified app) can skip it.
-- Runs for email sign-up, Google sign-in and email changes.
create or replace function public.enforce_school_email() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.email is not distinct from old.email then return new; end if;
  if coalesce(new.is_anonymous, false) then return new; end if;
  if new.email is null or not public.email_allowed(new.email) then
    raise exception 'CAMPUSLINK_SCHOOL_EMAIL_ONLY: Use your school email address to join CampusLink.'
      using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke execute on function public.enforce_school_email() from public, anon, authenticated;
drop trigger if exists enforce_school_email on auth.users;
create trigger enforce_school_email before insert or update of email on auth.users
  for each row execute function public.enforce_school_email();

-- Same rule as an Auth hook, which shows students a clear message instead of
-- "Database error saving new user". Turn it on in Dashboard > Authentication >
-- Hooks > "Before User Created" > Postgres > public.hook_before_user_created.
create or replace function public.hook_before_user_created(event jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare em text := event -> 'user' ->> 'email';
begin
  if coalesce((event -> 'user' ->> 'is_anonymous')::boolean, false) then return '{}'::jsonb; end if;
  if em is null or not public.email_allowed(em) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403,
      'message', (public.check_signup_email(coalesce(em, ''))) ->> 'message'));
  end if;
  return '{}'::jsonb;
end $$;
revoke execute on function public.hook_before_user_created(jsonb) from public, anon, authenticated;
grant execute on function public.hook_before_user_created(jsonb) to supabase_auth_admin;
grant usage on schema public to supabase_auth_admin;

-- Remember each person's institution (set by the database, never by the app).
alter table public.profiles add column if not exists institution_id uuid references public.institutions(id) on delete set null;
create index if not exists fk_profiles_institution on public.profiles (institution_id);

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, institution_id)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''),
          (select m.institution_id from public.match_school_email(new.email) m limit 1))
  on conflict (id) do nothing;
  return new;
end $$;

update public.profiles p set institution_id = m.institution_id
from auth.users u, lateral public.match_school_email(u.email) m
where u.id = p.id and p.institution_id is null;

create or replace function public.protect_profile_columns() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.role is distinct from old.role
       or new.tutor_verified is distinct from old.tutor_verified
       or new.tutor_verified_at is distinct from old.tutor_verified_at
       or new.created_at is distinct from old.created_at
       or new.institution_id is distinct from old.institution_id
       or (new.username_changed_at is distinct from old.username_changed_at
           and new.username is not distinct from old.username) then
      raise exception 'These fields can only be changed by the platform' using errcode = '42501';
    end if;
    if new.avatar_path is distinct from old.avatar_path and new.avatar_path is not null
       and not (new.avatar_path like 'https://%.supabase.co/storage/v1/object/public/avatars/' || new.id::text || '/%') then
      raise exception 'Profile photos must be uploaded through CampusLink' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

-- =========================================================================
-- 2. Tutors: price, how they teach, and private contact details
-- =========================================================================
alter table public.tutor_profiles
  add column if not exists rate_ugx integer check (rate_ugx is null or rate_ugx between 0 and 500000),
  add column if not exists rate_unit text not null default 'hour' check (rate_unit in ('hour', 'session', 'week', 'month')),
  add column if not exists price_negotiable boolean not null default false,
  add column if not exists first_session_free boolean not null default false,
  add column if not exists teaching_mode text not null default 'both' check (teaching_mode in ('in_person', 'online', 'both'));

-- Phone and email live in their own table that nobody else can read directly.
-- Students get them through tutor_contact(), which checks they may see them.
create table if not exists public.tutor_contacts (
  tutor_id uuid primary key references public.profiles(id) on delete cascade,
  phone text check (phone is null or phone ~ '^\+[1-9][0-9]{7,14}$'),
  phone_whatsapp boolean not null default false,
  phone_calls boolean not null default true,
  email text check (email is null or (char_length(email) <= 120
                    and email ~* '^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$')),
  -- 'accepted': only students whose request you accepted. 'signed_in': any signed-in student.
  visibility text not null default 'accepted' check (visibility in ('accepted', 'signed_in')),
  updated_at timestamptz not null default now()
);
alter table public.tutor_contacts enable row level security;
revoke all on public.tutor_contacts from anon;
grant select, insert, update, delete on public.tutor_contacts to authenticated;
drop policy if exists "own contact" on public.tutor_contacts;
create policy "own contact" on public.tutor_contacts for all to authenticated
  using (tutor_id = (select auth.uid())) with check (tutor_id = (select auth.uid()));

create or replace function public.tutor_contacts_tidy() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  new.email := nullif(lower(trim(new.email)), '');
  new.phone := nullif(trim(new.phone), '');
  if new.phone is null then new.phone_whatsapp := false; new.phone_calls := false; end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists tutor_contacts_tidy on public.tutor_contacts;
create trigger tutor_contacts_tidy before insert or update on public.tutor_contacts
  for each row execute function public.tutor_contacts_tidy();

-- Who looked at whose contact, per day. Used to stop number harvesting.
create table if not exists public.tutor_contact_views (
  tutor_id uuid not null references public.profiles(id) on delete cascade,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  day date not null default current_date,
  primary key (tutor_id, viewer_id, day)
);
create index if not exists tutor_contact_views_viewer on public.tutor_contact_views (viewer_id, day);
alter table public.tutor_contact_views enable row level security;
revoke all on public.tutor_contact_views from anon, authenticated;

-- What a list card may show: icons only ("has WhatsApp"), never the number.
create or replace function public.tutor_contact_summary(p_tutors uuid[])
returns table (tutor_id uuid, has_phone boolean, has_whatsapp boolean, has_email boolean, visibility text)
language sql stable security definer set search_path = public as $$
  select c.tutor_id, c.phone is not null, c.phone is not null and c.phone_whatsapp, c.email is not null, c.visibility
  from public.tutor_contacts c
  where c.tutor_id = any (p_tutors) and (select auth.uid()) is not null;
$$;

create or replace function public.tutor_contact(p_tutor uuid)
returns table (phone text, phone_whatsapp boolean, phone_calls boolean, email text, visible boolean, reason text)
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  c public.tutor_contacts;
  ok boolean := false;
  seen int;
begin
  if me is null then raise exception 'Please sign in first.' using errcode = '42501'; end if;
  select * into c from public.tutor_contacts t where t.tutor_id = p_tutor;
  if c.tutor_id is null or (c.phone is null and c.email is null) then
    return query select null::text, false, false, null::text, false, 'none'; return;
  end if;
  if me = p_tutor then
    return query select c.phone, c.phone_whatsapp, c.phone_calls, c.email, true, 'ok'; return;
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_tutor and p.is_tutor) then
    return query select null::text, false, false, null::text, false, 'not_tutor'; return;
  end if;
  -- Three open reports from different students pause a tutor (same rule as tutor_stats).
  if (select count(distinct r.reporter_id) from public.tutor_reports r
       where r.tutor_id = p_tutor and r.status = 'open') >= 3 then
    return query select null::text, false, false, null::text, false, 'paused'; return;
  end if;
  ok := exists (select 1 from public.tutor_requests r
                where r.tutor_id = p_tutor and r.student_id = me and r.status in ('accepted', 'completed'));
  if not ok and c.visibility = 'signed_in' then
    select count(*) into seen from public.tutor_contact_views v
     where v.viewer_id = me and v.day = current_date and v.tutor_id <> p_tutor;
    if seen >= 15 and not exists (select 1 from public.tutor_contact_views v
                                  where v.viewer_id = me and v.tutor_id = p_tutor and v.day = current_date) then
      return query select null::text, false, false, null::text, false, 'limit'; return;
    end if;
    ok := true;
  end if;
  if not ok then
    return query select null::text, false, false, null::text, false, 'request_first'; return;
  end if;
  insert into public.tutor_contact_views (tutor_id, viewer_id) values (p_tutor, me) on conflict do nothing;
  return query select c.phone, c.phone_whatsapp, c.phone_calls, c.email, true, 'ok';
end $$;

revoke execute on function public.tutor_contact_summary(uuid[]) from public, anon;
revoke execute on function public.tutor_contact(uuid) from public, anon;
grant execute on function public.tutor_contact_summary(uuid[]) to authenticated;
grant execute on function public.tutor_contact(uuid) to authenticated;

-- Tell the student they can now reach the tutor.
create or replace function public.notify_tutor_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.notifications (user_id, kind, title, body, link)
    values (new.tutor_id, 'tutor', 'New tutoring request for ' || new.course_code,
            left(new.message, 200), '/tutors/mine');
  elsif new.status is distinct from old.status and new.status in ('accepted', 'declined') then
    insert into public.notifications (user_id, kind, title, body, link)
    values (new.student_id, 'tutor', 'Your tutor ' || new.status || ' your request',
            new.course_code || case when new.status = 'accepted'
              then ' · You can now see their phone and email.' else '' end,
            '/tutors/mine');
  end if;
  return null;
end $$;

-- =========================================================================
-- 3. "Do I have a password?" (Google users can create one)
-- =========================================================================
create or replace function public.my_sign_in_methods() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'has_password', coalesce(u.encrypted_password, '') <> '',
    'providers', coalesce((select jsonb_agg(distinct i.provider) from auth.identities i where i.user_id = u.id), '[]'::jsonb),
    'email', u.email)
  from auth.users u where u.id = (select auth.uid());
$$;
revoke execute on function public.my_sign_in_methods() from public, anon;
grant execute on function public.my_sign_in_methods() to authenticated;

-- =========================================================================
-- 4. Private calendar feed (Google / Outlook / Apple Calendar subscribe to it)
-- =========================================================================
create table if not exists public.calendar_feeds (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  token_hash text not null unique,          -- only a fingerprint; the link itself is never stored
  include_events boolean not null default true,
  include_classes boolean not null default true,
  include_exams boolean not null default true,
  created_at timestamptz not null default now(),
  last_fetched_at timestamptz
);
alter table public.calendar_feeds enable row level security;
revoke all on public.calendar_feeds from anon;
grant select on public.calendar_feeds to authenticated;
drop policy if exists "own feed" on public.calendar_feeds;
create policy "own feed" on public.calendar_feeds for select to authenticated
  using (user_id = (select auth.uid()));

-- Makes (or replaces) your feed link. The old link stops working at once.
create or replace function public.create_calendar_feed() returns text
language plpgsql security definer set search_path = public as $$
declare t text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  if auth.uid() is null then raise exception 'Please sign in first.' using errcode = '42501'; end if;
  insert into public.calendar_feeds (user_id, token_hash)
  values (auth.uid(), encode(sha256(convert_to(t, 'UTF8')), 'hex'))
  on conflict (user_id) do update set token_hash = excluded.token_hash, created_at = now(), last_fetched_at = null;
  return t;
end $$;

create or replace function public.set_calendar_feed(p_events boolean, p_classes boolean, p_exams boolean) returns void
language sql security definer set search_path = public as $$
  update public.calendar_feeds
     set include_events = p_events, include_classes = p_classes, include_exams = p_exams
   where user_id = (select auth.uid());
$$;

create or replace function public.delete_calendar_feed() returns void
language sql security definer set search_path = public as $$
  delete from public.calendar_feeds where user_id = (select auth.uid());
$$;

-- What the calendar-feed edge function prints. The long random link is the
-- only key, so this is callable without signing in (calendar apps can't sign in).
create or replace function public.calendar_feed_data(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.calendar_feeds; ends date;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return null; end if;
  select * into f from public.calendar_feeds where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
  if f.user_id is null then return null; end if;
  if f.last_fetched_at is null or f.last_fetched_at < now() - interval '10 minutes' then
    update public.calendar_feeds set last_fetched_at = now() where user_id = f.user_id;
  end if;
  select nullif(value, '')::date into ends from public.app_settings where key = 'semester_ends_on';
  return jsonb_build_object(
    'semester_ends_on', ends,
    'events', case when f.include_events then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'title', e.title, 'description', e.description, 'location', e.location,
        'online_url', e.online_url, 'organiser', coalesce(pb.name, e.organiser),
        'starts_at', e.starts_at, 'ends_at', e.ends_at,
        'cancelled', e.cancelled_at is not null or e.status = 'removed',
        'cancel_reason', e.cancel_reason,
        'going', exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = f.user_id),
        'updated_at', greatest(e.created_at, coalesce(e.edited_at, e.created_at), coalesce(e.cancelled_at, e.created_at))))
      from public.events e left join public.publishers pb on pb.id = e.publisher_id
      where e.status in ('published', 'removed')
        and e.starts_at > now() - interval '60 days'
        and (exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = f.user_id)
             or (e.major_status = 'approved' and e.status = 'published'))), '[]'::jsonb) else '[]'::jsonb end,
    'classes', case when f.include_classes then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'code', t.course_code, 'name', t.course_name, 'day', t.day_of_week,
        'start', t.start_time, 'end', t.end_time, 'room', t.room, 'lecturer', t.lecturer,
        'from', t.created_at::date))
      from public.timetable_entries t where t.user_id = f.user_id), '[]'::jsonb) else '[]'::jsonb end,
    'exams', case when f.include_exams then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id, 'code', x.course_code, 'name', x.course_name, 'date', x.exam_date,
        'start', x.start_time, 'end', x.end_time, 'room', x.room, 'campus', x.campus))
      from public.my_exams x where x.user_id = f.user_id and x.exam_date >= current_date - 30), '[]'::jsonb) else '[]'::jsonb end);
end $$;

revoke execute on function public.create_calendar_feed() from public, anon;
revoke execute on function public.set_calendar_feed(boolean, boolean, boolean) from public, anon;
revoke execute on function public.delete_calendar_feed() from public, anon;
revoke execute on function public.calendar_feed_data(text) from public, authenticated;
grant execute on function public.create_calendar_feed() to authenticated;
grant execute on function public.set_calendar_feed(boolean, boolean, boolean) to authenticated;
grant execute on function public.delete_calendar_feed() to authenticated;
grant execute on function public.calendar_feed_data(text) to anon;
