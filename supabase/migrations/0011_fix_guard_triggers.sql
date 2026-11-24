-- CampusLink 0011: SECURITY FIX.
-- These guards ask "is a normal app user doing this?" (current_user =
-- 'authenticated'). Inside a SECURITY DEFINER function current_user is the
-- function owner, so the guards never fired. Run them as the caller instead.
alter function public.protect_profile_columns() security invoker;
alter function public.profiles_username_guard() security invoker;
alter function public.posts_lock_identity() security invoker;
-- The username guard needs these helpers when run as the caller.
grant execute on function public.make_username(text) to authenticated;
grant execute on function public.username_reserved(text) to authenticated;
