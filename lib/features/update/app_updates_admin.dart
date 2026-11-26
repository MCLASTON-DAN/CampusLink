import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../widgets/common.dart';
import 'app_update.dart';

/// Super admin: make an Android version required.
///
/// Sets app_settings.android_min_build / android_min_build_from. The app
/// shows a warning until that date, then a full-screen "Update" page, and the
/// database refuses older apps (0025_app_update_gate.sql).
class AppUpdatesAdminScreen extends StatefulWidget {
  const AppUpdatesAdminScreen({super.key});
  @override
  State<AppUpdatesAdminScreen> createState() => _AppUpdatesAdminScreenState();
}

class _AppUpdatesAdminScreenState extends State<AppUpdatesAdminScreen> {
  SupabaseClient get _db => Supabase.instance.client;
  AppRelease? _latest;
  int _min = 0;
  DateTime? _from;
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
      final url = AppConfig.androidApkUrl.replaceFirst('campuslink.apk', 'version.json');
      final r = await http.get(Uri.parse('$url?t=${DateTime.now().millisecondsSinceEpoch}'));
      final p = Map<String, dynamic>.from(await _db.rpc('app_update_policy') as Map);
      setState(() {
        _latest = r.statusCode == 200 ? AppRelease.fromMap(jsonDecode(r.body) as Map<String, dynamic>) : null;
        _min = (p['min_build'] as num?)?.toInt() ?? 0;
        _from = p['required_from'] == null ? null : DateTime.tryParse('${p['required_from']}')?.toLocal();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() => (_loading = false, _error = '$e'));
    }
  }

  Future<void> _set(int build, DateTime? from) async {
    try {
      await _db.from('app_settings').upsert([
        {'key': 'android_min_build', 'value': '$build'},
        {'key': 'android_min_build_from', 'value': from?.toUtc().toIso8601String() ?? ''},
      ]);
      if (mounted) showSnack(context, build == 0 ? 'No update is required now.' : 'Saved.');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save: $e');
    }
  }

  Future<void> _require() async {
    final latest = _latest;
    if (latest == null) return;
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Require version ${latest.version}?'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Everyone gets a warning first. When the time is up, older apps show only the '
                'Update page and the database stops serving them.'),
          ),
          for (final d in const [3, 7, 1, 0])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Text(d == 0 ? 'Right now (emergencies, e.g. a security fix)' : 'In $d day${d == 1 ? '' : 's'}${d == 3 ? ' (recommended)' : ''}'),
            ),
        ],
      ),
    );
    if (days == null) return;
    await _set(latest.build, days == 0 ? null : DateTime.now().add(Duration(days: days)));
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final latest = _latest;
    final requiring = _min > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('App updates')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: TextButton(onPressed: _load, child: const Text('Could not load. Retry')))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.android_rounded, color: Colors.green),
                      title: Text(latest == null ? 'No Android release found' : 'Latest Android version: ${latest.version}'),
                      subtitle: Text(latest == null
                          ? 'The Android build has not published yet.'
                          : [if (latest.sizeLabel.isNotEmpty) latest.sizeLabel, ...latest.notes.take(3)].join(' · ')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: requiring ? Theme.of(context).colorScheme.secondaryContainer : null,
                    child: ListTile(
                      leading: Icon(requiring ? Icons.lock_clock_rounded : Icons.lock_open_rounded),
                      title: Text(requiring ? 'Required: build $_min or newer' : 'No update is required'),
                      subtitle: Text(!requiring
                          ? 'People see a friendly "Update available" sheet they can postpone.'
                          : _from == null || DateTime.now().isAfter(_from!)
                              ? 'In force now: older apps show only the Update page.'
                              : 'Warning shown until ${_from!.toString().substring(0, 16)}, then required.'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (latest != null && latest.build > _min)
                    FilledButton.icon(
                      onPressed: _require,
                      icon: const Icon(Icons.system_update_rounded),
                      label: Text('Require version ${latest.version}'),
                    ),
                  if (requiring)
                    OutlinedButton(onPressed: () => _set(0, null), child: const Text('Stop requiring an update')),
                  const SizedBox(height: 16),
                  Text(
                    'When to require an update: security fixes, or a change the old app would break. '
                    'For normal improvements, let people update in their own time.\n\n'
                    'Apps installed before 26 Nov 2026 cannot show the Update page. When an update becomes '
                    'required they simply stop loading, so announce it first and give at least 3 days.',
                    style: TextStyle(color: muted, height: 1.4),
                  ),
                ]),
    );
  }
}
