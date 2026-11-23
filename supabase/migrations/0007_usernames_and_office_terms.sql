-- CampusLink 0007: usernames, finding people to appoint, and clear rules for
-- how an office term ends (naturally, early, or removal for misconduct).

-- ---------------------------------------------------------------------
-- A. Usernames: @like.this, unique, changeable once every 30 days.
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists username text,
  add column if not exists username_changed_at timestamptz;
alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles
  add constraint profiles_username_format check (username is null or username ~ '^[a-z0-9._]{3,20}$');
create unique index if not exists profiles_username_unique on public.profiles (username);

-- Names nobody may take, so no one can pretend to be an office.
create or replace function public.username_reserved(u text) returns boolean
language sql immutable set search_path = public as $$
  select u ~ '^(admin|administrator|administration|guild|cavendish|newsroom|official|support|campuslink|moderator|staff|university|registrar|lecturer|security|help|system)'
      or u ~ '(admin|official)$';
$$;

-- A free username made from a person's name: "Okecho Danmark" -> okecho.danmark
create or replace function public.make_username(p_name text) returns text
language plpgsql set search_path = public as $$
declare base text; cand text; n int := 0;
begin
  base := lower(regexp_replace(trim(coalesce(p_name, '')), '[^A-Za-z0-9]+', '.', 'g'));
  base := trim(both '.' from base);
  base := left(base, 16);
  base := trim(both '.' from base);
  if char_length(base) < 3 or public.username_reserved(base) then base := 'student'; end if;
  cand := base;
  while exists (select 1 from public.profiles where username = cand) loop
    n := n + 1;
    cand := left(base, 16) || n::text;
  end loop;
  return cand;
end $$;

create or replace function public.profiles_username_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.username := coalesce(nullif(lower(trim(new.username)), ''), public.make_username(new.full_name));
    return new;
  end if;
  new.username := nullif(lower(trim(new.username)), '');
  if new.username is null then new.username := old.username; end if;
  if new.username is distinct from old.username then
    if current_user in ('authenticated', 'anon') then
      if public.username_reserved(new.username) then
        raise exception 'That username is reserved. Please choose another.';
      end if;
      if old.username_changed_at is not null and old.username_changed_at > now() - interval '30 days' then
        raise exception 'You can change your username again on %.',
          to_char(old.username_changed_at + interval '30 days', 'DD Mon YYYY');
      end if;
    end if;
    if exists (select 1 from public.profiles where username = new.username and id <> new.id) then
      raise exception 'That username is taken. Try adding a number or dot.';
    end if;
    new.username_changed_at := now();
  end if;
  return new;
end $$;
drop trigger if exists profiles_username_guard on public.profiles;
create trigger profiles_username_guard before insert or update of username, full_name on public.profiles
  for each row execute function public.profiles_username_guard();

-- Give everyone who already signed up a username (their first change is free).
update public.profiles p set username = public.make_username(p.full_name)
where p.username is null;
update public.profiles set username_changed_at = null where username_changed_at is not null;

-- Public profile now includes the username.
drop view if exists public.public_profiles;
create view public.public_profiles with (security_invoker = true) as
select p.id, p.full_name, p.username, p.programme, p.year_of_study, p.faculty,
       p.is_tutor, p.tutor_subjects, p.is_buddy_mentor, p.tutor_verified,
       p.avatar_path,
       case when p.status_until is null or p.status_until > now() then p.status_text end as status_text,
       case when p.status_until > now() then p.status_until end as status_until,
       coalesce(o.position_title, case when l.is_lecturer then 'Lecturer' end) as office_title,
       o.office_name,
       case when p.role = 'super_admin' or o.kind = 'administration' then 'red'
            when l.is_lecturer then 'orange'
            when o.kind = 'guild' then 'green'
            when o.kind = 'press' then 'purple'
            when p.tutor_verified then 'blue' end as badge
from public.profiles p
left join lateral (
  select m.position_title, pb.kind, pb.name as office_name
  from public.publisher_members m
  join public.publishers pb on pb.id = m.publisher_id and pb.is_active
  where m.user_id = p.id and m.revoked_at is null
    and now() between m.starts_at and m.expires_at
  order by (pb.kind = 'administration') desc, (pb.kind = 'guild') desc, (pb.kind = 'press') desc
  limit 1) o on true
left join lateral (
  select exists (select 1 from public.course_lecturers cl where cl.lecturer_id = p.id) as is_lecturer) l on true;
grant select on public.public_profiles to authenticated;

-- ---------------------------------------------------------------------
-- B. Find a person by username or name. Only for people who appoint:
--    super admin, staff, and office managers. Never returns email or
--    student number. At most 10 results.
-- ---------------------------------------------------------------------
create or replace function public.search_people(p_query text)
returns table (id uuid, full_name text, username text, programme text, year_of_study int,
               avatar_path text, badge text, office_title text)
language plpgsql stable security definer set search_path = public as $$
declare q text := lower(trim(both '@ ' from coalesce(p_query, '')));
begin
  if not (public.is_staff() or exists (
      select 1 from public.publisher_members m
      where m.user_id = auth.uid() and m.revoked_at is null
        and now() between m.starts_at and m.expires_at and 'manage_members' = any (m.scopes))) then
    raise exception 'Only people who appoint members can search' using errcode = '42501';
  end if;
  if char_length(q) < 2 then return; end if;
  return query
    select pp.id, pp.full_name, pp.username, pp.programme, pp.year_of_study, pp.avatar_path, pp.badge, pp.office_title
    from public.public_profiles pp
    where pp.username like replace(replace(q, '%', ''), '_', '\_') || '%'
       or lower(pp.full_name) like '%' || replace(q, '%', '') || '%'
    order by (pp.username = q) desc, (pp.username like q || '%') desc, pp.full_name
    limit 10;
end $$;
revoke execute on function public.search_people(text) from public, anon;
grant execute on function public.search_people(text) to authenticated;

-- ---------------------------------------------------------------------
-- C. How a term ends. Reasons are public, so everyone has context.
--    early   = resigned / reshuffle / graduated (managers or super admin)
--    removed = misconduct (super admin ONLY, written reason 20+ characters)
--    A term that simply reaches its end date needs no action.
-- ---------------------------------------------------------------------
alter table public.publisher_members
  add column if not exists end_kind text check (end_kind in ('early','removed')),
  add column if not exists end_reason text check (end_reason is null or char_length(end_reason) <= 500),
  add column if not exists ended_by uuid references public.profiles(id),
  add column if not exists reminded_14 boolean not null default false,
  add column if not exists reminded_3 boolean not null default false;

create or replace function public.members_term_rules() returns trigger
language plpgsql security definer set search_path = public as $$
declare others int;
begin
  if old.revoked_at is not null and new.revoked_at is null then
    raise exception 'An ended term cannot be reopened. Appoint the person again instead.';
  end if;

  if new.revoked_at is not null and old.revoked_at is null then
    new.ended_by := auth.uid();
    new.end_kind := coalesce(new.end_kind, 'early');
    new.end_reason := nullif(trim(coalesce(new.end_reason, '')), '');
    if new.end_kind = 'removed' then
      if not public.is_super_admin() then
        raise exception 'Only the super admin can remove someone for misconduct.' using errcode = '42501';
      end if;
      if char_length(coalesce(new.end_reason, '')) < 20 then
        raise exception 'Explain why they were removed (at least 20 characters). It will be shown publicly.';
      end if;
    elsif char_length(coalesce(new.end_reason, '')) < 3 then
      raise exception 'Give a short reason for ending the term early.';
    end if;
    -- Never leave an office with nobody who can manage it (super admin can).
    if 'manage_members' = any (old.scopes) and not public.is_super_admin() then
      select count(*) into others from public.publisher_members m
      where m.publisher_id = old.publisher_id and m.id <> old.id and m.revoked_at is null
        and now() between m.starts_at and m.expires_at and 'manage_members' = any (m.scopes);
      if others = 0 then
        raise exception 'This is the last person who can manage this office. Appoint another manager first, or ask the super admin.';
      end if;
    end if;
  end if;

  -- A renewed term gets fresh reminders.
  if new.expires_at is distinct from old.expires_at then
    new.reminded_14 := false;
    new.reminded_3 := false;
  end if;
  return new;
end $$;
drop trigger if exists members_term_rules on public.publisher_members;
create trigger members_term_rules before update on public.publisher_members
  for each row execute function public.members_term_rules();

-- Tell people when they are appointed or their term ends.
alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications
  add constraint notifications_kind_check check (kind in ('course','official','event','tutor','request','office'));

create or replace function public.notify_membership() returns trigger
language plpgsql security definer set search_path = public as $$
declare office text;
begin
  select name into office from public.publishers where id = new.publisher_id;
  if tg_op = 'INSERT' then
    insert into public.notifications (user_id, kind, title, body, link)
    values (new.user_id, 'office', 'You are now ' || new.position_title,
            office || ' · until ' || to_char(new.expires_at at time zone 'Africa/Kampala', 'DD Mon YYYY'), '/profile');
  elsif new.revoked_at is not null and old.revoked_at is null then
    insert into public.notifications (user_id, kind, title, body, link, priority)
    values (new.user_id, 'office',
            case when new.end_kind = 'removed' then 'You were removed from office' else 'Your term has ended' end,
            office || coalesce(' · ' || new.end_reason, ''), '/moderation',
            case when new.end_kind = 'removed' then 'important' else 'normal' end);
  end if;
  return null;
end $$;
drop trigger if exists notify_membership on public.publisher_members;
create trigger notify_membership after insert or update on public.publisher_members
  for each row execute function public.notify_membership();

-- Reminders 14 and 3 days before a term ends, to the person and the
-- office managers. Runs once a day.
create or replace function public.remind_expiring_terms() returns void
language plpgsql security definer set search_path = public as $$
declare m record; office text;
begin
  for m in
    select * from public.publisher_members
    where revoked_at is null and expires_at > now()
      and ((expires_at <= now() + interval '14 days' and not reminded_14)
        or (expires_at <= now() + interval '3 days' and not reminded_3))
  loop
    select name into office from public.publishers where id = m.publisher_id;
    insert into public.notifications (user_id, kind, title, body, link)
    select distinct u, 'office',
           'Term ending soon: ' || m.position_title,
           office || ' · ends ' || to_char(m.expires_at at time zone 'Africa/Kampala', 'DD Mon YYYY') || '. Renew it in Office members if needed.',
           '/members'
    from (select m.user_id as u
          union
          select x.user_id from public.publisher_members x
          where x.publisher_id = m.publisher_id and x.revoked_at is null
            and now() between x.starts_at and x.expires_at and 'manage_members' = any (x.scopes)) t;
    update public.publisher_members
       set reminded_14 = true,
           reminded_3 = reminded_3 or expires_at <= now() + interval '3 days'
     where id = m.id;
  end loop;
end $$;

revoke execute on function public.members_term_rules() from public, anon, authenticated;
revoke execute on function public.notify_membership() from public, anon, authenticated;
revoke execute on function public.profiles_username_guard() from public, anon, authenticated;
revoke execute on function public.remind_expiring_terms() from public, anon, authenticated;
revoke execute on function public.make_username(text) from public, anon, authenticated;

-- Daily at 09:00 Kampala time (06:00 UTC).
create extension if not exists pg_cron;
do $$ begin
  perform cron.unschedule('campuslink-term-reminders');
exception when others then null; end $$;
select cron.schedule('campuslink-term-reminders', '0 6 * * *', 'select public.remind_expiring_terms()');
