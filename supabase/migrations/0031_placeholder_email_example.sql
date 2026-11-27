-- 0031: the example school address shown to users is a made-up one, never a
-- real student's (same format: 2 letters + 6 numbers).
update public.institution_email_domains
set example = 'xx123456@students.cavendish.ac.ug'
where domain = 'students.cavendish.ac.ug' and example is distinct from 'xx123456@students.cavendish.ac.ug';
