import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme.dart';

/// Build number baked in by GitHub Actions (0 for local builds).
const kAppBuild = int.fromEnvironment('APP_BUILD');

/// Where the Android build publishes its newest version details.
final _versionUrl = AppConfig.androidApkUrl.replaceFirst('campuslink.apk', 'version.json');

/// Sent with every database request, so the database can refuse apps that
/// are too old once an update is required (see 0025_app_update_gate.sql).
Map<String, String> appVersionHeaders() {
  if (kIsWeb) return const {}; // browsers send an Origin header instead
  return {
    'x-app-platform': defaultTargetPlatform.name.toLowerCase(),
    if (defaultTargetPlatform == TargetPlatform.android) 'x-app-build': '$kAppBuild',
  };
}

/// The newest Android release, as written by the build (version.json).
class AppRelease {
  const AppRelease({
    required this.build,
    required this.version,
    required this.url,
    this.sha256,
    this.sizeBytes,
    this.notes = const [],
  });

  /// [abis] are the phone's processor types, best first (from Android).
  /// When the release has a slim APK for one of them, that one is used: about
  /// a third of the size. Otherwise the all-in-one APK.
  factory AppRelease.fromMap(Map<String, dynamic> m, {List<String> abis = const []}) {
    final slim = m['apks'] is Map ? Map<String, dynamic>.from(m['apks'] as Map) : const <String, dynamic>{};
    Map<String, dynamic>? pick;
    for (final a in abis) {
      if (slim[a] is Map) {
        pick = Map<String, dynamic>.from(slim[a] as Map);
        break;
      }
    }
    return AppRelease(
      build: (m['build'] as num).toInt(),
      version: '${m['version'] ?? m['build']}',
      url: '${pick?['url'] ?? m['url'] ?? AppConfig.androidApkUrl}',
      sha256: (pick?['sha256'] ?? m['sha256']) as String?,
      sizeBytes: ((pick?['size'] ?? m['size']) as num?)?.toInt(),
      notes: [for (final n in (m['notes'] as List? ?? const [])) '$n'],
    );
  }

  final int build;
  final String version;
  final String url;
  final String? sha256;
  final int? sizeBytes;
  final List<String> notes;

  String get sizeLabel => sizeBytes == null ? '' : '${(sizeBytes! / 1048576).toStringAsFixed(0)} MB';
}

enum UpdateLevel { none, available, requiredSoon, required }

/// What the app knows about updates right now. Me → "Update available" reads
/// this too, so the update is never lost after "Not now".
class UpdateState {
  const UpdateState(this.level, {this.release, this.requiredFrom});
  final UpdateLevel level;
  final AppRelease? release;
  final DateTime? requiredFrom;
}

final updateState = ValueNotifier(const UpdateState(UpdateLevel.none));

/// Android only. Checks for a newer version on start and when the app comes
/// back to the front (at most every 6 hours):
/// - newer version: a tidy "Update available" sheet, once per version, again after 3 days;
/// - required later: the same sheet, saying from when it becomes required;
/// - required now: a full-screen page that can't be closed. The database also
///   refuses old apps, so ignoring the page doesn't help.
/// The web app updates itself, so it never asks.
class UpdateChecker extends StatefulWidget {
  const UpdateChecker({super.key, required this.child});
  final Widget child;
  @override
  State<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<UpdateChecker> with WidgetsBindingObserver {
  static const _snoozeKey = 'campuslink.update.snooze'; // "build|until-millis"
  DateTime? _lastCheck;
  bool _sheet = false;

  bool get _enabled => !kIsWeb && defaultTargetPlatform == TargetPlatform.android && kAppBuild > 0;

  @override
  void initState() {
    super.initState();
    if (_enabled) {
      WidgetsBinding.instance.addObserver(this);
      Future.delayed(const Duration(seconds: 4), _check);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed &&
        (_lastCheck == null || DateTime.now().difference(_lastCheck!) > const Duration(hours: 6))) {
      _check();
    }
  }

  Future<void> _check() async {
    _lastCheck = DateTime.now();
    try {
      final r = await http.get(Uri.parse('$_versionUrl?t=${DateTime.now().millisecondsSinceEpoch ~/ 600000}'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return;
      var abis = const <String>[];
      try {
        abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
      } catch (_) {/* unknown: the all-in-one APK always works */}
      final rel = AppRelease.fromMap(jsonDecode(r.body) as Map<String, dynamic>, abis: abis);

      var minBuild = 0;
      DateTime? from;
      if (AppConfig.hasSupabase) {
        try {
          final p = Map<String, dynamic>.from(await Supabase.instance.client.rpc('app_update_policy') as Map);
          minBuild = (p['min_build'] as num?)?.toInt() ?? 0;
          from = p['required_from'] == null ? null : DateTime.tryParse('${p['required_from']}')?.toLocal();
        } catch (_) {/* offline: decide from version.json only */}
      }

      final level = kAppBuild < minBuild
          ? (from != null && DateTime.now().isBefore(from) ? UpdateLevel.requiredSoon : UpdateLevel.required)
          : rel.build > kAppBuild
              ? UpdateLevel.available
              : UpdateLevel.none;
      updateState.value = UpdateState(level, release: rel, requiredFrom: from);
      if (level == UpdateLevel.none || level == UpdateLevel.required) return setState(() {});

      // Don't nag: once per version, then again after 3 days (1 day if it will become required).
      final prefs = await SharedPreferences.getInstance();
      final snooze = (prefs.getString(_snoozeKey) ?? '').split('|');
      if (snooze.length == 2 && snooze[0] == '${rel.build}' &&
          DateTime.now().millisecondsSinceEpoch < (int.tryParse(snooze[1]) ?? 0)) {
        return;
      }
      if (mounted) setState(() => _sheet = true);
    } catch (_) {/* no internet: try next time */}
  }

  Future<void> _notNow() async {
    final s = updateState.value;
    setState(() => _sheet = false);
    final wait = s.level == UpdateLevel.requiredSoon ? const Duration(days: 1) : const Duration(days: 3);
    try {
      (await SharedPreferences.getInstance())
          .setString(_snoozeKey, '${s.release?.build}|${DateTime.now().add(wait).millisecondsSinceEpoch}');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = updateState.value;
    if (s.level == UpdateLevel.required && s.release != null) {
      return UpdateRequiredPage(release: s.release!);
    }
    return Stack(children: [
      widget.child,
      // Dimmed background + sheet sliding up from the bottom.
      IgnorePointer(
        ignoring: !_sheet,
        child: AnimatedOpacity(
          opacity: _sheet ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: GestureDetector(onTap: _notNow, child: Container(color: Colors.black54)),
        ),
      ),
      AnimatedPositioned(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        left: 0,
        right: 0,
        bottom: _sheet ? 0 : -700,
        child: s.release == null
            ? const SizedBox.shrink()
            : _UpdateSheet(state: s, onLater: _notNow),
      ),
    ]);
  }
}

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet({required this.state, required this.onLater});
  final UpdateState state;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final rel = state.release!;
    final soon = state.level == UpdateLevel.requiredSoon;
    final t = Theme.of(context);
    return Material(
      color: t.colorScheme.surface,
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                    width: 40, height: 4, decoration: BoxDecoration(color: t.dividerColor, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 18),
              Row(children: [
                const _AppIcon(size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(soon ? 'Update needed soon' : 'Update available',
                        style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      [
                        'Version ${rel.version}',
                        if (rel.sizeLabel.isNotEmpty) rel.sizeLabel,
                      ].join(' · '),
                      style: TextStyle(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ]),
                ),
              ]),
              if (soon && state.requiredFrom != null) ...[
                const SizedBox(height: 14),
                _Note(
                  icon: Icons.event_rounded,
                  text: 'From ${_day(state.requiredFrom!)}, older versions will stop working. Update now to avoid interruption.',
                ),
              ],
              const SizedBox(height: 14),
              _WhatsNew(notes: rel.notes),
              const SizedBox(height: 18),
              UpdateButton(release: rel),
              const SizedBox(height: 4),
              TextButton(onPressed: onLater, child: Text(soon ? 'Remind me tomorrow' : 'Not now')),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Full screen, no way back: shown when this version is no longer allowed.
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({super.key, required this.release});
  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: Brand.primaryGradient),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(children: [
                    const _AppIcon(size: 84),
                    const SizedBox(height: 18),
                    const Text('Time to update CampusLink',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text(
                      'This version is no longer supported. The update takes about a minute, '
                      'and your account, messages and settings stay exactly as they are.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, height: 1.4),
                    ),
                    const SizedBox(height: 22),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(
                            ['Version ${release.version}', if (release.sizeLabel.isNotEmpty) release.sizeLabel].join(' · '),
                            style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          _WhatsNew(notes: release.notes),
                          const SizedBox(height: 16),
                          UpdateButton(release: release),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Downloads the new version inside the app (with progress), checks it is
/// the genuine file (SHA-256), then opens Android's installer.
class UpdateButton extends StatefulWidget {
  const UpdateButton({super.key, required this.release});
  final AppRelease release;
  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  StreamSubscription<OtaEvent>? _sub;
  double? _progress; // null = not started
  String? _message;
  bool _failed = false;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() => (_progress = 0, _message = 'Starting download…', _failed = false));
    try {
      _sub = OtaUpdate()
          .execute(widget.release.url,
              destinationFilename: 'campuslink-${widget.release.build}.apk', sha256checksum: widget.release.sha256)
          .listen(_onEvent, onError: (_) => _fail('The download stopped. Check your internet and try again.'));
    } catch (_) {
      _fail('Could not start the download.');
    }
  }

  void _onEvent(OtaEvent e) {
    if (!mounted) return;
    switch (e.status) {
      case OtaStatus.DOWNLOADING:
        final p = (double.tryParse(e.value ?? '') ?? 0) / 100;
        setState(() => (_progress = p, _message = 'Downloading… ${(p * 100).round()}%'));
      case OtaStatus.INSTALLING:
      case OtaStatus.INSTALLATION_DONE:
        setState(() => (_progress = 1, _message = 'Opening the installer… Tap "Update" when Android asks.'));
      case OtaStatus.ALREADY_RUNNING_ERROR:
        setState(() => _message = 'Already downloading…');
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _fail('Android needs your OK first: allow "Install unknown apps" for CampusLink, then tap Try again.');
      case OtaStatus.CHECKSUM_ERROR:
        _fail("The download didn't match the official file, so it was deleted for your safety. Try again.");
      case OtaStatus.INSTALLATION_ERROR:
      case OtaStatus.CANCELED:
        _fail('The install was cancelled. Tap Try again when you are ready.');
      default:
        _fail('The download stopped. Check your internet and try again.');
    }
  }

  void _fail(String m) => mounted ? setState(() => (_failed = true, _message = m, _progress = null)) : null;

  @override
  Widget build(BuildContext context) {
    final busy = _progress != null && !_failed;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (busy) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 8),
        ),
        const SizedBox(height: 8),
      ],
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(_message!,
              textAlign: TextAlign.center,
              style: TextStyle(color: _failed ? Theme.of(context).colorScheme.error : null)),
        ),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        onPressed: busy ? null : _start,
        icon: Icon(_failed ? Icons.refresh_rounded : Icons.system_update_rounded),
        label: Text(_failed ? 'Try again' : 'Update now'),
      ),
      if (_failed)
        TextButton(
          onPressed: () => launchUrl(Uri.parse(widget.release.url), mode: LaunchMode.externalApplication),
          child: const Text('Download with the browser instead'),
        ),
    ]);
  }
}

class _WhatsNew extends StatelessWidget {
  const _WhatsNew({required this.notes});
  final List<String> notes;
  @override
  Widget build(BuildContext context) {
    final items = notes.isEmpty ? const ['Improvements and fixes.'] : notes.take(5).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("What's new", style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      for (final n in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.check_circle_rounded, size: 16, color: Brand.teal)),
            const SizedBox(width: 8),
            Expanded(child: Text(n)),
          ]),
        ),
    ]);
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Brand.amber.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, color: Brand.amber),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * .24),
        child: Image.asset('assets/icon.png', width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
                width: size,
                height: size,
                decoration: const BoxDecoration(gradient: Brand.primaryGradient),
                child: Icon(Icons.hub_rounded, color: Colors.white, size: size * .5))),
      );
}

String _day(DateTime d) {
  const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${w[d.weekday - 1]} ${d.day} ${m[d.month - 1]}';
}

/// Me → "Update available": the same details, on their own page.
class UpdateDetailsScreen extends StatelessWidget {
  const UpdateDetailsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = updateState.value;
    final rel = s.release;
    return Scaffold(
      appBar: AppBar(title: const Text('App update')),
      body: rel == null || s.level == UpdateLevel.none
          ? const Center(child: Text("You're on the newest version."))
          : ListView(padding: const EdgeInsets.all(20), children: [
              Row(children: [
                const _AppIcon(size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    ['Version ${rel.version}', if (rel.sizeLabel.isNotEmpty) rel.sizeLabel].join(' · '),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
              if (s.level == UpdateLevel.requiredSoon && s.requiredFrom != null) ...[
                const SizedBox(height: 14),
                _Note(icon: Icons.event_rounded, text: 'Required from ${_day(s.requiredFrom!)}.'),
              ],
              const SizedBox(height: 16),
              _WhatsNew(notes: rel.notes),
              const SizedBox(height: 20),
              UpdateButton(release: rel),
            ]),
    );
  }
}
