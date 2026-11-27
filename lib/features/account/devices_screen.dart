import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/section.dart';
import 'account_api.dart';

/// Me > Your devices: everywhere this account is signed in, with a way to
/// sign any of them out. Every new sign-in also sends an alert (in the app,
/// on the phone and by email), so a stranger can't stay unnoticed.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});
  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _api = AccountApi.instance;
  late Future<List<SignedInDevice>> _list = _load();
  final _busy = <String>{};

  Future<List<SignedInDevice>> _load() => _api.available ? _api.devices() : Future.value(const []);

  void _reload() => setState(() => _list = _load());

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      ) ==
      true;

  Future<void> _signOut(SignedInDevice d) async {
    if (!await _confirm('Sign out ${d.name}?', 'That device will need to sign in again to use your account.', 'Sign out')) {
      return;
    }
    setState(() => _busy.add(d.id));
    try {
      await _api.signOutDevice(d.id);
      if (mounted) showSnack(context, 'Signed out ${d.name}.');
    } catch (_) {
      if (mounted) showSnack(context, 'Could not sign it out. Try again.');
    }
    _busy.remove(d.id);
    _reload();
  }

  Future<void> _signOutOthers() async {
    if (!await _confirm('Sign out every other device?',
        'Only this device stays signed in. Do this if you see a device you don\'t recognise.', 'Sign out others')) {
      return;
    }
    try {
      final n = await _api.signOutOtherDevices();
      if (mounted) showSnack(context, n == 0 ? 'No other devices were signed in.' : 'Signed out $n ${n == 1 ? 'device' : 'devices'}.');
    } catch (_) {
      if (mounted) showSnack(context, 'Could not sign them out. Try again.');
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your devices')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<SignedInDevice>>(
          future: _list,
          builder: (context, snap) {
            if (!_api.available) {
              return const EmptyState(
                  icon: Icons.devices_rounded, title: 'Not in demo mode', subtitle: 'Sign in with a real account to see your devices.');
            }
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return EmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Could not load',
                subtitle: 'Check your connection and try again.',
                action: FilledButton(onPressed: _reload, child: const Text('Retry')),
              );
            }
            final list = snap.data ?? const <SignedInDevice>[];
            final others = list.where((d) => !d.isThisDevice).toList();
            return PageBody(children: [
              Text(
                'Everywhere your account is signed in. You get an alert each time it\'s opened on a new sign-in. '
                'If you see a device you don\'t recognise, sign it out and secure your Google account or password.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              for (final d in list) _DeviceCard(d, busy: _busy.contains(d.id), onSignOut: () => _signOut(d)),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _signOutOthers,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out every other device'),
                ),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard(this.d, {required this.busy, required this.onSignOut});
  final SignedInDevice d;
  final bool busy;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            backgroundColor: c.primaryContainer,
            foregroundColor: c.onPrimaryContainer,
            child: Icon(d.isPhone ? Icons.smartphone_rounded : Icons.computer_rounded),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                if (d.isThisDevice) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: c.secondaryContainer, borderRadius: BorderRadius.circular(20)),
                    child: Text('This device', style: small?.copyWith(color: c.onSecondaryContainer, fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
              const SizedBox(height: 4),
              Text(d.isThisDevice ? 'Active now' : 'Last active ${friendlyDate(d.lastActiveAt)}', style: small),
              Text('Signed in ${fullDate(d.signedInAt)}${d.ip == null ? '' : ' · ${d.ip}'}', style: small),
            ]),
          ),
          if (!d.isThisDevice)
            busy
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : TextButton(onPressed: onSignOut, child: const Text('Sign out')),
        ]),
      ),
    );
  }
}

/// Opened from the "This wasn't me" button in a sign-in email. Works signed in
/// or out. A button (not an automatic action) so email apps that open links to
/// scan them can't sign anyone out.
class SecureAccountScreen extends ConsumerStatefulWidget {
  const SecureAccountScreen({super.key, required this.token});
  final String token;
  @override
  ConsumerState<SecureAccountScreen> createState() => _SecureAccountScreenState();
}

class _SecureAccountScreenState extends ConsumerState<SecureAccountScreen> {
  bool _busy = false;
  String? _result;

  Future<void> _secure() async {
    setState(() => _busy = true);
    String result;
    try {
      result = await AccountApi.instance.secureAccount(widget.token);
    } catch (_) {
      result = 'error';
    }
    // This device was signed out on the server too; clear it here.
    if (result == 'ok') {
      try {
        await ref.read(repositoryProvider).signOut();
      } catch (_) {}
    }
    if (mounted) setState(() => (_busy = false, _result = result));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (icon, title, body) = switch (_result) {
      null => (
          Icons.shield_rounded,
          'Wasn\'t you?',
          'Tap the button to sign your CampusLink account out of every device, including this one.'
        ),
      'ok' => (
          Icons.verified_user_rounded,
          'Every device is signed out',
          'Next, to keep your account safe:\n1. Secure your Google account and turn on 2-Step Verification.\n'
              '2. If you use a CampusLink password, change it after you sign in.'
        ),
      'done' => (Icons.check_circle_rounded, 'Already done', 'This link was already used. Every device was signed out then.'),
      'expired' => (
          Icons.timer_off_rounded,
          'Link expired',
          'This link only works for 7 days. Sign in and open Me > Your devices to sign devices out.'
        ),
      'invalid' => (Icons.link_off_rounded, 'Link not valid', 'This link is broken. Sign in and open Me > Your devices.'),
      _ => (Icons.wifi_off_rounded, 'Could not finish', 'Check your connection and try again.'),
    };
    final retry = _result == 'error';
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(body, style: t.bodyLarge, textAlign: _result == 'ok' ? TextAlign.start : TextAlign.center),
              const SizedBox(height: 24),
              if (_result == null || retry)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                  onPressed: _busy ? null : _secure,
                  icon: _busy
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.logout_rounded),
                  label: Text(retry ? 'Try again' : 'Sign out every device'),
                )
              else
                FilledButton(onPressed: () => context.go('/login'), child: const Text('Go to sign in')),
              if (_result == null) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: () => context.go('/home'), child: const Text('It was me, close this')),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
