-- CampusLink 0009: fixes from the platform-wide bug hunt.

-- 1. Staff could see reports but never close them.
drop policy if exists "staff handle reports" on public.reports;
create policy "staff handle reports" on public.reports for update to authenticated
  using (public.is_staff()) with check (public.is_staff());
grant update (status, handled_by, handled_at) on public.reports to authenticated;

-- 2. Profiles: a person could reset username_changed_at to skip the 30-day
--    rule, or point their photo at any picture on the internet.
create or replace function public.protect_profile_columns() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if current_user in ('authenticated','anon') then
    if new.role is distinct from old.role
       or new.tutor_verified is distinct from old.tutor_verified
       or new.tutor_verified_at is distinct from old.tutor_verified_at
       or new.created_at is distinct from old.created_at
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
revoke execute on function public.protect_profile_columns() from public, anon, authenticated;

-- 3. Posts: who wrote it, for which office, and when, can never be edited.
create or replace function public.posts_lock_identity() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if current_user in ('authenticated','anon') and (
       new.author_id is distinct from old.author_id
    or new.author_position is distinct from old.author_position
    or new.publisher_id is distinct from old.publisher_id
    or new.published_at is distinct from old.published_at
    or new.created_at is distinct from old.created_at
    or new.pledge_accepted_at is distinct from old.pledge_accepted_at) then
    raise exception 'The author, office and date of a post cannot be changed' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists posts_lock_identity on public.posts;
create trigger posts_lock_identity before update on public.posts
  for each row execute function public.posts_lock_identity();
revoke execute on function public.posts_lock_identity() from public, anon, authenticated;

-- 4. Speed: index every foreign key that has no index.
do $$
declare r record;
begin
  for r in
    select c.conrelid::regclass as tbl, c.conname,
           string_agg(quote_ident(a.attname), ', ' order by k.ord) as cols
    from pg_constraint c
    join lateral unnest(c.conkey) with ordinality k(attnum, ord) on true
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
    where c.contype = 'f' and c.connamespace = 'public'::regnamespace
      and not exists (
        select 1 from pg_index i
        where i.indrelid = c.conrelid
          and (i.indkey::text || ' ') like array_to_string(c.conkey, ' ') || ' %')
    group by c.conrelid, c.conname
  loop
    execute format('create index if not exists %I on %s (%s)', left('fk_' || r.conname, 63), r.tbl, r.cols);
  end loop;
end $$;

-- 5. Speed: work out "who is signed in" once per query, not once per row.
do $$
declare p record; q text; c text; stmt text;
begin
  for p in select * from pg_policies where schemaname = 'public' loop
    q := p.qual; c := p.with_check;
    if (q is not null and q like '%auth.uid()%' and q not like '%SELECT auth.uid()%')
       or (c is not null and c like '%auth.uid()%' and c not like '%SELECT auth.uid()%') then
      stmt := format('alter policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
      if q is not null then stmt := stmt || ' using (' || replace(q, 'auth.uid()', '(select auth.uid())') || ')'; end if;
      if c is not null then stmt := stmt || ' with check (' || replace(c, 'auth.uid()', '(select auth.uid())') || ')'; end if;
      execute stmt;
    end if;
  end loop;
end $$;
