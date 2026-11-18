-- =====================================================================
-- CampusLink 0002: community platform
--   roles + verified publishers (administration / guild) with expiring terms
--   news & official records, events with "major" approval, comments, likes
--   lost & found, surveys, tutor credibility, moderation log, policies
-- Run AFTER 0001_campuslink_schema.sql. Safe to re-run.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A. Grants for the 0001 tables.
-- New Supabase projects do NOT expose tables to the app until they are
-- granted. Nothing is granted to `anon`: you must be signed in.
-- Row Level Security (policies) still decides which rows.
-- ---------------------------------------------------------------------
grant usage on schema public to authenticated, service_role;

-- 0001 opened every table to every signed-in user and made that the default
-- for future tables. Reset to "nothing", then grant each table only what it
-- needs, so a forgotten policy can never become an open door.
alter default privileges in schema public revoke all on tables from authenticated;
revoke all on all tables in schema public from anon, authenticated;
grant select on public.pulse_results to authenticated;

grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.announcements to authenticated;
grant select, insert, update, delete on public.help_offices to authenticated;
grant select, insert, update on public.help_requests to authenticated;
grant select, insert on public.help_request_updates to authenticated;
grant select, insert, update on public.study_groups to authenticated;
grant select, insert, delete on public.study_group_members to authenticated;
grant select, insert, update, delete on public.pulse_polls to authenticated;
grant select, insert on public.pulse_votes to authenticated;
grant select, insert, update on public.buddy_pairs to authenticated;
grant select, insert on public.feedback to authenticated;
grant select, insert, update, delete on public.events to authenticated;
grant select on public.clubs to authenticated;
grant select, insert, update, delete on public.timetable_entries to authenticated;

grant all on all tables in schema public to service_role;

-- ---------------------------------------------------------------------
-- B. Roles. `role` on profiles = platform level:
--      student      everyone by default
--      staff/admin  university administration staff (kept for the old app)
--      super_admin  the platform owners (very few people)
--    Guild is NOT a role: it is a time-limited membership (see publishers).
-- ---------------------------------------------------------------------
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check check (role in ('student','staff','admin','super_admin'));

alter table public.profiles
  add column if not exists tutor_verified boolean not null default false,
  add column if not exists tutor_verified_at timestamptz;

create or replace function public.is_super_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'super_admin');
$$;

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role in ('staff','admin','super_admin'));
$$;

-- SECURITY FIX: in 0001 a student could update their own row, including
-- `role`. Now protected columns can only change through trusted functions.
-- (current_user is `authenticated` for app users; the SQL editor and the
-- definer functions below run as the owner, so they are allowed.)
create or replace function public.protect_profile_columns() returns trigger
language plpgsql as $$
begin
  if current_user in ('authenticated','anon') then
    if new.role is distinct from old.role
       or new.tutor_verified is distinct from old.tutor_verified
       or new.tutor_verified_at is distinct from old.tutor_verified_at then
      raise exception 'These fields can only be changed by the platform' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists protect_profile_columns on public.profiles;
create trigger protect_profile_columns before update on public.profiles
  for each row execute function public.protect_profile_columns();

drop policy if exists "own profile update" on public.profiles;
create policy "own profile update" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Only a super admin can change someone's role.
create or replace function public.set_user_role(p_user uuid, p_role text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_super_admin() then
    raise exception 'Only a super admin can change roles' using errcode = '42501';
  end if;
  if p_role not in ('student','staff','admin','super_admin') then
    raise exception 'Unknown role';
  end if;
  update public.profiles set role = p_role where id = p_user;
end $$;

-- ---------------------------------------------------------------------
-- C. Publishers: who may speak for an office, for how long, about what.
-- ---------------------------------------------------------------------
create table if not exists public.publishers (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('administration','guild','club')),
  name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- One place to change how long a guild term can last.
create or replace function public.max_term() returns interval
language sql immutable as $$ select interval '12 months' $$;

create table if not exists public.publisher_members (
  id uuid primary key default gen_random_uuid(),
  publisher_id uuid not null references public.publishers(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  position_title text not null check (char_length(position_title) between 3 and 80),
  -- what this person may publish. Allowed words:
  -- news, notices, events, meeting_links, surveys, lost_found, manage_members
  scopes text[] not null default '{news}',
  starts_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '12 months'),
  revoked_at timestamptz,
  appointed_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  check (expires_at > starts_at),
  check (scopes <@ array['news','notices','events','meeting_links','surveys','lost_found','manage_members']::text[])
);
create unique index if not exists publisher_members_one_active
  on public.publisher_members (publisher_id, user_id) where revoked_at is null;
create index if not exists publisher_members_user on public.publisher_members (user_id);

-- Can the signed-in user publish this kind of thing for this office, right now?
-- The term end date is checked every time, so rights vanish by themselves.
create or replace function public.can_publish(p_publisher uuid, p_scope text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_super_admin() or exists (
    select 1 from public.publisher_members m
    join public.publishers p on p.id = m.publisher_id and p.is_active
    where m.publisher_id = p_publisher and m.user_id = auth.uid()
      and m.revoked_at is null and now() between m.starts_at and m.expires_at
      and p_scope = any (m.scopes));
$$;

create or replace function public.is_active_publisher() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_super_admin() or exists (
    select 1 from public.publisher_members m
    join public.publishers p on p.id = m.publisher_id and p.is_active
    where m.user_id = auth.uid() and m.revoked_at is null
      and now() between m.starts_at and m.expires_at);
$$;

-- Public face of a person: safe columns only + badge.
-- red = administration, green = guild (while in office), blue = verified tutor.
create or replace view public.public_profiles as
select p.id, p.full_name, p.programme, p.year_of_study, p.faculty,
       p.is_tutor, p.tutor_subjects, p.is_buddy_mentor, p.tutor_verified,
       o.position_title as office_title, o.office_name,
       case when o.kind = 'administration' then 'red'
            when o.kind = 'guild' then 'green'
            when p.tutor_verified then 'blue' end as badge
from public.profiles p
left join lateral (
  select m.position_title, pb.kind, pb.name as office_name
  from public.publisher_members m
  join public.publishers pb on pb.id = m.publisher_id and pb.is_active
  where m.user_id = p.id and m.revoked_at is null
    and now() between m.starts_at and m.expires_at
  order by (pb.kind = 'administration') desc, (pb.kind = 'guild') desc
  limit 1) o on true;

-- ---------------------------------------------------------------------
-- D. Posts: news, notices, official records, meeting links, clarifications
-- ---------------------------------------------------------------------
create or replace function public.scope_for_kind(p_kind text) returns text
language sql immutable as $$
  select case p_kind
    when 'news' then 'news' when 'clarification' then 'news'
    when 'notice' then 'notices' when 'official_record' then 'notices'
    when 'meeting_link' then 'meeting_links' end;
$$;

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  publisher_id uuid not null references public.publishers(id),
  author_id uuid not null references public.profiles(id),
  author_position text not null default '',          -- frozen at posting time
  kind text not null default 'news'
    check (kind in ('news','notice','official_record','meeting_link','clarification')),
  title text not null check (char_length(title) between 5 and 140),
  body text not null check (char_length(body) between 20 and 10000),
  cover_path text,
  video_url text check (video_url is null or video_url ~* '^https://(www\.)?(youtube\.com/watch\?v=|youtu\.be/|youtube-nocookie\.com/embed/)'),
  meeting_url text check (meeting_url is null or meeting_url ~* '^https://'),
  source_note text not null check (char_length(source_note) >= 10),  -- where this information comes from
  corrects_post_id uuid references public.posts(id),                 -- a clarification answering a rumour
  status text not null default 'published' check (status in ('draft','published','removed')),
  pledge_accepted_at timestamptz not null default now(),
  expires_at timestamptz,                                            -- meeting links expire
  published_at timestamptz not null default now(),
  edited_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists posts_feed on public.posts (status, published_at desc);
create index if not exists posts_publisher on public.posts (publisher_id, published_at desc);

create table if not exists public.post_revisions (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  title text not null,
  body text not null,
  edited_by uuid references public.profiles(id),
  edited_at timestamptz not null default now()
);

-- Stamp the real author and position, cap how much one office can post.
create or replace function public.posts_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pos text; v_recent int;
begin
  new.author_id := auth.uid();
  select m.position_title into v_pos from public.publisher_members m
   where m.publisher_id = new.publisher_id and m.user_id = auth.uid()
     and m.revoked_at is null and now() between m.starts_at and m.expires_at
   limit 1;
  if v_pos is null then
    if public.is_super_admin() then v_pos := 'Platform team';
    else raise exception 'You are not an active member of this office' using errcode = '42501';
    end if;
  end if;
  new.author_position := v_pos;
  new.pledge_accepted_at := now();
  new.edited_at := null;
  if not public.is_super_admin() then
    select count(*) into v_recent from public.posts
     where publisher_id = new.publisher_id and created_at > now() - interval '24 hours';
    if v_recent >= 10 then
      raise exception 'This office has reached its daily posting limit. Please quality-check and try tomorrow.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists posts_before_insert on public.posts;
create trigger posts_before_insert before insert on public.posts
  for each row execute function public.posts_before_insert();

-- Keep every earlier version so nobody can quietly rewrite history.
create or replace function public.posts_keep_revision() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.title is distinct from old.title or new.body is distinct from old.body then
    insert into public.post_revisions (post_id, title, body, edited_by)
    values (old.id, old.title, old.body, auth.uid());
    new.edited_at := now();
  end if;
  return new;
end $$;
drop trigger if exists posts_keep_revision on public.posts;
create trigger posts_keep_revision before update on public.posts
  for each row execute function public.posts_keep_revision();

-- ---------------------------------------------------------------------
-- E. Events: extend the 0001 table, add speakers, "major" needs approval
-- ---------------------------------------------------------------------
alter table public.events
  add column if not exists publisher_id uuid references public.publishers(id),
  add column if not exists created_by uuid references public.profiles(id),
  add column if not exists topic text,
  add column if not exists impact text,                -- how students benefit
  add column if not exists cover_path text,
  add column if not exists online_url text check (online_url is null or online_url ~* '^https://'),
  add column if not exists status text not null default 'published'
    check (status in ('draft','published','removed')),
  add column if not exists major_status text not null default 'none'
    check (major_status in ('none','requested','approved','rejected')),
  add column if not exists major_reason text,          -- why the organiser says it is major
  add column if not exists major_reviewed_by uuid references public.profiles(id),
  add column if not exists major_reviewed_at timestamptz;
create index if not exists events_start on public.events (starts_at);
create index if not exists events_major on public.events (major_status, starts_at);

create table if not exists public.event_speakers (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 80),
  title text,                                          -- e.g. "Dean, Faculty of Science"
  role text not null default 'guest' check (role in ('guest','panelist','moderator','host')),
  photo_path text,
  bio text,
  position int not null default 0
);
create index if not exists event_speakers_event on public.event_speakers (event_id, position);

-- Only a super admin can approve/reject "major". Organisers may only ask,
-- and one office can have at most 3 requests waiting.
create or replace function public.events_guard_major() returns trigger
language plpgsql as $$
declare v_pending int;
begin
  if current_user in ('authenticated','anon') then
    if new.major_status in ('approved','rejected')
       and (tg_op = 'INSERT' or new.major_status is distinct from old.major_status)
       and not public.is_super_admin() then
      raise exception 'Only a platform super admin can approve a major event' using errcode = '42501';
    end if;
    if new.major_status = 'requested'
       and (tg_op = 'INSERT' or old.major_status is distinct from 'requested') then
      if coalesce(char_length(new.major_reason), 0) < 30 then
        raise exception 'Explain why this event is major (30+ characters)';
      end if;
      select count(*) into v_pending from public.events
       where publisher_id = new.publisher_id and major_status = 'requested' and id <> new.id;
      if v_pending >= 3 then
        raise exception 'This office already has 3 major requests waiting for review';
      end if;
    end if;
    if tg_op = 'UPDATE' and old.major_status = 'approved'
       and (new.starts_at is distinct from old.starts_at or new.title is distinct from old.title)
       and not public.is_super_admin() then
      new.major_status := 'requested';                  -- big edits need a fresh review
    end if;
  end if;
  return new;
end $$;
drop trigger if exists events_guard_major on public.events;
create trigger events_guard_major before insert or update on public.events
  for each row execute function public.events_guard_major();

-- What the home screen pops up: approved major events, from 24 hours before
-- the start until they end. At most 2 at a time so the feed is never buried.
create or replace view public.featured_events with (security_invoker = true) as
select * from public.events
where major_status = 'approved' and status = 'published'
  and now() >= starts_at - interval '24 hours'
  and now() < coalesce(ends_at, starts_at + interval '3 hours')
order by starts_at
limit 2;

-- ---------------------------------------------------------------------
-- F. Comments and likes (always as yourself, never as an office)
-- ---------------------------------------------------------------------
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in ('post','event')),
  target_id uuid not null,
  parent_id uuid references public.comments(id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  status text not null default 'visible' check (status in ('visible','removed')),
  created_at timestamptz not null default now()
);
create index if not exists comments_target on public.comments (target_type, target_id, created_at);

create table if not exists public.reactions (
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('post','event','comment')),
  target_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (user_id, target_type, target_id)
);
create index if not exists reactions_target on public.reactions (target_type, target_id);

create or replace function public.comments_rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.comments
       where author_id = new.author_id and created_at > now() - interval '1 hour') >= 30 then
    raise exception 'Slow down: too many comments this hour';
  end if;
  return new;
end $$;
drop trigger if exists comments_rate_limit on public.comments;
create trigger comments_rate_limit before insert on public.comments
  for each row execute function public.comments_rate_limit();

-- ---------------------------------------------------------------------
-- G. Moderation: reports + a public, append-only log of every removal
-- ---------------------------------------------------------------------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('post','comment','event')),
  target_id uuid not null,
  reason text not null check (char_length(reason) between 10 and 500),
  status text not null default 'open' check (status in ('open','actioned','dismissed')),
  handled_by uuid references public.profiles(id),
  handled_at timestamptz,
  created_at timestamptz not null default now(),
  unique (reporter_id, target_type, target_id)
);

create table if not exists public.moderation_actions (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles(id),
  target_type text not null check (target_type in ('post','comment','event')),
  target_id uuid not null,
  target_title text,                                   -- what was removed, in a few words
  action text not null check (action in ('remove','restore')),
  reason text not null check (char_length(reason) >= 20),
  created_at timestamptz not null default now()
);
create index if not exists moderation_actions_recent on public.moderation_actions (created_at desc);

-- Removing: comments by any staff; official posts/events by a super admin only.
-- The content is hidden (not deleted) and the reason is public.
create or replace function public.moderate(p_action text, p_type text, p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_title text; v_new text;
begin
  if p_action not in ('remove','restore') then raise exception 'Unknown action'; end if;
  if char_length(coalesce(p_reason,'')) < 20 then
    raise exception 'A clear reason (20+ characters) is required, it will be shown publicly';
  end if;
  v_new := case p_action when 'remove' then 'removed' else 'published' end;

  if p_type = 'comment' then
    if not public.is_staff() then raise exception 'Not allowed' using errcode = '42501'; end if;
    select left(body, 80) into v_title from public.comments where id = p_id;
    update public.comments set status = case p_action when 'remove' then 'removed' else 'visible' end
     where id = p_id;
  elsif p_type = 'post' then
    if not public.is_super_admin() then raise exception 'Only a super admin can act on official posts' using errcode = '42501'; end if;
    select title into v_title from public.posts where id = p_id;
    update public.posts set status = v_new where id = p_id;
  elsif p_type = 'event' then
    if not public.is_super_admin() then raise exception 'Only a super admin can act on events' using errcode = '42501'; end if;
    select title into v_title from public.events where id = p_id;
    update public.events set status = v_new where id = p_id;
  else
    raise exception 'Unknown target type';
  end if;

  if v_title is null then raise exception 'Nothing found to act on'; end if;
  insert into public.moderation_actions (actor_id, target_type, target_id, target_title, action, reason)
  values (auth.uid(), p_type, p_id, v_title, p_action, p_reason);
  update public.reports set status = 'actioned', handled_by = auth.uid(), handled_at = now()
   where target_type = p_type and target_id = p_id and status = 'open';
end $$;

-- ---------------------------------------------------------------------
-- H. Lost & found: only offices post; owners must give proof
-- ---------------------------------------------------------------------
create table if not exists public.lost_found_items (
  id uuid primary key default gen_random_uuid(),
  publisher_id uuid not null references public.publishers(id),
  posted_by uuid not null default auth.uid() references public.profiles(id),
  title text not null check (char_length(title) between 3 and 100),
  description text not null default '',                -- keep secret details out, owners must prove them
  photo_path text,
  found_where text not null,
  stored_at text not null,                             -- e.g. "Guild Office, Students' Centre"
  found_on date not null default current_date,
  status text not null default 'held' check (status in ('held','claimed','disposed')),
  created_at timestamptz not null default now()
);
create index if not exists lost_found_recent on public.lost_found_items (status, created_at desc);

create table if not exists public.lost_found_claims (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.lost_found_items(id) on delete cascade,
  claimant_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  proof text not null check (char_length(proof) >= 20),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  handled_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (item_id, claimant_id)
);

-- ---------------------------------------------------------------------
-- I. Surveys: one answer per person, anonymous by design, small groups hidden
-- ---------------------------------------------------------------------
create table if not exists public.surveys (
  id uuid primary key default gen_random_uuid(),
  publisher_id uuid not null references public.publishers(id),
  created_by uuid not null default auth.uid() references public.profiles(id),
  title text not null check (char_length(title) between 5 and 140),
  purpose text not null check (char_length(purpose) >= 30),  -- why we are asking, shown to students
  audience text not null default 'all',
  opens_at timestamptz not null default now(),
  closes_at timestamptz not null,
  status text not null default 'open' check (status in ('draft','open','closed','removed')),
  created_at timestamptz not null default now(),
  check (closes_at > opens_at)
);

create table if not exists public.survey_questions (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.surveys(id) on delete cascade,
  position int not null default 0,
  prompt text not null check (char_length(prompt) between 3 and 300),
  kind text not null check (kind in ('single','multi','scale','text')),
  options text[] not null default '{}'
);
create index if not exists survey_questions_survey on public.survey_questions (survey_id, position);

-- Who took part (so nobody votes twice) is stored apart from what they said.
create table if not exists public.survey_participation (
  survey_id uuid not null references public.surveys(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (survey_id, user_id)
);
create table if not exists public.survey_answers (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.surveys(id) on delete cascade,
  question_id uuid not null references public.survey_questions(id) on delete cascade,
  answer text not null check (char_length(answer) <= 1000)
);
create index if not exists survey_answers_q on public.survey_answers (survey_id, question_id);

create or replace function public.survey_questions_limit() returns trigger
language plpgsql as $$
begin
  if (select count(*) from public.survey_questions where survey_id = new.survey_id) >= 15 then
    raise exception 'A survey can have at most 15 questions. Short surveys get honest answers.';
  end if;
  return new;
end $$;
drop trigger if exists survey_questions_limit on public.survey_questions;
create trigger survey_questions_limit before insert on public.survey_questions
  for each row execute function public.survey_questions_limit();

-- Submit all answers at once: {"<question_id>": "answer" | ["a","b"]}
create or replace function public.submit_survey(p_survey uuid, p_answers jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare s public.surveys; q record; v jsonb; item text;
begin
  select * into s from public.surveys where id = p_survey;
  if s.id is null or s.status <> 'open' or now() not between s.opens_at and s.closes_at then
    raise exception 'This survey is not open';
  end if;
  insert into public.survey_participation (survey_id, user_id) values (p_survey, auth.uid());  -- unique: one go only
  for q in select id, kind, options from public.survey_questions where survey_id = p_survey loop
    v := p_answers -> q.id::text;
    continue when v is null or v = 'null'::jsonb;
    if jsonb_typeof(v) = 'array' then
      for item in select jsonb_array_elements_text(v) loop
        insert into public.survey_answers (survey_id, question_id, answer) values (p_survey, q.id, item);
      end loop;
    else
      insert into public.survey_answers (survey_id, question_id, answer) values (p_survey, q.id, v #>> '{}');
    end if;
  end loop;
end $$;

-- Results only for the office that asked (or super admin), and only once at
-- least 5 people have answered, so no one can be singled out.
create or replace function public.survey_results(p_survey uuid)
returns table (question_id uuid, answer text, n bigint)
language plpgsql stable security definer set search_path = public as $$
declare s public.surveys;
begin
  select * into s from public.surveys where id = p_survey;
  if s.id is null or not public.can_publish(s.publisher_id, 'surveys') then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  if (select count(*) from public.survey_participation where survey_id = p_survey) < 5 then
    raise exception 'Results unlock after 5 responses';
  end if;
  return query
    select a.question_id, a.answer, count(*) from public.survey_answers a
     where a.survey_id = p_survey group by a.question_id, a.answer order by a.question_id, 3 desc;
end $$;

-- ---------------------------------------------------------------------
-- J. Tutors: profile, modules with price, requests, reviews, earned badge
-- ---------------------------------------------------------------------
create table if not exists public.tutor_profiles (
  tutor_id uuid primary key references public.profiles(id) on delete cascade,
  bio text not null default '' check (char_length(bio) <= 600),
  contact_whatsapp text,
  availability text not null default '' check (char_length(availability) <= 400),
  updated_at timestamptz not null default now()
);

create table if not exists public.tutor_modules (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  course_code text not null,
  course_name text,
  grade_achieved text,                                  -- what the tutor says they scored
  price_ugx int not null check (price_ugx between 0 and 500000),   -- per hour
  is_active boolean not null default true,
  unique (tutor_id, course_code)
);

create table if not exists public.tutor_requests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  tutor_id uuid not null references public.profiles(id) on delete cascade,
  course_code text not null,
  message text not null default '' check (char_length(message) <= 500),
  status text not null default 'pending' check (status in ('pending','accepted','declined','completed')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check (student_id <> tutor_id)
);

-- Tutor answers the request; only the STUDENT can say the lesson happened.
create or replace function public.tutor_requests_transition() returns trigger
language plpgsql as $$
begin
  if new.status is distinct from old.status and current_user in ('authenticated','anon') then
    if auth.uid() = old.tutor_id and new.status in ('accepted','declined') and old.status = 'pending' then
      null;
    elsif auth.uid() = old.student_id and new.status = 'completed' and old.status = 'accepted' then
      new.completed_at := now();
    else
      raise exception 'That status change is not allowed' using errcode = '42501';
    end if;
  end if;
  if new.student_id <> old.student_id or new.tutor_id <> old.tutor_id or new.course_code <> old.course_code then
    raise exception 'Request details cannot be changed';
  end if;
  return new;
end $$;
drop trigger if exists tutor_requests_transition on public.tutor_requests;
create trigger tutor_requests_transition before update on public.tutor_requests
  for each row execute function public.tutor_requests_transition();

create table if not exists public.tutor_reviews (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.tutor_requests(id) on delete cascade,
  tutor_id uuid not null references public.profiles(id) on delete cascade,
  student_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  course_code text not null,
  rating int not null check (rating between 1 and 5),
  comment text check (comment is null or char_length(comment) <= 500),
  created_at timestamptz not null default now()
);
create index if not exists tutor_reviews_tutor on public.tutor_reviews (tutor_id, course_code);

-- Fair score: Bayesian average. Everyone starts near the platform average
-- (anchored at 4.0 until the platform has lots of reviews) and
-- moves away only as real reviews arrive. So 2 reviews of 5 stars cannot beat
-- 40 reviews averaging 4.7, and a tutor with 8 thin modules is not rewarded
-- for spreading out. All modules are pooled, weighted by their review counts.
create or replace function public.tutor_score(p_tutor uuid, p_course text default null)
returns table (score numeric, reviews int, reviewers int)
language sql stable security definer set search_path = public as $$
  with g as (select (coalesce(sum(rating), 0) + 4.0 * 50) / (count(*) + 50) as c from public.tutor_reviews),
       t as (select count(*) as n, coalesce(sum(rating), 0) as s, count(distinct student_id) as r
               from public.tutor_reviews
              where tutor_id = p_tutor and (p_course is null or course_code = p_course))
  select round(((g.c * 5 + t.s) / (5 + t.n))::numeric, 2), t.n::int, t.r::int from g, t;
$$;

-- Blue tick is EARNED: 10+ reviews from 5+ different students and score 4.2+.
-- It is lost if the score drops below 3.8 (the gap stops flickering).
create or replace function public.recompute_tutor_verification(p_tutor uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s record; cur boolean;
begin
  select * into s from public.tutor_score(p_tutor);
  select tutor_verified into cur from public.profiles where id = p_tutor;
  if not coalesce(cur, false) and s.reviews >= 10 and s.reviewers >= 5 and s.score >= 4.2 then
    update public.profiles set tutor_verified = true, tutor_verified_at = now() where id = p_tutor;
  elsif coalesce(cur, false) and s.score < 3.8 then
    update public.profiles set tutor_verified = false where id = p_tutor;
  end if;
end $$;

create or replace function public.tutor_reviews_after() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.recompute_tutor_verification(new.tutor_id);
  return null;
end $$;
drop trigger if exists tutor_reviews_after on public.tutor_reviews;
create trigger tutor_reviews_after after insert on public.tutor_reviews
  for each row execute function public.tutor_reviews_after();

-- ---------------------------------------------------------------------
-- K. Offices on the map: what they do, what to bring, hours, directions
-- ---------------------------------------------------------------------
create table if not exists public.campuses (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  address text,
  lat double precision,
  lng double precision,
  notes text
);

alter table public.help_offices
  add column if not exists campus_id uuid references public.campuses(id),
  add column if not exists what_we_do text[] not null default '{}',
  add column if not exists what_we_dont text[] not null default '{}',
  add column if not exists bring text[] not null default '{}',     -- what you must bring to be served
  add column if not exists hours jsonb not null default '[]'::jsonb, -- [{"days":[1,2,3,4,5],"open":"08:00","close":"17:00"}]
  add column if not exists directions text,                        -- step-by-step from the main entrance
  add column if not exists source text,                            -- which official document/person confirmed this
  add column if not exists last_verified_at timestamptz;

-- ---------------------------------------------------------------------
-- L. Policy acceptance (privacy policy, terms, posting code)
-- ---------------------------------------------------------------------
create table if not exists public.policy_acceptances (
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  policy text not null check (policy in ('privacy','terms','posting_code')),
  version text not null,
  accepted_at timestamptz not null default now(),
  primary key (user_id, policy, version)
);

-- ---------------------------------------------------------------------
-- M. Pictures: small and image-only. Videos are YouTube links, not uploads.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('campus-media', 'campus-media', true, 1048576, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "publishers upload media" on storage.objects;
create policy "publishers upload media" on storage.objects for insert to authenticated
  with check (bucket_id = 'campus-media' and public.is_active_publisher());
drop policy if exists "owners change media" on storage.objects;
create policy "owners change media" on storage.objects for update to authenticated
  using (bucket_id = 'campus-media' and owner_id = auth.uid()::text);
drop policy if exists "owners delete media" on storage.objects;
create policy "owners delete media" on storage.objects for delete to authenticated
  using (bucket_id = 'campus-media' and (owner_id = auth.uid()::text or public.is_super_admin()));

-- ---------------------------------------------------------------------
-- N. Row Level Security for the new tables
-- ---------------------------------------------------------------------
alter table public.publishers enable row level security;
alter table public.publisher_members enable row level security;
alter table public.posts enable row level security;
alter table public.post_revisions enable row level security;
alter table public.event_speakers enable row level security;
alter table public.comments enable row level security;
alter table public.reactions enable row level security;
alter table public.reports enable row level security;
alter table public.moderation_actions enable row level security;
alter table public.lost_found_items enable row level security;
alter table public.lost_found_claims enable row level security;
alter table public.surveys enable row level security;
alter table public.survey_questions enable row level security;
alter table public.survey_participation enable row level security;
alter table public.survey_answers enable row level security;
alter table public.tutor_profiles enable row level security;
alter table public.tutor_modules enable row level security;
alter table public.tutor_requests enable row level security;
alter table public.tutor_reviews enable row level security;
alter table public.campuses enable row level security;
alter table public.policy_acceptances enable row level security;

-- publishers & members: everyone can see who speaks for whom
drop policy if exists "read publishers" on public.publishers;
create policy "read publishers" on public.publishers for select to authenticated using (true);
drop policy if exists "super admin manages publishers" on public.publishers;
create policy "super admin manages publishers" on public.publishers for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

drop policy if exists "read members" on public.publisher_members;
create policy "read members" on public.publisher_members for select to authenticated using (true);
drop policy if exists "appoint members" on public.publisher_members;
create policy "appoint members" on public.publisher_members for insert to authenticated
  with check (public.can_publish(publisher_id, 'manage_members')
              and expires_at <= now() + public.max_term() + interval '1 day'
              and appointed_by = auth.uid()
              and user_id <> auth.uid());              -- you cannot appoint yourself
drop policy if exists "end a term" on public.publisher_members;
create policy "end a term" on public.publisher_members for update to authenticated
  using (public.can_publish(publisher_id, 'manage_members'))
  with check (public.can_publish(publisher_id, 'manage_members')
              and expires_at <= now() + public.max_term() + interval '1 day');

-- posts: published ones are public; authors and super admins also see the rest
drop policy if exists "read posts" on public.posts;
create policy "read posts" on public.posts for select to authenticated
  using ((status = 'published' and (expires_at is null or expires_at > now()))
         or author_id = auth.uid() or public.is_super_admin());
drop policy if exists "publish posts" on public.posts;
create policy "publish posts" on public.posts for insert to authenticated
  with check (public.can_publish(publisher_id, public.scope_for_kind(kind))
              and status in ('draft','published'));
drop policy if exists "edit own posts" on public.posts;
create policy "edit own posts" on public.posts for update to authenticated
  using (author_id = auth.uid() and status <> 'removed'
         and public.can_publish(publisher_id, public.scope_for_kind(kind)))
  with check (author_id = auth.uid() and status in ('draft','published'));

drop policy if exists "read revisions" on public.post_revisions;
create policy "read revisions" on public.post_revisions for select to authenticated
  using (public.is_super_admin());

-- events: replace the old staff-only rule with office-based rules
drop policy if exists "read events" on public.events;
create policy "read events" on public.events for select to authenticated
  using (status = 'published' or created_by = auth.uid() or public.is_super_admin());
drop policy if exists "staff write events" on public.events;
drop policy if exists "offices create events" on public.events;
create policy "offices create events" on public.events for insert to authenticated
  with check (public.can_publish(publisher_id, 'events') and created_by = auth.uid()
              and status in ('draft','published'));
drop policy if exists "offices edit events" on public.events;
create policy "offices edit events" on public.events for update to authenticated
  using (created_by = auth.uid() and public.can_publish(publisher_id, 'events') and status <> 'removed')
  with check (created_by = auth.uid() and status in ('draft','published'));
drop policy if exists "super admin events" on public.events;
create policy "super admin events" on public.events for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

drop policy if exists "read speakers" on public.event_speakers;
create policy "read speakers" on public.event_speakers for select to authenticated using (true);
drop policy if exists "organiser manages speakers" on public.event_speakers;
create policy "organiser manages speakers" on public.event_speakers for all to authenticated
  using (exists (select 1 from public.events e where e.id = event_id
                  and (e.created_by = auth.uid() or public.is_super_admin())))
  with check (exists (select 1 from public.events e where e.id = event_id
                  and (e.created_by = auth.uid() or public.is_super_admin())));

-- comments and likes
drop policy if exists "read comments" on public.comments;
create policy "read comments" on public.comments for select to authenticated
  using (status = 'visible' or author_id = auth.uid() or public.is_staff());
drop policy if exists "write comments" on public.comments;
create policy "write comments" on public.comments for insert to authenticated
  with check (author_id = auth.uid() and status = 'visible');
drop policy if exists "edit own comment" on public.comments;
create policy "edit own comment" on public.comments for update to authenticated
  using (author_id = auth.uid() and status = 'visible')
  with check (author_id = auth.uid() and status = 'visible');
drop policy if exists "delete own comment" on public.comments;
create policy "delete own comment" on public.comments for delete to authenticated
  using (author_id = auth.uid());

drop policy if exists "read reactions" on public.reactions;
create policy "read reactions" on public.reactions for select to authenticated using (true);
drop policy if exists "react" on public.reactions;
create policy "react" on public.reactions for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "unreact" on public.reactions;
create policy "unreact" on public.reactions for delete to authenticated using (user_id = auth.uid());

-- reports and the public moderation log
drop policy if exists "file report" on public.reports;
create policy "file report" on public.reports for insert to authenticated with check (reporter_id = auth.uid());
drop policy if exists "read reports" on public.reports;
create policy "read reports" on public.reports for select to authenticated
  using (reporter_id = auth.uid() or public.is_staff());
drop policy if exists "read moderation log" on public.moderation_actions;
create policy "read moderation log" on public.moderation_actions for select to authenticated using (true);

-- lost & found
drop policy if exists "read lost found" on public.lost_found_items;
create policy "read lost found" on public.lost_found_items for select to authenticated using (true);
drop policy if exists "offices post lost found" on public.lost_found_items;
create policy "offices post lost found" on public.lost_found_items for insert to authenticated
  with check (public.can_publish(publisher_id, 'lost_found') and posted_by = auth.uid());
drop policy if exists "offices update lost found" on public.lost_found_items;
create policy "offices update lost found" on public.lost_found_items for update to authenticated
  using (public.can_publish(publisher_id, 'lost_found'))
  with check (public.can_publish(publisher_id, 'lost_found'));

drop policy if exists "claim item" on public.lost_found_claims;
create policy "claim item" on public.lost_found_claims for insert to authenticated
  with check (claimant_id = auth.uid());
drop policy if exists "read claims" on public.lost_found_claims;
create policy "read claims" on public.lost_found_claims for select to authenticated
  using (claimant_id = auth.uid() or exists (
           select 1 from public.lost_found_items i
            where i.id = item_id and public.can_publish(i.publisher_id, 'lost_found')));
drop policy if exists "decide claims" on public.lost_found_claims;
create policy "decide claims" on public.lost_found_claims for update to authenticated
  using (exists (select 1 from public.lost_found_items i
                  where i.id = item_id and public.can_publish(i.publisher_id, 'lost_found')))
  with check (handled_by = auth.uid());

-- surveys (answers are only reachable through submit_survey / survey_results)
drop policy if exists "read surveys" on public.surveys;
create policy "read surveys" on public.surveys for select to authenticated
  using (status in ('open','closed') or created_by = auth.uid() or public.is_super_admin());
drop policy if exists "offices create surveys" on public.surveys;
create policy "offices create surveys" on public.surveys for insert to authenticated
  with check (public.can_publish(publisher_id, 'surveys') and created_by = auth.uid()
              and status in ('draft','open'));
drop policy if exists "offices edit surveys" on public.surveys;
create policy "offices edit surveys" on public.surveys for update to authenticated
  using (created_by = auth.uid() and public.can_publish(publisher_id, 'surveys'))
  with check (created_by = auth.uid() and status in ('draft','open','closed'));

drop policy if exists "read questions" on public.survey_questions;
create policy "read questions" on public.survey_questions for select to authenticated using (true);
drop policy if exists "owners write questions" on public.survey_questions;
create policy "owners write questions" on public.survey_questions for all to authenticated
  using (exists (select 1 from public.surveys s where s.id = survey_id and s.created_by = auth.uid()))
  with check (exists (select 1 from public.surveys s where s.id = survey_id and s.created_by = auth.uid()
                       and s.status = 'draft'));
drop policy if exists "see own participation" on public.survey_participation;
create policy "see own participation" on public.survey_participation for select to authenticated
  using (user_id = auth.uid());

-- tutors
drop policy if exists "read tutor profiles" on public.tutor_profiles;
create policy "read tutor profiles" on public.tutor_profiles for select to authenticated using (true);
drop policy if exists "own tutor profile" on public.tutor_profiles;
create policy "own tutor profile" on public.tutor_profiles for all to authenticated
  using (tutor_id = auth.uid()) with check (tutor_id = auth.uid());

drop policy if exists "read tutor modules" on public.tutor_modules;
create policy "read tutor modules" on public.tutor_modules for select to authenticated using (true);
drop policy if exists "own tutor modules" on public.tutor_modules;
create policy "own tutor modules" on public.tutor_modules for all to authenticated
  using (tutor_id = auth.uid()) with check (tutor_id = auth.uid());

drop policy if exists "request a tutor" on public.tutor_requests;
create policy "request a tutor" on public.tutor_requests for insert to authenticated
  with check (student_id = auth.uid() and status = 'pending');
drop policy if exists "read own requests" on public.tutor_requests;
create policy "read own requests" on public.tutor_requests for select to authenticated
  using (student_id = auth.uid() or tutor_id = auth.uid());
drop policy if exists "answer or complete" on public.tutor_requests;
create policy "answer or complete" on public.tutor_requests for update to authenticated
  using (student_id = auth.uid() or tutor_id = auth.uid())
  with check (student_id = auth.uid() or tutor_id = auth.uid());

drop policy if exists "read reviews" on public.tutor_reviews;
create policy "read reviews" on public.tutor_reviews for select to authenticated using (true);
drop policy if exists "review after a real lesson" on public.tutor_reviews;
create policy "review after a real lesson" on public.tutor_reviews for insert to authenticated
  with check (student_id = auth.uid() and exists (
    select 1 from public.tutor_requests r
     where r.id = request_id and r.student_id = auth.uid()
       and r.tutor_id = tutor_reviews.tutor_id
       and r.course_code = tutor_reviews.course_code
       and r.status = 'completed'));

-- campuses & policies
drop policy if exists "read campuses" on public.campuses;
create policy "read campuses" on public.campuses for select to authenticated using (true);
drop policy if exists "staff write campuses" on public.campuses;
create policy "staff write campuses" on public.campuses for all to authenticated
  using (public.is_staff()) with check (public.is_staff());

drop policy if exists "own acceptances" on public.policy_acceptances;
create policy "own acceptances" on public.policy_acceptances for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- O. Grants for the new tables and functions (least needed; RLS decides rows)
-- ---------------------------------------------------------------------
grant select on public.publishers to authenticated;
grant select, insert, update on public.publisher_members to authenticated;
grant select, insert, update on public.posts to authenticated;
grant select on public.post_revisions to authenticated;
grant select, insert, update, delete on public.event_speakers to authenticated;
grant select, insert, update, delete on public.comments to authenticated;
grant select, insert, delete on public.reactions to authenticated;
grant select, insert on public.reports to authenticated;
grant select on public.moderation_actions to authenticated;
grant select, insert, update on public.lost_found_items to authenticated;
grant select, insert, update on public.lost_found_claims to authenticated;
grant select, insert, update on public.surveys to authenticated;
grant select, insert, update, delete on public.survey_questions to authenticated;
grant select on public.survey_participation to authenticated;           -- no direct access to survey_answers
grant select, insert, update, delete on public.tutor_profiles to authenticated;
grant select, insert, update, delete on public.tutor_modules to authenticated;
grant select, insert, update on public.tutor_requests to authenticated;
grant select, insert on public.tutor_reviews to authenticated;           -- reviews are permanent
grant select on public.campuses to authenticated;
grant select, insert, update, delete on public.policy_acceptances to authenticated;
grant select on public.public_profiles to authenticated;
grant select on public.featured_events to authenticated;
grant all on all tables in schema public to service_role;

-- publishers/campuses writes by super admin / staff go through RLS policies above
grant insert, update, delete on public.publishers to authenticated;
grant insert, update, delete on public.campuses to authenticated;

grant execute on function public.set_user_role(uuid, text) to authenticated;
grant execute on function public.moderate(text, text, uuid, text) to authenticated;
grant execute on function public.submit_survey(uuid, jsonb) to authenticated;
grant execute on function public.survey_results(uuid) to authenticated;
grant execute on function public.tutor_score(uuid, text) to authenticated;
grant execute on function public.can_publish(uuid, text) to authenticated;
grant execute on function public.is_active_publisher() to authenticated;
grant execute on function public.is_super_admin() to authenticated;
revoke execute on function public.recompute_tutor_verification(uuid) from public, anon, authenticated;
