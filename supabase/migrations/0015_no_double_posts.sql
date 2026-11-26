-- 0015: the database skips an exact repeat sent within 10 seconds.
-- Same person + same place + same words = a double tap, not a new message.
-- Protects everyone, even people still on an older version of the app.
-- Safe to run more than once.

create or replace function public.skip_double_comment() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if exists (select 1 from public.comments c
             where c.author_id = new.author_id and c.target_type = new.target_type
               and c.target_id = new.target_id and c.body = new.body
               and c.created_at > now() - interval '10 seconds') then
    return null;  -- skip the copy quietly
  end if;
  return new;
end $$;
drop trigger if exists skip_double_comment on public.comments;
create trigger skip_double_comment before insert on public.comments
  for each row execute function public.skip_double_comment();

create or replace function public.skip_double_request_update() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if exists (select 1 from public.help_request_updates u
             where u.request_id = new.request_id and u.author_id is not distinct from new.author_id
               and u.message = new.message and u.new_status is not distinct from new.new_status
               and u.created_at > now() - interval '10 seconds') then
    return null;
  end if;
  return new;
end $$;
drop trigger if exists skip_double_request_update on public.help_request_updates;
create trigger skip_double_request_update before insert on public.help_request_updates
  for each row execute function public.skip_double_request_update();

create index if not exists comments_author_recent on public.comments (author_id, created_at desc);
create index if not exists request_updates_recent on public.help_request_updates (request_id, created_at desc);
