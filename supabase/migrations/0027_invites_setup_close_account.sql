-- 0027: invite links (guests), first sign-in setup, privacy settings and
-- closing an account with a 30-day grace period. Safe to run more than once.

-- =========================================================================
-- 1. New profile fields
-- =========================================================================
alter table public.profiles
  add column if not exists display_name text,
  add column if not exists onboarded_at timestamptz,
  add column if not exists interests text[] not null default '{}',
  add column if not exists show_studies boolean not null default true,
  add column if not exists account_type text not null default 'student',
  add column if not exists access_level text not null default 'member',
  add column if not exists access_until timestamptz,
  add column if not exists invite_id uuid,
  add column if not exists closing_at timestamptz,
  add column if not exists closed_at timestamptz;

alter table public.profiles drop constraint if exists profiles_display_name_len;
alter table public.profiles add constraint profiles_display_name_len
  check (display_name is null or char_length(display_name) between 2 and 40);
alter table public.profiles drop constraint if exists profiles_account_type_check;
alter table public.profiles add constraint profiles_account_type_check check (account_type in ('student', 'guest'));
alter table public.profiles drop constraint if exists profiles_access_level_check;
alter table public.profiles add constraint profiles_access_level_check check (access_level in ('visitor', 'member'));
alter table public.profiles drop constraint if exists profiles_interests_check;
alter table public.profiles add constraint profiles_interests_check check (
  cardinality(interests) <= 12 and interests <@ array['academics', 'sports', 'guild', 'clubs', 'careers', 'events',
    'tech', 'arts', 'faith', 'health', 'business', 'volunteering']::text[]);

-- Others may read these (0023 grants columns one by one).
grant select (display_name, onboarded_at, interests, show_studies, account_type, access_level, access_until,
              closing_at, closed_at) on public.profiles to authenticated;

-- People can't give themselves guest/visitor changes, end dates or closure dates.
create or replace function public.protect_profile_columns() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.role is distinct from old.role
       or new.tutor_verified is distinct from old.tutor_verified
       or new.tutor_verified_at is distinct from old.tutor_verified_at
       or new.created_at is distinct from old.created_at
       or new.institution_id is distinct from old.institution_id
       or new.account_type is distinct from old.account_type
       or new.access_level is distinct from old.access_level
       or new.access_until is distinct from old.access_until
       or new.invite_id is distinct from old.invite_id
       or new.closing_at is distinct from old.closing_at
       or new.closed_at is distinct from old.closed_at
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

-- Nicknames: tidy, and nothing that pretends to be an official.
create or replace function public.profiles_display_name_guard() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  new.display_name := nullif(regexp_replace(trim(coalesce(new.display_name, '')), '\s+', ' ', 'g'), '');
  if new.display_name is not null and current_user in ('authenticated', 'anon')
     and (tg_op = 'INSERT' or new.display_name is distinct from old.display_name) then
    if new.display_name ~* '(admin|official|moderator|campuslink|registrar|dean|vice.?chancellor|guild.?president|university|cavendish|support team)' then
      raise exception 'That name looks like an official title. Please choose another.';
    end if;
    if new.display_name !~ '[[:alpha:]]' then
      raise exception 'Use at least one letter in your name.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists profiles_display_name_guard on public.profiles;
create trigger profiles_display_name_guard before insert or update of display_name on public.profiles
  for each row execute function public.profiles_display_name_guard();

-- =========================================================================
-- 2. Personal settings
-- =========================================================================
create table if not exists public.user_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  notify_kinds text[] not null default '{course,official,event,tutor,request,office,access,group}',
  quiet_enabled boolean not null default true,
  quiet_start time not null default '22:00',
  quiet_end time not null default '06:00',
  updated_at timestamptz not null default now()
);
alter table public.user_settings enable row level security;
revoke all on public.user_settings from anon;
grant select, insert, update, delete on public.user_settings to authenticated;
drop policy if exists "own settings" on public.user_settings;
create policy "own settings" on public.user_settings for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- =========================================================================
-- 3. Invite links
-- =========================================================================
create table if not exists public.invites (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  kind text not null check (kind in ('personal', 'group')),
  email text check (email is null or (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  access_level text not null default 'visitor' check (access_level in ('visitor', 'member')),
  max_uses int not null check (max_uses between 1 and 50),
  uses int not null default 0,
  link_expires_at timestamptz not null,
  access_until timestamptz,
  note text check (note is null or char_length(note) <= 200),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  check (kind = 'group' or (email is not null and max_uses = 1))
);
create index if not exists fk_invites_created_by on public.invites (created_by);

create table if not exists public.invite_claims (
  id uuid primary key default gen_random_uuid(),
  invite_id uuid not null references public.invites(id) on delete cascade,
  email text not null,
  reserved_until timestamptz not null,
  user_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (invite_id, email)
);
create index if not exists invite_claims_email on public.invite_claims (email);
create index if not exists fk_invite_claims_user on public.invite_claims (user_id);

alter table public.invites enable row level security;
alter table public.invite_claims enable row level security;
revoke all on public.invites, public.invite_claims from anon;
grant select on public.invites, public.invite_claims to authenticated;
drop policy if exists "super admin invites" on public.invites;
create policy "super admin invites" on public.invites for select to authenticated using (public.is_super_admin());
drop policy if exists "super admin claims" on public.invite_claims;
create policy "super admin claims" on public.invite_claims for select to authenticated using (public.is_super_admin());

alter table public.profiles drop constraint if exists profiles_invite_fk;
alter table public.profiles add constraint profiles_invite_fk foreign key (invite_id) references public.invites(id) on delete set null;
create index if not exists fk_profiles_invite on public.profiles (invite_id);

create or replace function public.invite_by_token(p_token text) returns public.invites
language sql stable security definer set search_path = public as $$
  select * from public.invites
  where p_token ~ '^[0-9a-f]{64}$' and token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
$$;
revoke execute on function public.invite_by_token(text) from public, anon, authenticated;

-- Super admin makes an invite. Returns the secret part of the link once.
create or replace function public.create_invite(
  p_kind text, p_email text, p_level text, p_max_uses int, p_link_days int, p_access_until timestamptz, p_note text)
returns text language plpgsql security definer set search_path = public as $$
declare t text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  if not public.is_super_admin() then raise exception 'Only the super admin can make invites.'; end if;
  if p_kind not in ('personal', 'group') then raise exception 'Choose a personal or group invite.'; end if;
  if p_kind = 'personal' and coalesce(trim(p_email), '') = '' then raise exception 'A personal invite needs their email.'; end if;
  if p_kind = 'group' and (p_link_days not between 1 and 7) then raise exception 'Group links can work for at most 7 days.'; end if;
  if p_kind = 'personal' and (p_link_days not between 1 and 30) then raise exception 'Personal links can work for at most 30 days.'; end if;
  if p_kind = 'group' and (p_max_uses not between 2 and 50) then raise exception 'A group link is for 2 to 50 people.'; end if;
  if p_access_until is not null and p_access_until <= now() then raise exception 'Access must end in the future.'; end if;
  insert into public.invites (token_hash, kind, email, access_level, max_uses, link_expires_at, access_until, note, created_by)
  values (encode(sha256(convert_to(t, 'UTF8')), 'hex'), p_kind,
          case when p_kind = 'personal' then lower(trim(p_email)) end,
          coalesce(p_level, 'visitor'), case when p_kind = 'personal' then 1 else p_max_uses end,
          now() + make_interval(days => p_link_days), p_access_until, nullif(trim(p_note), ''), auth.uid());
  return t;
end $$;

create or replace function public.revoke_invite(p_invite uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_super_admin() then raise exception 'Only the super admin can cancel invites.'; end if;
  update public.invites set revoked_at = now() where id = p_invite and revoked_at is null;
  delete from public.invite_claims where invite_id = p_invite and user_id is null;
end $$;

-- What the invite page shows before anyone signs up.
create or replace function public.invite_info(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare i public.invites; taken int;
begin
  i := public.invite_by_token(p_token);
  if i.id is null then return jsonb_build_object('valid', false, 'reason', 'This invite link is not valid.'); end if;
  if i.revoked_at is not null then return jsonb_build_object('valid', false, 'reason', 'This invite was cancelled.'); end if;
  if i.link_expires_at <= now() then return jsonb_build_object('valid', false, 'reason', 'This invite link has expired.'); end if;
  select count(*) into taken from public.invite_claims c
   where c.invite_id = i.id and (c.user_id is not null or c.reserved_until > now());
  if taken >= i.max_uses then return jsonb_build_object('valid', false, 'reason', 'This invite has been used up.'); end if;
  return jsonb_build_object('valid', true, 'kind', i.kind, 'level', i.access_level,
    'access_until', i.access_until, 'link_expires_at', i.link_expires_at,
    -- personal invites: show only a hint of whose it is, e.g. j***@gmail.com
    'email_hint', case when i.email is not null
      then left(i.email, 1) || '***@' || split_part(i.email, '@', 2) end);
end $$;

-- Step 1 of joining by invite: reserve a place for this email for 2 hours,
-- so the sign-up that follows is allowed (see email_allowed).
create or replace function public.claim_invite(p_token text, p_email text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i public.invites; em text := lower(trim(coalesce(p_email, ''))); taken int; recent int;
begin
  if em !~ '^[a-z0-9._%+-]{1,64}@[a-z0-9-]+(\.[a-z0-9-]+)+$' then
    return jsonb_build_object('ok', false, 'reason', 'Check the email address.');
  end if;
  i := public.invite_by_token(p_token);
  if i.id is null or i.revoked_at is not null or i.link_expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'This invite link is no longer valid.');
  end if;
  if exists (select 1 from public.match_school_email(em)) then
    return jsonb_build_object('ok', true, 'school', true); -- school emails never need an invite
  end if;
  if i.email is not null and i.email <> em then
    return jsonb_build_object('ok', false, 'reason', 'This invite is for a different email address.');
  end if;
  if exists (select 1 from auth.users u where lower(u.email) = em) then
    return jsonb_build_object('ok', false, 'reason', 'That email already has an account. Sign in instead.');
  end if;
  -- Slow down anyone trying to burn a group link with fake emails.
  select count(*) into recent from public.invite_claims c
   where c.invite_id = i.id and c.created_at > now() - interval '1 hour';
  if recent >= i.max_uses * 3 then
    return jsonb_build_object('ok', false, 'reason', 'Too many tries on this link. Wait an hour and try again.');
  end if;
  select count(*) into taken from public.invite_claims c
   where c.invite_id = i.id and c.email <> em and (c.user_id is not null or c.reserved_until > now());
  if taken >= i.max_uses then
    return jsonb_build_object('ok', false, 'reason', 'This invite has been used up.');
  end if;
  insert into public.invite_claims (invite_id, email, reserved_until)
  values (i.id, em, now() + interval '2 hours')
  on conflict (invite_id, email) do update set reserved_until = excluded.reserved_until
    where public.invite_claims.user_id is null;
  return jsonb_build_object('ok', true, 'school', false);
end $$;

revoke execute on function public.create_invite(text, text, text, int, int, timestamptz, text) from public, anon;
revoke execute on function public.revoke_invite(uuid) from public, anon;
revoke execute on function public.invite_info(text) from public;
revoke execute on function public.claim_invite(text, text) from public;
grant execute on function public.create_invite(text, text, text, int, int, timestamptz, text) to authenticated;
grant execute on function public.revoke_invite(uuid) to authenticated;
grant execute on function public.invite_info(text) to anon, authenticated;
grant execute on function public.claim_invite(text, text) to anon, authenticated;

-- An email with a live invite reservation may sign up, like a school email.
create or replace function public.email_allowed(p_email text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select value from public.app_settings where key = 'school_email_only'), 'on') = 'off'
      or exists (select 1 from public.match_school_email(p_email))
      or exists (select 1 from public.email_exceptions e
                 where e.email = lower(trim(p_email)) and (e.expires_at is null or e.expires_at > now()))
      or exists (select 1 from public.invite_claims c join public.invites i on i.id = c.invite_id
                 where c.email = lower(trim(p_email)) and c.user_id is null and c.reserved_until > now()
                   and i.revoked_at is null and i.link_expires_at > now());
$$;
revoke execute on function public.email_allowed(text) from public, anon, authenticated;

-- Closed accounts get a placeholder email (see finish_account_closures).
create or replace function public.enforce_school_email() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.email is not distinct from old.email then return new; end if;
  if coalesce(new.is_anonymous, false) then return new; end if;
  if tg_op = 'UPDATE' and new.email like '%@closed.campuslink.invalid' then return new; end if;
  if new.email is null or not public.email_allowed(new.email) then
    raise exception 'CAMPUSLINK_SCHOOL_EMAIL_ONLY: Use your school email address to join CampusLink.'
      using errcode = 'P0001';
  end if;
  return new;
end $$;

-- New account: school email = student; otherwise use the invite reservation.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  md jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  yr int;
  sn text := nullif(left(trim(md ->> 'student_number'), 20), '');
  prog text := nullif(left(trim(md ->> 'programme'), 80), '');
  inst uuid;
  c record;
begin
  begin
    yr := (md ->> 'year_of_study')::int;
    if yr not between 1 and 7 then yr := null; end if;
  exception when others then yr := null;
  end;
  if sn is not null and sn !~ '^[A-Za-z0-9/-]{3,20}$' then sn := null; end if;
  select m.institution_id into inst from public.match_school_email(new.email) m limit 1;
  insert into public.profiles (id, full_name, institution_id, student_number, programme, year_of_study)
  values (new.id, left(coalesce(md ->> 'full_name', md ->> 'name', ''), 120), inst, sn, prog, yr)
  on conflict (id) do nothing;

  if inst is null then
    select cl.id as claim_id, i.id as invite_id, i.access_level, i.access_until into c
    from public.invite_claims cl join public.invites i on i.id = cl.invite_id
    where cl.email = lower(new.email) and cl.user_id is null and cl.reserved_until > now()
      and i.revoked_at is null and i.link_expires_at > now()
    order by cl.created_at desc limit 1;
    if c.claim_id is not null then
      update public.invite_claims set user_id = new.id where id = c.claim_id;
      update public.invites set uses = uses + 1 where id = c.invite_id;
      update public.profiles
         set account_type = 'guest', access_level = c.access_level, access_until = c.access_until,
             invite_id = c.invite_id, student_number = null
       where id = new.id;
      -- When access ends, Supabase itself refuses to sign them in.
      if c.access_until is not null then
        update auth.users set banned_until = c.access_until where id = new.id;
      end if;
    end if;
  end if;
  return new;
end $$;

-- Super admin: change when a guest's access ends, or end it now.
create or replace function public.set_guest_access(p_user uuid, p_until timestamptz, p_end_now boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare who text;
begin
  if not public.is_super_admin() then raise exception 'Only the super admin can change guest access.'; end if;
  select account_type into who from public.profiles where id = p_user;
  if who is distinct from 'guest' then raise exception 'That person is not a guest.'; end if;
  if p_end_now then
    update public.profiles set access_until = now() where id = p_user;
    update auth.users set banned_until = now() where id = p_user;
    delete from auth.sessions where user_id = p_user;
  else
    if p_until is not null and p_until <= now() then raise exception 'Pick a date in the future.'; end if;
    update public.profiles set access_until = p_until where id = p_user;
    update auth.users set banned_until = p_until where id = p_user;
  end if;
end $$;

create or replace function public.set_guest_level(p_user uuid, p_level text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_super_admin() then raise exception 'Only the super admin can change guest access.'; end if;
  if p_level not in ('visitor', 'member') then raise exception 'Choose visitor or member.'; end if;
  update public.profiles set access_level = p_level where id = p_user and account_type = 'guest';
end $$;

-- Guests the super admin can see and manage.
create or replace function public.list_guests()
returns table (id uuid, name text, email text, access_level text, access_until timestamptz, joined_at timestamptz, invite_note text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_super_admin() then raise exception 'Only the super admin can see guests.'; end if;
  return query
    select p.id, coalesce(p.display_name, p.full_name), u.email::text, p.access_level, p.access_until, p.created_at, i.note
    from public.profiles p join auth.users u on u.id = p.id left join public.invites i on i.id = p.invite_id
    where p.account_type = 'guest' and p.closed_at is null
    order by p.created_at desc;
end $$;

revoke execute on function public.set_guest_access(uuid, timestamptz, boolean) from public, anon;
revoke execute on function public.set_guest_level(uuid, text) from public, anon;
revoke execute on function public.list_guests() from public, anon;
grant execute on function public.set_guest_access(uuid, timestamptz, boolean) to authenticated;
grant execute on function public.set_guest_level(uuid, text) to authenticated;
grant execute on function public.list_guests() to authenticated;

-- =========================================================================
-- 4. Visitors read, but don't post, join, message or see other students
-- =========================================================================
create or replace function public.is_visitor() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = (select auth.uid()) and account_type = 'guest' and access_level = 'visitor');
$$;
revoke execute on function public.is_visitor() from public, anon;
grant execute on function public.is_visitor() to authenticated;

create or replace function public.block_visitors() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if public.is_visitor() then
    raise exception 'Visitors can read CampusLink but not post, join or message. Ask the CampusLink admin for member access.'
      using errcode = '42501';
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['help_requests', 'help_request_updates', 'comments', 'reactions', 'study_groups',
    'study_group_members', 'study_group_messages', 'study_group_requests', 'tutor_requests', 'tutor_reviews',
    'tutor_profiles', 'tutor_modules', 'tutor_contacts', 'lost_found_claims', 'buddy_pairs',
    'survey_participation', 'pulse_votes', 'post_answers', 'event_rsvps']
  loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists block_visitors on public.%I', t);
      execute format('create trigger block_visitors before insert on public.%I for each row execute function public.block_visitors()', t);
    end if;
  end loop;
end $$;

-- Visitors see only their own profile row (so no browsing students).
drop policy if exists "visitors see only themselves" on public.profiles;
create policy "visitors see only themselves" on public.profiles as restrictive for select to authenticated
  using (id = (select auth.uid()) or not (select public.is_visitor()));

-- =========================================================================
-- 5. Public profile view: nickname, hide studies if asked, guest badge,
--    hide accounts that are closing
-- =========================================================================
create or replace view public.public_profiles with (security_invoker = true) as
 select p.id,
    coalesce(p.display_name, p.full_name) as full_name,
    p.username,
    case when p.show_studies or p.id = (select auth.uid()) or public.is_staff() then p.programme end as programme,
    case when p.show_studies or p.id = (select auth.uid()) or public.is_staff() then p.year_of_study end as year_of_study,
    case when p.show_studies or p.id = (select auth.uid()) or public.is_staff() then p.faculty end as faculty,
    p.is_tutor,
    p.tutor_subjects,
    p.is_buddy_mentor,
    p.tutor_verified,
    p.avatar_path,
    case when p.status_until is null or p.status_until > now() then p.status_text else null::text end as status_text,
    case when p.status_until > now() then p.status_until else null::timestamptz end as status_until,
    coalesce(o.position_title, case when l.is_lecturer then 'Lecturer'::text else null::text end) as office_title,
    o.office_name,
    case
      when p.role = 'super_admin'::text or o.kind = 'administration'::text then 'red'::text
      when l.is_lecturer then 'orange'::text
      when o.kind = 'guild'::text then 'green'::text
      when o.kind = 'press'::text then 'purple'::text
      when p.account_type = 'guest' then 'guest'::text
      when p.tutor_verified then 'blue'::text
      else null::text
    end as badge
   from profiles p
     left join lateral ( select m.position_title, pb.kind, pb.name as office_name
           from publisher_members m
             join publishers pb on pb.id = m.publisher_id and pb.is_active
          where m.user_id = p.id and m.revoked_at is null and now() >= m.starts_at and now() <= m.expires_at
          order by (pb.kind = 'administration'::text) desc, (pb.kind = 'guild'::text) desc, (pb.kind = 'press'::text) desc
         limit 1) o on true
     left join lateral ( select (exists ( select 1 from course_lecturers cl where cl.lecturer_id = p.id)) as is_lecturer) l on true
  where p.closing_at is null or p.id = (select auth.uid());

-- =========================================================================
-- 6. Closing an account: 30 days to change your mind
-- =========================================================================
create or replace function public.request_account_closure(p_reason text default null) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r text; until timestamptz := now() + interval '30 days';
begin
  if me is null then raise exception 'Please sign in first.'; end if;
  select role into r from public.profiles where id = me;
  if r = 'super_admin' and (select count(*) from public.profiles where role = 'super_admin' and closed_at is null) <= 1 then
    raise exception 'You are the only super admin. Make someone else super admin before closing your account.';
  end if;
  update public.profiles set closing_at = until where id = me and closed_at is null;
  delete from public.calendar_feeds where user_id = me;
  -- The reason (optional) is not stored: it's private and not needed.
  return until;
end $$;

create or replace function public.cancel_account_closure() returns void
language sql security definer set search_path = public as $$
  update public.profiles set closing_at = null where id = (select auth.uid()) and closed_at is null;
$$;

-- Nightly: accounts past their 30 days lose their personal data for good.
-- Things other people rely on (request threads, chat replies, reviews) stay,
-- shown as "Former student".
create or replace function public.finish_account_closures() returns int
language plpgsql security definer set search_path = public, auth as $$
declare p record; n int := 0;
begin
  for p in select id from public.profiles where closing_at is not null and closing_at <= now() and closed_at is null loop
    delete from public.timetable_entries where user_id = p.id;
    delete from public.my_exams where user_id = p.id;
    delete from public.calendar_feeds where user_id = p.id;
    delete from public.notifications where user_id = p.id;
    delete from public.user_settings where user_id = p.id;
    delete from public.tutor_contacts where tutor_id = p.id;
    delete from public.tutor_contact_views where tutor_id = p.id or viewer_id = p.id;
    delete from public.tutor_modules where tutor_id = p.id;
    delete from public.tutor_profiles where tutor_id = p.id;
    delete from public.reactions where user_id = p.id;
    delete from public.activity_days where user_id = p.id;
    delete from public.study_group_members where user_id = p.id;
    delete from public.study_group_requests where user_id = p.id;
    delete from public.buddy_pairs where mentee_id = p.id or mentor_id = p.id;
    delete from public.event_rsvps where user_id = p.id;
    delete from public.help_office_staff where user_id = p.id;
    delete from public.course_lecturers where lecturer_id = p.id;
    update public.publisher_members set revoked_at = now(), end_kind = 'early', end_reason = 'Account closed'
     where user_id = p.id and revoked_at is null;
    update public.profiles set
      full_name = 'Former student', display_name = null, username = 'former-' || left(replace(p.id::text, '-', ''), 10),
      student_number = null, programme = null, year_of_study = null, faculty = null, avatar_path = null,
      status_text = null, status_until = null, is_tutor = false, tutor_subjects = '{}', is_buddy_mentor = false,
      tutor_verified = false, interests = '{}', institution_id = null, role = 'student',
      closing_at = null, closed_at = now()
    where id = p.id;
    -- Free the email so they can join again later with a fresh account.
    update auth.users set email = 'closed-' || p.id || '@closed.campuslink.invalid', phone = null,
      encrypted_password = '', raw_user_meta_data = '{}'::jsonb, banned_until = 'infinity'
     where id = p.id;
    delete from auth.identities where user_id = p.id;
    delete from auth.sessions where user_id = p.id;
    n := n + 1;
  end loop;
  return n;
end $$;

revoke execute on function public.request_account_closure(text) from public, anon;
revoke execute on function public.cancel_account_closure() from public, anon;
revoke execute on function public.finish_account_closures() from public, anon, authenticated;
grant execute on function public.request_account_closure(text) to authenticated;
grant execute on function public.cancel_account_closure() to authenticated;

select cron.unschedule('campuslink-close-accounts') where exists (select 1 from cron.job where jobname = 'campuslink-close-accounts');
select cron.schedule('campuslink-close-accounts', '0 21 * * *', 'select public.finish_account_closures()'); -- midnight Kampala

-- Closing tutors are hidden: no contact details while closing.
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
  if public.is_visitor() then
    return query select null::text, false, false, null::text, false, 'visitor'; return;
  end if;
  select * into c from public.tutor_contacts t where t.tutor_id = p_tutor;
  if c.tutor_id is null or (c.phone is null and c.email is null) then
    return query select null::text, false, false, null::text, false, 'none'; return;
  end if;
  if me = p_tutor then
    return query select c.phone, c.phone_whatsapp, c.phone_calls, c.email, true, 'ok'; return;
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_tutor and p.is_tutor and p.closing_at is null) then
    return query select null::text, false, false, null::text, false, 'not_tutor'; return;
  end if;
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
