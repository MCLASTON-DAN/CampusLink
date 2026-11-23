-- CampusLink 0005: newsroom badge, profile photo + status, post views,
-- tutor rules, tutor levels and tutor reports.

-- ---------------------------------------------------------------------
-- A. Newsroom (press team): purple badge, at most 5 active members.
-- ---------------------------------------------------------------------
alter table public.publishers drop constraint if exists publishers_kind_check;
alter table public.publishers
  add constraint publishers_kind_check check (kind in ('administration','guild','press','club'));

insert into public.publishers (kind, name)
values ('press', 'Cavendish Campus Newsroom')
on conflict (name) do nothing;

create or replace function public.press_team_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select kind from public.publishers where id = new.publisher_id) = 'press'
     and new.revoked_at is null
     and (select count(*) from public.publisher_members m
           where m.publisher_id = new.publisher_id and m.revoked_at is null
             and now() between m.starts_at and m.expires_at
             and m.id <> new.id) >= 5 then
    raise exception 'The newsroom already has 5 active members. End someone''s term first.';
  end if;
  return new;
end $$;
drop trigger if exists press_team_limit on public.publisher_members;
create trigger press_team_limit before insert or update on public.publisher_members
  for each row execute function public.press_team_limit();

-- ---------------------------------------------------------------------
-- B. Profile photo and a short status that ends by itself.
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists avatar_path text check (avatar_path is null or char_length(avatar_path) <= 200),
  add column if not exists status_text text check (status_text is null or char_length(status_text) <= 80),
  add column if not exists status_until timestamptz;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 307200, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- Each person may only write inside their own folder: avatars/<their id>/...
drop policy if exists "own avatar upload" on storage.objects;
create policy "own avatar upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "own avatar change" on storage.objects;
create policy "own avatar change" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "own avatar delete" on storage.objects;
create policy "own avatar delete" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_super_admin()));

-- Public face of a person, now with photo, live status and the new badges.
-- red = administration (and super admins), green = guild, purple = newsroom,
-- blue = verified tutor. Office badges vanish when the term ends.
drop view if exists public.public_profiles;
create view public.public_profiles with (security_invoker = true) as
select p.id, p.full_name, p.programme, p.year_of_study, p.faculty,
       p.is_tutor, p.tutor_subjects, p.is_buddy_mentor, p.tutor_verified,
       p.avatar_path,
       case when p.status_until is null or p.status_until > now() then p.status_text end as status_text,
       case when p.status_until > now() then p.status_until end as status_until,
       o.position_title as office_title, o.office_name,
       case when p.role = 'super_admin' or o.kind = 'administration' then 'red'
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
  limit 1) o on true;
grant select on public.public_profiles to authenticated;

-- ---------------------------------------------------------------------
-- C. Post views: counted once per person; only the posting office,
--    staff and super admins can see the number.
-- ---------------------------------------------------------------------
create table if not exists public.post_views (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.post_views enable row level security;
-- No direct reads or writes: only through the two functions below.
revoke all on public.post_views from anon, authenticated;

create or replace function public.record_post_view(p_post uuid) returns void
language sql security definer set search_path = public as $$
  insert into public.post_views (post_id, user_id) values (p_post, auth.uid())
  on conflict do nothing;
$$;

create or replace function public.post_view_count(p_post uuid) returns int
language sql stable security definer set search_path = public as $$
  select case
    when public.is_staff() or public.is_super_admin()
      or exists (select 1 from public.posts p where p.id = p_post
                   and (p.author_id = auth.uid() or public.can_publish(p.publisher_id, 'news')
                        or public.can_publish(p.publisher_id, 'notices')))
    then (select count(*)::int from public.post_views where post_id = p_post)
  end;
$$;
revoke execute on function public.record_post_view(uuid) from public, anon;
revoke execute on function public.post_view_count(uuid) from public, anon;
grant execute on function public.record_post_view(uuid) to authenticated;
grant execute on function public.post_view_count(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- D. Tutor rules: a real bio, a grade for each module, and not in first year.
-- ---------------------------------------------------------------------
create or replace function public.tutor_module_rules() returns trigger
language plpgsql security definer set search_path = public as $$
declare yr int; rl text; bio text;
begin
  select year_of_study, role into yr, rl from public.profiles where id = new.tutor_id;
  select tp.bio into bio from public.tutor_profiles tp where tp.tutor_id = new.tutor_id;
  if rl not in ('staff','admin','super_admin') and coalesce(yr, 1) < 2 then
    raise exception 'Tutors must be in year 2 or above (set your year in your profile).';
  end if;
  if char_length(coalesce(bio, '')) < 40 then
    raise exception 'Write a tutor bio of at least 40 characters first.';
  end if;
  if char_length(coalesce(trim(new.grade_achieved), '')) = 0 then
    raise exception 'Add the grade you got in % so students can trust you.', new.course_code;
  end if;
  return new;
end $$;
drop trigger if exists tutor_module_rules on public.tutor_modules;
create trigger tutor_module_rules before insert or update on public.tutor_modules
  for each row execute function public.tutor_module_rules();

-- ---------------------------------------------------------------------
-- E. Tutor reports: only students who had a lesson with the tutor may report.
-- ---------------------------------------------------------------------
create table if not exists public.tutor_reports (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid not null references public.profiles(id) on delete cascade,
  reporter_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  reason text not null check (reason in
    ('no_show','unprofessional','poor_teaching','overcharging','harassment','other')),
  details text not null check (char_length(details) between 10 and 600),
  status text not null default 'open' check (status in ('open','upheld','dismissed')),
  handled_by uuid references public.profiles(id),
  handled_at timestamptz,
  created_at timestamptz not null default now(),
  check (tutor_id <> reporter_id)
);
create unique index if not exists tutor_reports_one_open
  on public.tutor_reports (tutor_id, reporter_id) where status = 'open';
alter table public.tutor_reports enable row level security;

drop policy if exists "report a tutor you had" on public.tutor_reports;
create policy "report a tutor you had" on public.tutor_reports for insert to authenticated
  with check (reporter_id = auth.uid() and exists (
    select 1 from public.tutor_requests r
    where r.tutor_id = tutor_reports.tutor_id and r.student_id = auth.uid()
      and r.status in ('accepted','completed')));
drop policy if exists "see own or staff" on public.tutor_reports;
create policy "see own or staff" on public.tutor_reports for select to authenticated
  using (reporter_id = auth.uid() or public.is_staff() or public.is_super_admin());
drop policy if exists "staff handle" on public.tutor_reports;
create policy "staff handle" on public.tutor_reports for update to authenticated
  using (public.is_staff() or public.is_super_admin())
  with check (public.is_staff() or public.is_super_admin());
grant select, insert on public.tutor_reports to authenticated;
grant update (status, handled_by, handled_at) on public.tutor_reports to authenticated;

-- Per tutor, per reason: how many reports and what share. Staff only.
create or replace function public.tutor_report_summary()
returns table (tutor_id uuid, tutor_name text, reason text, n int, pct numeric,
               total int, reporters int, open_reports int)
language sql stable security definer set search_path = public as $$
  with r as (select * from public.tutor_reports
             where public.is_staff() or public.is_super_admin())
  select r.tutor_id, p.full_name, r.reason, count(*)::int,
         round(100.0 * count(*) / sum(count(*)) over (partition by r.tutor_id), 1),
         (sum(count(*)) over (partition by r.tutor_id))::int,
         (select count(distinct x.reporter_id)::int from r x where x.tutor_id = r.tutor_id),
         (select count(*)::int from r x where x.tutor_id = r.tutor_id and x.status = 'open')
  from r join public.profiles p on p.id = r.tutor_id
  group by r.tutor_id, p.full_name, r.reason
  order by 6 desc, 4 desc;
$$;
revoke execute on function public.tutor_report_summary() from public, anon;
grant execute on function public.tutor_report_summary() to authenticated;

-- ---------------------------------------------------------------------
-- F. Tutor stats: lessons taught (for levels) and a pause flag.
--    A tutor is paused from the list while 3+ different students have
--    open reports, until staff review them.
-- ---------------------------------------------------------------------
create or replace function public.tutor_stats()
returns table (tutor_id uuid, lessons int, paused boolean)
language sql stable security definer set search_path = public as $$
  select p.id,
         (select count(*)::int from public.tutor_requests r
           where r.tutor_id = p.id and r.status = 'completed'),
         (select count(distinct t.reporter_id) >= 3 from public.tutor_reports t
           where t.tutor_id = p.id and t.status = 'open')
  from public.profiles p
  where p.is_tutor;
$$;
revoke execute on function public.tutor_stats() from public, anon;
grant execute on function public.tutor_stats() to authenticated;

-- Trigger helpers are never called directly.
revoke execute on function public.press_team_limit() from public, anon, authenticated;
revoke execute on function public.tutor_module_rules() from public, anon, authenticated;
