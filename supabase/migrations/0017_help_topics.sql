-- 0017: help topics. Each office lists the problems it handles; a request
-- picks one (or "Other"), so similar problems group together and an office
-- can answer all of them at once. Safe to run more than once.

alter table public.help_offices add column if not exists topics text[] not null default '{}';
alter table public.help_requests add column if not exists topic text;
alter table public.help_requests drop constraint if exists help_requests_topic_len;
alter table public.help_requests add constraint help_requests_topic_len check (topic is null or char_length(topic) between 2 and 60);
create index if not exists help_requests_office_topic on public.help_requests (office_id, topic, status);

-- A request's topic must be one of its office's topics, or "Other".
create or replace function public.help_request_topic_check() returns trigger
language plpgsql security invoker set search_path = public as $$
declare t text[];
begin
  if new.topic is null or new.topic = 'Other' then return new; end if;
  select topics into t from public.help_offices where id = new.office_id;
  if t is null or not (new.topic = any (t)) then
    new.topic := 'Other';   -- office changed or topic removed: keep it, as Other
  end if;
  return new;
end $$;
drop trigger if exists help_request_topic_check on public.help_requests;
create trigger help_request_topic_check before insert or update of topic, office_id on public.help_requests
  for each row execute function public.help_request_topic_check();

-- Starter topics, only for offices that have none yet. Offices can edit them.
update public.help_offices set topics = v.t
from (values
  ('Registrar', array['Registration','Add or drop a unit','Transcript','Student ID card','Admission letter','Deferment']),
  ('Finance', array['Fee statement','Payment not showing','Payment plan','Bursary or scholarship','Refund']),
  ('ICT', array['Portal login','Student email','Wi-Fi','E-learning','Lab computer']),
  ('Library', array['Borrowing','E-resources login','Fines','Printing','Study room']),
  ('Dean of Students', array['Accommodation','Welfare','Clubs and societies','Discipline','Complaint about a service']),
  ('Counselling', array['Talk to a counsellor','Stress or exams','Personal matter']),
  ('Faculty', array['Timetable clash','Course advising','Missing marks','Lecturer not attending','Exam query']),
  ('Examinations', array['Exam card','Missing marks','Remark request','Retake','Results not showing']),
  ('Careers', array['CV review','Internship placement','Recommendation letter'])
) as v(k, t)
where public.help_offices.name ilike '%' || v.k || '%' and cardinality(public.help_offices.topics) = 0;

-- Answer every open request on one topic at once (e.g. "Missing marks for
-- BDA2207 are now uploaded"). Only whoever handles that office.
create or replace function public.reply_to_topic(p_office uuid, p_topic text, p_message text, p_status text default null)
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  if not public.can_handle_request(p_office) then raise exception 'You do not handle this office.'; end if;
  if char_length(trim(coalesce(p_message, ''))) < 3 then raise exception 'Write a short reply.'; end if;
  if p_status is not null and p_status not in ('open', 'in_progress', 'resolved', 'closed') then
    raise exception 'Unknown status.';
  end if;
  for r in select id, student_id, title from public.help_requests
           where office_id is not distinct from p_office and topic = p_topic and status in ('open', 'in_progress')
  loop
    if p_status is not null then
      update public.help_requests set status = p_status, updated_at = now() where id = r.id;
    else
      update public.help_requests set updated_at = now() where id = r.id;
      insert into public.notifications (user_id, kind, title, body, link)
      values (r.student_id, 'request', 'Reply about: ' || r.title, left(trim(p_message), 200), '/requests/' || r.id);
    end if;
    insert into public.help_request_updates (request_id, author_id, message, new_status)
    values (r.id, (select auth.uid()), trim(p_message), p_status);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function public.reply_to_topic(uuid, text, text, text) from public, anon;
grant execute on function public.reply_to_topic(uuid, text, text, text) to authenticated;
