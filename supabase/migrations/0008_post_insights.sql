-- CampusLink 0008: view details for posting offices and admins.
-- Each person who opens a post counts once. Only the office that posted it
-- (and staff / super admin) can see these numbers.
create index if not exists post_views_time on public.post_views (post_id, viewed_at);

create or replace function public.post_insights(p_days int default 90)
returns table (post_id uuid, title text, publisher_name text, published_at timestamptz,
               views int, views_24h int, views_7d int, comments int, likes int)
language sql stable security definer set search_path = public as $$
  select p.id, p.title, pb.name, p.published_at,
         (select count(*)::int from public.post_views v where v.post_id = p.id),
         (select count(*)::int from public.post_views v where v.post_id = p.id and v.viewed_at > now() - interval '24 hours'),
         (select count(*)::int from public.post_views v where v.post_id = p.id and v.viewed_at > now() - interval '7 days'),
         (select count(*)::int from public.comments c where c.target_type = 'post' and c.target_id = p.id and c.status = 'visible'),
         (select count(*)::int from public.reactions r where r.target_type = 'post' and r.target_id = p.id)
  from public.posts p
  join public.publishers pb on pb.id = p.publisher_id
  where p.status = 'published'
    and p.published_at > now() - make_interval(days => least(greatest(coalesce(p_days, 90), 1), 365))
    and (public.is_staff() or public.is_super_admin() or p.author_id = auth.uid()
         or public.can_publish(p.publisher_id, 'news') or public.can_publish(p.publisher_id, 'notices'))
  order by p.published_at desc
  limit 200;
$$;
revoke execute on function public.post_insights(int) from public, anon;
grant execute on function public.post_insights(int) to authenticated;
