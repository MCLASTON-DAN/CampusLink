import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/common.dart';

/// Super admin: which email addresses may join CampusLink.
///
/// - Institutions and their email types (e.g. students.cavendish.ac.ug).
/// - Exceptions: one named person allowed without a school email.
/// - The emergency switch, if the rule ever blocks real students by mistake.
///
/// The database only lets a super admin change these (see 0022_*.sql).
class EmailRulesAdminScreen extends StatefulWidget {
  const EmailRulesAdminScreen({super.key});
  @override
  State<EmailRulesAdminScreen> createState() => _EmailRulesAdminScreenState();
}

class _EmailRulesAdminScreenState extends State<EmailRulesAdminScreen> {
  SupabaseClient get _db => Supabase.instance.client;
  List<Map<String, dynamic>> _insts = [];
  List<Map<String, dynamic>> _domains = [];
  List<Map<String, dynamic>> _exceptions = [];
  bool _ruleOn = true;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        _db.from('institutions').select().order('name'),
        _db.from('institution_email_domains').select().order('domain'),
        _db.from('email_exceptions').select().order('created_at', ascending: false),
        _db.from('app_settings').select('value').eq('key', 'school_email_only').maybeSingle(),
      ]);
      setState(() {
        _insts = List<Map<String, dynamic>>.from(r[0] as List);
        _domains = List<Map<String, dynamic>>.from(r[1] as List);
        _exceptions = List<Map<String, dynamic>>.from(r[2] as List);
        _ruleOn = ((r[3] as Map?)?['value'] ?? 'on') != 'off';
        _error = null;
        _loading = false;
      });
    } catch (e) {
      setState(() => (_error = '$e', _loading = false));
    }
  }

  Future<void> _do(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (mounted) showSnack(context, ok);
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) showSnack(context, e.message.contains('duplicate') ? 'That already exists.' : e.message);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save. $e');
    }
  }

  Future<void> _toggleRule(bool on) async {
    if (!on) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Let any email join?'),
          content: const Text('Anyone with any email (Gmail, Yahoo…) could make an account and see student content. '
              'Only do this for a short emergency, then switch it back on.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Turn off rule')),
          ],
        ),
      );
      if (sure != true) return;
    }
    await _do(() => _db.from('app_settings').upsert({'key': 'school_email_only', 'value': on ? 'on' : 'off'}),
        on ? 'School emails only: ON' : 'Rule is OFF. Remember to switch it back on.');
  }

  Future<void> _addInstitution() async {
    final name = TextEditingController();
    final short = TextEditingController();
    var provider = 'none';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Add institution'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
            TextField(controller: short, decoration: const InputDecoration(labelText: 'Short name (e.g. CUU)')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: provider,
              decoration: const InputDecoration(labelText: 'Their email runs on'),
              items: const [
                DropdownMenuItem(value: 'google', child: Text('Google (Gmail for schools)')),
                DropdownMenuItem(value: 'microsoft', child: Text('Microsoft (Outlook / 365)')),
                DropdownMenuItem(value: 'none', child: Text("Something else / don't know")),
              ],
              onChanged: (v) => set(() => provider = v ?? 'none'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().length < 3) return;
    await _do(
        () => _db.from('institutions').insert({
              'name': name.text.trim(),
              'short_name': short.text.trim().isEmpty ? null : short.text.trim(),
              'calendar_provider': provider,
            }),
        'Institution added. Now add its email types.');
  }

  Future<void> _addDomain(Map<String, dynamic> inst) async {
    final domain = TextEditingController();
    final example = TextEditingController();
    final pattern = TextEditingController();
    var subs = false;
    var kind = 'student';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Email type for ${inst['short_name'] ?? inst['name']}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: domain,
                decoration: const InputDecoration(labelText: 'Part after @', hintText: 'students.cavendish.ac.ug'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: subs,
                onChanged: (v) => set(() => subs = v ?? false),
                title: const Text('Also accept sub-parts'),
                subtitle: Text('e.g. fst.${domain.text.isEmpty ? 'cavendish.ac.ug' : domain.text}'),
              ),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Who uses it'),
                items: const [
                  DropdownMenuItem(value: 'student', child: Text('Students')),
                  DropdownMenuItem(value: 'staff', child: Text('Staff and lecturers')),
                  DropdownMenuItem(value: 'any', child: Text('Anyone at the school')),
                ],
                onChanged: (v) => set(() => kind = v ?? 'student'),
              ),
              TextField(controller: example, decoration: const InputDecoration(labelText: 'Example address shown to users')),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Advanced: rule for the part before @'),
                children: [
                  TextField(
                    controller: pattern,
                    decoration: const InputDecoration(
                        labelText: 'Pattern (optional)',
                        hintText: r'^[a-z]{2}[0-9]{6}$',
                        helperText: r'^[a-z]{2}[0-9]{6}$ = 2 letters + 6 numbers, like xx123456',
                        helperMaxLines: 2),
                  ),
                ],
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true || domain.text.trim().isEmpty) return;
    await _do(
        () => _db.from('institution_email_domains').insert({
              'institution_id': inst['id'],
              'domain': domain.text.trim().toLowerCase().replaceAll('@', ''),
              'include_subdomains': subs,
              'account_kind': kind,
              'example': example.text.trim().isEmpty ? null : example.text.trim(),
              'local_part_pattern': pattern.text.trim().isEmpty ? null : pattern.text.trim(),
              'added_by': _db.auth.currentUser?.id,
            }),
        'Email type added.');
  }

  Future<void> _addException() async {
    final email = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Allow one person'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: email, decoration: const InputDecoration(labelText: 'Their email')),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Why (e.g. visiting lecturer)')),
          const SizedBox(height: 8),
          const Text('Allowed for 90 days. People who already have an account never need this.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Allow')),
        ],
      ),
    );
    if (ok != true) return;
    await _do(
        () => _db.from('email_exceptions').insert({
              'email': email.text.trim().toLowerCase(),
              'reason': reason.text.trim().isEmpty ? 'Allowed by super admin' : reason.text.trim(),
              'expires_at': DateTime.now().add(const Duration(days: 90)).toUtc().toIso8601String(),
              'added_by': _db.auth.currentUser?.id,
            }),
        'Allowed for 90 days.');
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Who can join')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addInstitution,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Institution'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: TextButton(onPressed: _load, child: Text('Could not load. Retry\n$_error')))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
                    Card(
                      color: _ruleOn ? null : Theme.of(context).colorScheme.errorContainer,
                      child: SwitchListTile(
                        title: const Text('School emails only'),
                        subtitle: Text(_ruleOn
                            ? 'New accounts need a school email from the list below.'
                            : 'OFF: any email can join right now.'),
                        value: _ruleOn,
                        onChanged: _toggleRule,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final i in _insts) ...[
                      Card(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          ListTile(
                            leading: const Icon(Icons.account_balance_rounded),
                            title: Text('${i['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(i['calendar_provider'] == 'google'
                                ? 'Email by Google: students can add CampusLink to Google Calendar'
                                : i['calendar_provider'] == 'microsoft'
                                    ? 'Email by Microsoft'
                                    : 'Email provider not set'),
                            trailing: Switch(
                              value: i['is_active'] == true,
                              onChanged: (v) => _do(() => _db.from('institutions').update({'is_active': v}).eq('id', i['id']),
                                  v ? 'Institution on' : 'Institution off: its emails can no longer join'),
                            ),
                          ),
                          for (final d in _domains.where((d) => d['institution_id'] == i['id']))
                            ListTile(
                              dense: true,
                              leading: Icon(Icons.alternate_email, color: d['is_active'] == true ? null : muted),
                              title: Text('…@${d['domain']}${d['include_subdomains'] == true ? '  (+ sub-parts)' : ''}'),
                              subtitle: Text([
                                d['account_kind'] == 'student' ? 'Students' : d['account_kind'] == 'staff' ? 'Staff' : 'Anyone',
                                if (d['example'] != null) 'e.g. ${d['example']}',
                                if (d['local_part_pattern'] != null) 'rule ${d['local_part_pattern']}',
                              ].join(' · ')),
                              trailing: PopupMenuButton<String>(
                                onSelected: (a) => a == 'toggle'
                                    ? _do(
                                        () => _db
                                            .from('institution_email_domains')
                                            .update({'is_active': d['is_active'] != true}).eq('id', d['id']),
                                        'Updated')
                                    : _do(() => _db.from('institution_email_domains').delete().eq('id', d['id']), 'Removed'),
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: 'toggle', child: Text(d['is_active'] == true ? 'Pause' : 'Turn on')),
                                  const PopupMenuItem(value: 'delete', child: Text('Remove')),
                                ],
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                                onPressed: () => _addDomain(i), icon: const Icon(Icons.add), label: const Text('Add email type')),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: Text('Exceptions', style: Theme.of(context).textTheme.titleMedium)),
                      TextButton.icon(onPressed: _addException, icon: const Icon(Icons.person_add_alt), label: const Text('Allow one person')),
                    ]),
                    if (_exceptions.isEmpty)
                      Text('None. Existing accounts (even Gmail ones) keep working without an exception.', style: TextStyle(color: muted)),
                    for (final x in _exceptions)
                      Card(
                        child: ListTile(
                          title: Text('${x['email']}'),
                          subtitle: Text('${x['reason']}${x['expires_at'] != null ? ' · until ${'${x['expires_at']}'.substring(0, 10)}' : ''}'),
                          trailing: IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _do(() => _db.from('email_exceptions').delete().eq('email', x['email']), 'Removed'),
                          ),
                        ),
                      ),
                  ]),
                ),
    );
  }
}
