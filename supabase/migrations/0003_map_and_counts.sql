-- =====================================================================
-- CampusLink 0003: office coordinates for the map + cheap like/comment counts
-- Run AFTER 0002. Safe to re-run.
-- =====================================================================

-- Where an office is on the map. Left empty until the administration enters
-- the real location (we never guess coordinates).
alter table public.help_offices
  add column if not exists lat double precision,
  add column if not exists lng double precision;

-- Counts for a page of posts/events without downloading every comment.
-- Ask it with: .from('content_stats').select().inFilter('target_id', ids)
create or replace view public.content_stats as
select 'post'::text as target_type, p.id as target_id,
       (select count(*) from public.reactions r
         where r.target_type = 'post' and r.target_id = p.id) as likes,
       (select count(*) from public.comments c
         where c.target_type = 'post' and c.target_id = p.id and c.status = 'visible') as comments
from public.posts p
union all
select 'event'::text, e.id,
       (select count(*) from public.reactions r
         where r.target_type = 'event' and r.target_id = e.id),
       (select count(*) from public.comments c
         where c.target_type = 'event' and c.target_id = e.id and c.status = 'visible')
from public.events e;

grant select on public.content_stats to authenticated;
grant select, update on public.help_offices to authenticated;

-- Staff keep office details accurate. Every change stamps who and when.
alter table public.help_offices
  add column if not exists verified_by uuid references public.profiles(id);

create or replace function public.help_offices_stamp() returns trigger
language plpgsql as $$
begin
  if current_user in ('authenticated','anon') and (
       new.what_we_do is distinct from old.what_we_do
    or new.what_we_dont is distinct from old.what_we_dont
    or new.bring is distinct from old.bring
    or new.hours is distinct from old.hours
    or new.directions is distinct from old.directions
    or new.open_hours is distinct from old.open_hours
    or new.lat is distinct from old.lat or new.lng is distinct from old.lng) then
    if coalesce(char_length(new.source), 0) < 5 then
      raise exception 'Say where this information comes from (document or person) in "source"';
    end if;
    new.last_verified_at := now();
    new.verified_by := auth.uid();
  end if;
  return new;
end $$;
drop trigger if exists help_offices_stamp on public.help_offices;
create trigger help_offices_stamp before update on public.help_offices
  for each row execute function public.help_offices_stamp();

-- Tutor scores for a whole list in one go (same maths as tutor_score()).
create or replace view public.tutor_scores as
with g as (
  select (coalesce(sum(rating), 0) + 4.0 * 50) / (count(*) + 50) as c from public.tutor_reviews)
select r.tutor_id,
       count(*)::int as reviews,
       count(distinct r.student_id)::int as reviewers,
       round(((g.c * 5 + sum(r.rating)) / (5 + count(*)))::numeric, 2) as score
from public.tutor_reviews r, g
group by r.tutor_id, g.c;
grant select on public.tutor_scores to authenticated;
