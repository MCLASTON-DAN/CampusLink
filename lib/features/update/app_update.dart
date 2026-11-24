import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';

/// Build number baked in by GitHub Actions (0 for local builds).
const kAppBuild = int.fromEnvironment('APP_BUILD');

/// Where the Android build publishes its newest version number.
final _versionUrl = AppConfig.androidApkUrl.replaceFirst('campuslink.apk', 'version.json');

/// On the Android app only: if a newer APK exists, show a friendly banner
/// with an Update button. The web app updates itself, so it never asks.
class UpdateChecker extends StatefulWidget {
  const UpdateChecker({super.key, required this.child});
  final Widget child;
  @override
  State<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<UpdateChecker> {
  static const _skipKey = 'campuslink.update.skipped';
  int? _newBuild;
  String _newVersion = '';
  String _url = AppConfig.androidApkUrl;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && kAppBuild > 0) {
      Future.delayed(const Duration(seconds: 3), _check);
    }
  }

  Future<void> _check() async {
    try {
      final r = await http.get(Uri.parse(_versionUrl)).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      final build = (m['build'] as num).toInt();
      if (build <= kAppBuild) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt(_skipKey) == build) return; // "Later" for this version
      if (!mounted) return;
      setState(() {
        _newBuild = build;
        _newVersion = '${m['version'] ?? build}';
        _url = '${m['url'] ?? AppConfig.androidApkUrl}';
      });
    } catch (_) {/* no internet: try next time */}
  }

  Future<void> _later() async {
    final b = _newBuild;
    setState(() => _newBuild = null);
    try {
      if (b != null) (await SharedPreferences.getInstance()).setInt(_skipKey, b);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_newBuild == null) return widget.child;
    final s = Theme.of(context).colorScheme;
    return Stack(children: [
      widget.child,
      Positioned(
        left: 12,
        right: 12,
        bottom: 90,
        child: SafeArea(
          child: Material(
            elevation: 8,
            color: s.primaryContainer,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(children: [
                Icon(Icons.system_update_rounded, color: s.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('A new version of CampusLink is ready ($_newVersion).',
                      style: TextStyle(color: s.onPrimaryContainer, fontWeight: FontWeight.w600)),
                ),
                TextButton(onPressed: _later, child: const Text('Later')),
                FilledButton(
                  onPressed: () => launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication),
                  child: const Text('Update'),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
