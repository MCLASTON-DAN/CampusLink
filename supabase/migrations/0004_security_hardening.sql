-- CampusLink 0004: security hardening (from the Supabase security advisor).
-- Views follow the caller's rules; signed-out users can call nothing;
-- trigger helpers cannot be called directly. Safe to re-run.
alter view public.pulse_results set (security_invoker = true);
alter view public.public_profiles set (security_invoker = true);
alter view public.content_stats set (security_invoker = true);
alter view public.tutor_scores set (security_invoker = true);

alter function public.protect_profile_columns() set search_path = public;
alter function public.max_term() set search_path = public;
alter function public.scope_for_kind(text) set search_path = public;
alter function public.events_guard_major() set search_path = public;
alter function public.survey_questions_limit() set search_path = public;
alter function public.tutor_requests_transition() set search_path = public;
alter function public.help_offices_stamp() set search_path = public;

revoke execute on all functions in schema public from public, anon;
revoke execute on function public.handle_new_user() from authenticated;
revoke execute on function public.comments_rate_limit() from authenticated;
revoke execute on function public.posts_before_insert() from authenticated;
revoke execute on function public.posts_keep_revision() from authenticated;
revoke execute on function public.tutor_reviews_after() from authenticated;
revoke execute on function public.recompute_tutor_verification(uuid) from authenticated;

grant execute on function public.is_staff() to authenticated;
grant execute on function public.is_super_admin() to authenticated;
grant execute on function public.can_publish(uuid, text) to authenticated;
grant execute on function public.is_active_publisher() to authenticated;
grant execute on function public.scope_for_kind(text) to authenticated;
grant execute on function public.max_term() to authenticated;
grant execute on function public.set_user_role(uuid, text) to authenticated;
grant execute on function public.moderate(text, text, uuid, text) to authenticated;
grant execute on function public.submit_survey(uuid, jsonb) to authenticated;
grant execute on function public.survey_results(uuid) to authenticated;
grant execute on function public.tutor_score(uuid, text) to authenticated;
grant execute on all functions in schema public to service_role;

alter default privileges in schema public revoke execute on functions from public, anon;
