import 'package:flutter/material.dart';

const kPolicyVersion = '2026-11-draft';

const _policies = <String, (String, String)>{
  'posting_code': (
    'Posting code',
    'Who can post: only verified offices (Administration, Guild members while in office).\n\n'
        'Rules:\n• Post only what you can prove. Say where it comes from.\n'
        '• No insults, threats, hate or private details.\n'
        '• Corrections are welcome. Use a "Clarification" post.\n'
        '• Edits are kept in history. Removed posts are hidden, not deleted, and the reason is public.\n'
        '• Official posts can only be removed by the super admin, with a public reason.\n\n'
        'DRAFT. Must be reviewed by the university and a lawyer before launch.'
  ),
  'privacy': (
    'Privacy notice',
    'We keep your name, student number, programme and what you post. Comments show your real name. '
        'Survey answers are anonymous and results show only after 5 answers. '
        'We follow the Data Protection and Privacy Act, 2019 (Uganda). Ask the administration to see or fix your data.\n\n'
        'DRAFT. A lawyer must review this before launch.'
  ),
};

Future<void> showPolicy(BuildContext context, String key) {
  final p = _policies[key]!;
  return showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(p.$1),
      content: SingleChildScrollView(child: Text(p.$2)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ),
  );
}
