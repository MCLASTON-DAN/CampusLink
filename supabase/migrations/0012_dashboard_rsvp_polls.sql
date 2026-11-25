-- CampusLink 0012: admin dashboard, event RSVP + check-in, polls and quizzes.
-- Every table: RLS on, explicit grants, and only what each role needs.

-- =====================================================================
-- A. Activity: one row per person per day they open the app.
--    Used only for counts (daily active users). Never shown per person.
-- =====================================================================
create table if not exists public.activity_days (
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null default (now() at time zone 'Africa/Kampala')::date,
  primary key (user_id, day)
);
create index if not exists activity_days_day on public.activity_days (day);
alter table public.activity_days enable row level security;
revoke all on public.activity_days from anon, authenticated;   -- only via functions

create or replace function public.touch_activity() returns void
language sql security definer set search_path = public as $$
  insert into public.activity_days (user_id) values (auth.uid()) on conflict do nothing;
$$;
revoke execute on function public.touch_activity() from public, anon;
grant execute on function public.touch_activity() to authenticated;

-- One call returns the whole dashboard. Staff and super admin only.
create or replace function public.admin_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare today date := (now() at time zone 'Africa/Kampala')::date;
begin
  if not public.is_staff() then
    raise exception 'Only staff can see the dashboard' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'users_total',      (select count(*) from public.profiles),
    'users_new_7d',     (select count(*) from public.profiles where created_at > now() - interval '7 days'),
    'active_today',     (select count(*) from public.activity_days where day = today),
    'active_7d',        (select count(distinct user_id) from public.activity_days where day > today - 7),
    'daily_active',     (select coalesce(jsonb_agg(jsonb_build_object('day', d::date, 'n',
                            (select count(*) from public.activity_days a where a.day = d::date)) order by d), '[]')
                         from generate_series(today - 13, today, interval '1 day') d),
    'posts_7d',         (select count(*) from public.posts where status = 'published' and published_at > now() - interval '7 days'),
    'views_7d',         (select count(*) from public.post_views where viewed_at > now() - interval '7 days'),
    'top_posts',        (select coalesce(jsonb_agg(t), '[]') from (
                            select p.id, p.title, count(v.*)::int as views
                            from public.posts p join public.post_views v on v.post_id = p.id
                            where v.viewed_at > now() - interval '7 days'
                            group by p.id, p.title order by views desc limit 5) t),
    'open_reports',     (select count(*) from public.reports where status = 'open'),
    'open_tutor_reports',(select count(*) from public.tutor_reports where status = 'open'),
    'major_requests',   (select count(*) from public.events where major_status = 'requested'),
    'pending_claims',   (select count(*) from public.lost_found_claims where status = 'pending'),
    'open_help',        (select count(*) from public.help_requests where status in ('open','in_progress')),
    'terms_ending_14d', (select count(*) from public.publisher_members
                         where revoked_at is null and expires_at between now() and now() + interval '14 days'),
    'upcoming_events',  (select count(*) from public.events where status = 'published' and starts_at > now())
  );
end $$;
revoke execute on function public.admin_overview() from public, anon;
grant execute on function public.admin_overview() to authenticated;

-- =====================================================================
-- B. Event RSVP and check-in.
--    Each "I'm going" gets a private 6-character code (shown as a QR).
--    Only the organising office can check people in.
-- =====================================================================
create table if not exists public.event_rsvps (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  code text not null default upper(substr(md5(gen_random_uuid()::text), 1, 6)),
  created_at timestamptz not null default now(),
  checked_in_at timestamptz,
  checked_in_by uuid references public.profiles(id),
  primary key (event_id, user_id)
);
create index if not exists event_rsvps_user on public.event_rsvps (user_id);
create index if not exists fk_event_rsvps_checked_in_by on public.event_rsvps (checked_in_by);
alter table public.event_rsvps enable row level security;

drop policy if exists "rsvp myself" on public.event_rsvps;
create policy "rsvp myself" on public.event_rsvps for insert to authenticated
  with check (user_id = (select auth.uid())
    and exists (select 1 from public.events e where e.id = event_id and e.status = 'published' and e.starts_at > now() - interval '6 hours'));
drop policy if exists "see my rsvp or organiser" on public.event_rsvps;
create policy "see my rsvp or organiser" on public.event_rsvps for select to authenticated
  using (user_id = (select auth.uid())
    or exists (select 1 from public.events e where e.id = event_id
               and (public.can_publish(e.publisher_id, 'events') or public.is_staff())));
drop policy if exists "cancel my rsvp" on public.event_rsvps;
create policy "cancel my rsvp" on public.event_rsvps for delete to authenticated
  using (user_id = (select auth.uid()) and checked_in_at is null);
grant select, insert, delete on public.event_rsvps to authenticated;

-- How many are going / came. Public numbers, no names.
create or replace function public.event_rsvp_counts(p_events uuid[])
returns table (event_id uuid, going int, checked_in int)
language sql stable security definer set search_path = public as $$
  select r.event_id, count(*)::int, count(r.checked_in_at)::int
  from public.event_rsvps r where r.event_id = any (p_events) group by r.event_id;
$$;
revoke execute on function public.event_rsvp_counts(uuid[]) from public, anon;
grant execute on function public.event_rsvp_counts(uuid[]) to authenticated;

-- Organiser checks a person in with the code from their QR.
create or replace function public.event_check_in(p_event uuid, p_code text) returns text
language plpgsql security definer set search_path = public as $$
declare pub uuid; who text; already timestamptz;
begin
  select publisher_id into pub from public.events where id = p_event;
  if pub is null or not (public.can_publish(pub, 'events') or public.is_super_admin()) then
    raise exception 'Only the organising office can check people in' using errcode = '42501';
  end if;
  select p.full_name, r.checked_in_at into who, already
  from public.event_rsvps r join public.profiles p on p.id = r.user_id
  where r.event_id = p_event and r.code = upper(trim(p_code));
  if who is null then
    raise exception 'Code not found for this event. Ask them to tap "I''m going" first.';
  end if;
  if already is not null then
    return who || ' was already checked in at ' || to_char(already at time zone 'Africa/Kampala', 'HH24:MI');
  end if;
  update public.event_rsvps set checked_in_at = now(), checked_in_by = auth.uid()
  where event_id = p_event and code = upper(trim(p_code));
  return who || ' checked in';
end $$;
revoke execute on function public.event_check_in(uuid, text) from public, anon;
grant execute on function public.event_check_in(uuid, text) to authenticated;

-- =====================================================================
-- C. Polls and quizzes inside news posts.
--    A post can carry up to 5 questions. A poll shows results after you
--    vote. A quiz also reveals the right answer after you answer.
-- =====================================================================
create table if not exists public.post_questions (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  position int not null default 0,
  kind text not null check (kind in ('poll','quiz')),
  prompt text not null check (char_length(prompt) between 3 and 200),
  options text[] not null check (cardinality(options) between 2 and 6),
  correct_index int,                       -- quizzes only; hidden from students
  check ((kind = 'quiz') = (correct_index is not null)),
  check (correct_index is null or (correct_index >= 0 and correct_index < cardinality(options)))
);
create index if not exists post_questions_post on public.post_questions (post_id, position);
alter table public.post_questions enable row level security;

-- Only the office that owns the post can add or remove its questions.
drop policy if exists "post office manages questions" on public.post_questions;
create policy "post office manages questions" on public.post_questions for all to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id
                 and (p.author_id = (select auth.uid()) or public.is_super_admin())))
  with check (exists (select 1 from public.posts p where p.id = post_id
                 and (p.author_id = (select auth.uid()) or public.is_super_admin())));
-- Authors can read their own questions (the policy limits rows to their
-- posts); students read through post_questions_for(), which hides answers.
grant select, insert, update, delete on public.post_questions to authenticated;

create table if not exists public.post_answers (
  question_id uuid not null references public.post_questions(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  option_index int not null check (option_index between 0 and 5),
  created_at timestamptz not null default now(),
  primary key (question_id, user_id)
);
create index if not exists fk_post_answers_user on public.post_answers (user_id);
alter table public.post_answers enable row level security;
revoke all on public.post_answers from anon, authenticated;   -- only via functions

-- Questions of a post, with counts and the right answer ONLY after you answered.
create or replace function public.post_questions_for(p_post uuid)
returns table (id uuid, kind text, prompt text, options text[], pos int,
               my_answer int, correct_index int, counts int[], total int)
language sql stable security definer set search_path = public as $$
  select q.id, q.kind, q.prompt, q.options, q.position,
         a.option_index,
         case when a.option_index is not null or exists (select 1 from public.posts p where p.id = q.post_id and p.author_id = auth.uid())
              then q.correct_index end,
         case when a.option_index is not null or exists (select 1 from public.posts p where p.id = q.post_id and p.author_id = auth.uid())
              then (select array_agg((select count(*)::int from public.post_answers x where x.question_id = q.id and x.option_index = i) order by i)
                    from generate_series(0, cardinality(q.options) - 1) i) end,
         (select count(*)::int from public.post_answers x where x.question_id = q.id)
  from public.post_questions q
  left join public.post_answers a on a.question_id = q.id and a.user_id = auth.uid()
  where q.post_id = p_post
    and exists (select 1 from public.posts p where p.id = p_post and p.status = 'published')
  order by q.position;
$$;
revoke execute on function public.post_questions_for(uuid) from public, anon;
grant execute on function public.post_questions_for(uuid) to authenticated;

-- One answer per person per question; it cannot be changed (fair quizzes).
create or replace function public.answer_post_question(p_question uuid, p_option int) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  select cardinality(q.options) into n from public.post_questions q
  join public.posts p on p.id = q.post_id and p.status = 'published'
  where q.id = p_question;
  if n is null then raise exception 'Question not found'; end if;
  if p_option < 0 or p_option >= n then raise exception 'Pick one of the options'; end if;
  insert into public.post_answers (question_id, user_id, option_index)
  values (p_question, auth.uid(), p_option);
exception when unique_violation then
  raise exception 'You already answered this one';
end $$;
revoke execute on function public.answer_post_question(uuid, int) from public, anon;
grant execute on function public.answer_post_question(uuid, int) to authenticated;
