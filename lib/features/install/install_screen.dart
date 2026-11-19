import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/pwa/pwa.dart';
import '../../widgets/common.dart';
import '../../widgets/section.dart';

enum InstallTarget { android, ios, mac, windows, linux, other, nativeApp }

InstallTarget detectInstallTarget() {
  if (!kIsWeb) return InstallTarget.nativeApp;
  final ua = pwaUserAgent().toLowerCase();
  if (ua.contains('android')) return InstallTarget.android;
  if (ua.contains('iphone') || ua.contains('ipad') || (ua.contains('macintosh') && ua.contains('mobile'))) {
    return InstallTarget.ios;
  }
  if (ua.contains('mac os')) return InstallTarget.mac;
  if (ua.contains('windows')) return InstallTarget.windows;
  if (ua.contains('linux')) return InstallTarget.linux;
  return InstallTarget.other;
}

/// The Android app needs Android 7.0 or newer (Flutter's minimum, API 24).
const minAndroidForApk = 7;

/// Reads the Android version from a browser's user agent, e.g. "Android 6.0.1" -> 6.
/// Returns null when it is not Android or the version is hidden.
int? androidMajorVersion(String ua) {
  final m = RegExp(r'android\s+(\d+)', caseSensitive: false).firstMatch(ua);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// False only when we are sure the phone is too old for the APK.
bool apkFitsThisPhone([String? ua]) {
  final v = androidMajorVersion(ua ?? pwaUserAgent());
  return v == null || v >= minAndroidForApk;
}

/// True when it makes sense to suggest installing (web, not installed yet).
bool shouldSuggestInstall() => kIsWeb && !pwaIsStandalone();

class InstallScreen extends StatefulWidget {
  const InstallScreen({super.key});
  @override
  State<InstallScreen> createState() => _InstallScreenState();
}

class _InstallScreenState extends State<InstallScreen> {
  late final InstallTarget _target = detectInstallTarget();
  late final bool _apkOk = apkFitsThisPhone();
  bool _canPrompt = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _canPrompt = pwaCanInstall();
    // The browser may offer install a moment after the page loads.
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      final v = pwaCanInstall();
      if (v != _canPrompt && mounted) setState(() => _canPrompt = v);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _install() async {
    final r = await pwaPromptInstall();
    if (!mounted) return;
    showSnack(context, r == 'accepted' ? 'Installing CampusLink…' : 'Install was not started');
  }

  @override
  Widget build(BuildContext context) {
    final installed = !kIsWeb || pwaIsStandalone();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Install the app')),
      body: PageBody(maxWidth: 720, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(installed ? 'You are using the installed app ✓' : 'Get CampusLink on this device',
                  style: t.titleLarge),
              const SizedBox(height: 6),
              Text(
                installed
                    ? 'It opens from your home screen or app list, works full screen and loads fast.'
                    : 'Install once. It opens like a normal app, full screen, and loads faster next time.',
                style: t.bodyMedium,
              ),
              if (!installed) ...[
                const SizedBox(height: 16),
                ..._steps(context),
              ],
            ]),
          ),
        ),
        const SectionTitle('Other devices'),
        _Row(
          icon: Icons.android_rounded,
          title: 'Android app (APK)',
          text: _apkOk
              ? 'Needs Android $minAndroidForApk.0 or newer. Download, open the file, and allow "Install unknown apps" when asked.'
              : 'This phone is too old for the Android app (needs Android $minAndroidForApk.0+). Use the web app above instead.',
          button: _apkOk ? 'Download' : null,
          onTap: () => launchUrl(Uri.parse(AppConfig.androidApkUrl), mode: LaunchMode.externalApplication),
        ),
        _Row(
          icon: Icons.ios_share_rounded,
          title: 'iPhone and iPad',
          text: 'Open the link in Safari, tap Share, then "Add to Home Screen".',
        ),
        _Row(
          icon: Icons.computer_rounded,
          title: 'Windows, Mac, Linux, Chromebook',
          text: 'Open the link in Chrome or Edge and click the install icon in the address bar.',
        ),
        _Row(
          icon: Icons.link_rounded,
          title: 'Share the link',
          text: AppConfig.webUrl,
          button: 'Copy',
          onTap: () async {
            await Clipboard.setData(const ClipboardData(text: AppConfig.webUrl));
            if (context.mounted) showSnack(context, 'Link copied');
          },
        ),
      ]),
    );
  }

  List<Widget> _steps(BuildContext context) {
    Widget step(String n, String s) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 12, child: Text(n, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            Expanded(child: Text(s)),
          ]),
        );
    switch (_target) {
      case InstallTarget.android when !_apkOk:
        return [
          Text(
            'This phone runs an Android version older than $minAndroidForApk.0, so the Android app cannot install on it. '
            'The web app below does the same things: news, events, map, tutors and more.',
          ),
          const SizedBox(height: 12),
          if (_canPrompt)
            FilledButton.icon(onPressed: _install, icon: const Icon(Icons.install_mobile_rounded), label: const Text('Install the web app'))
          else ...[
            step('1', 'Open this page in Chrome.'),
            step('2', 'Tap the menu (three dots), then "Add to Home screen" or "Install app".'),
          ],
        ];
      case InstallTarget.android:
        return [
          FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse(AppConfig.androidApkUrl), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.android_rounded),
            label: const Text('Download the Android app'),
          ),
          const SizedBox(height: 8),
          if (_canPrompt)
            OutlinedButton.icon(onPressed: _install, icon: const Icon(Icons.install_mobile_rounded), label: const Text('Or install the web app')),
        ];
      case InstallTarget.ios:
        return [
          step('1', 'Open this page in Safari.'),
          step('2', 'Tap the Share button (square with an arrow).'),
          step('3', 'Choose "Add to Home Screen", then "Add".'),
        ];
      default:
        return [
          if (_canPrompt)
            FilledButton.icon(onPressed: _install, icon: const Icon(Icons.download_rounded), label: const Text('Install CampusLink'))
          else ...[
            step('1', 'Use Chrome or Edge.'),
            step('2', 'Click the install icon at the right of the address bar (a screen with a down arrow).'),
            if (_target == InstallTarget.mac) step('•', 'In Safari: File → Add to Dock.'),
          ],
        ];
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.text, this.button, this.onTap});
  final IconData icon;
  final String title, text;
  final String? button;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(text, style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              if (button != null) ...[const SizedBox(width: 8), TextButton(onPressed: onTap, child: Text(button!))],
            ]),
          ),
        ),
      );
}
