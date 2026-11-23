// Privacy policy, terms of use and posting code shown in the app.
//
// IMPORTANT: written to follow Uganda's Data Protection and Privacy Act, 2019
// and its 2021 Regulations, but it is not legal advice. Have the university's
// legal office (or a lawyer) review it before the official launch, and fill in
// the contact details marked below. Raise [kPolicyVersion] whenever the text
// changes: everyone is then asked to accept the new version.

const kPolicyVersion = '2026-11-v1';
const kPolicyEffective = '23 November 2026';

/// Who to contact about data. Change these when the university confirms them.
const kDataContactEmail = 'privacy@campuslink.app';
const kOperator = 'the CampusLink team, for students and staff of Cavendish University Uganda';

class PolicySection {
  const PolicySection(this.heading, this.body);
  final String heading;
  final String body;
}

class PolicyDoc {
  const PolicyDoc(this.key, this.title, this.summary, this.sections);
  final String key;
  final String title;
  final String summary;
  final List<PolicySection> sections;
}

const privacyPolicy = PolicyDoc('privacy', 'Privacy Policy',
    'What we collect, why, who can see it, how long we keep it and your rights.', [
  PolicySection('1. Who we are',
      'CampusLink is run by $kOperator. For this policy we are the "data controller": we decide why and how your '
          'personal data is used. Contact: $kDataContactEmail.'),
  PolicySection('2. What we collect',
      '• Account: your name, email address and Google account picture if you sign in with Google.\n'
          '• Profile (you choose): student number, programme, year, faculty, profile photo and a short status.\n'
          '• Timetable: the classes you import or add. Only you can see your timetable.\n'
          '• What you do in the app: comments, likes, survey answers, help requests, tutor requests and reviews, '
          'reports you file, and which posts you opened (to count views).\n'
          '• Device: notification settings and basic technical logs needed to keep the service safe.\n'
          'We do not collect your location, contacts, messages outside the app, or payment card details.'),
  PolicySection('3. Why we use it (lawful basis)',
      '• To run the service you signed up for: your account, timetable, requests and tutoring.\n'
          '• With your consent: notifications, profile photo, status and optional profile fields. You can withdraw '
          'consent at any time in the app.\n'
          '• To keep the community safe: moderation, reports and a public log of removed content.\n'
          '• To meet legal duties under the laws of Uganda.'),
  PolicySection('4. Who can see what',
      '• Everyone signed in: your name, programme, year, photo, status, badge, and your comments and reviews.\n'
          '• Only you: your timetable, help requests, survey answers and notification settings.\n'
          '• Survey answers are anonymous. Results appear only after at least 5 people answer.\n'
          '• Post view counts are visible only to the office that posted and to administrators, never to other students.\n'
          '• Staff handling a help request or a report can see what is needed to deal with it.\n'
          '• Administrators can see that a report exists and its reason, not your private data unrelated to it.'),
  PolicySection('5. Where it is stored and how it is protected',
      'Data is stored with our cloud database provider (Supabase), which may keep it on servers outside Uganda, '
          'such as in the European Union. We only use providers that protect data to a standard at least as strong '
          'as Ugandan law requires. Every table is protected by access rules, so each person only reaches what they '
          'are allowed to see. Connections are encrypted (HTTPS). Pictures are resized and kept small.'),
  PolicySection('6. How long we keep it',
      '• Your account: while it is active. If you delete it, your profile, timetable and private data are erased '
          'within 30 days.\n'
          '• Comments and reviews you posted are removed or anonymised when you delete your account.\n'
          '• Moderation records: kept for up to 2 years to keep the platform fair and accountable.\n'
          '• Backups are overwritten on a rolling basis.'),
  PolicySection('7. Your rights',
      'Under the Data Protection and Privacy Act, 2019 you can: ask what data we hold about you and get a copy; '
          'correct wrong data; ask us to delete it; object to its use; and withdraw consent. Email $kDataContactEmail. '
          'We answer within 30 days. If you are not happy with our answer, you can complain to the Personal Data '
          'Protection Office (PDPO) of Uganda.'),
  PolicySection('8. Children',
      'CampusLink is for university students and staff. If you are under 18, use it only with the permission of a '
          'parent or guardian.'),
  PolicySection('9. Changes',
      'If we change this policy, we raise its version and ask you to read and accept it again before you continue.'),
]);

const termsOfUse = PolicyDoc('terms', 'Terms of Use',
    'The rules everyone agrees to when using CampusLink.', [
  PolicySection('1. Using CampusLink',
      'CampusLink helps Cavendish University Uganda students and staff find information, get help, study and take '
          'part in campus life. Use your real name and keep your account to yourself.'),
  PolicySection('2. Respect',
      'Do not post or send insults, threats, hate, harassment, sexual content, private details of others, spam, '
          'or anything illegal. Do not pretend to be another person or office.'),
  PolicySection('3. Official posts and badges',
      'Only verified offices can publish news, events and notices. Badges show a real role: red for '
          'Administration, green for the Guild (while in office), purple for the Campus Newsroom, orange for '
          'lecturers, blue for tutors who earned it through real reviews. Badges cannot be bought.'),
  PolicySection('4. Tutoring',
      'Tutors are students or staff offering help. CampusLink does not employ them and is not part of any payment '
          'between you. Report any tutor who behaves badly. Reviews must be honest and only follow a real lesson.'),
  PolicySection('5. Sharing content',
      'You may share CampusLink posts using the Share button, which sends a short preview and a link. Do not copy '
          'whole articles or pictures to other sites without permission from the office that posted them.'),
  PolicySection('6. Moderation',
      'Content that breaks these rules may be removed. Every removal is recorded with a public reason. Offices can '
          'manage comments on their own posts; administrators step in only for clear rule-breaking.'),
  PolicySection('7. Your content',
      'You keep ownership of what you post. You allow CampusLink to show it inside the platform. You are '
          'responsible for what you post.'),
  PolicySection('8. Limits',
      'We work hard to keep information correct, but always confirm important details (fees, deadlines, exams) '
          'with the official office. The service may sometimes be unavailable.'),
  PolicySection('9. Ending your account',
      'You can stop using CampusLink at any time. We may suspend accounts that seriously or repeatedly break these '
          'terms.'),
  PolicySection('10. Law',
      'These terms follow the laws of the Republic of Uganda.'),
]);

const postingCode = PolicyDoc('posting_code', 'Posting Code',
    'Rules for offices that publish news, events and notices.', [
  PolicySection('Who can post',
      'Only verified offices: Administration, the Guild while in office, the Campus Newsroom (at most 5 members) '
          'and lecturers for their own course units.'),
  PolicySection('Rules',
      '• Post only what you can prove, and say where it comes from.\n'
          '• No insults, threats, hate or private details.\n'
          '• Corrections are welcome: use a "Clarification" post.\n'
          '• Edits are kept in history. Removed posts are hidden, not deleted, and the reason is public.\n'
          '• Official posts can only be removed by the super admin, with a public reason.'),
]);

const allPolicies = {'privacy': privacyPolicy, 'terms': termsOfUse, 'posting_code': postingCode};
