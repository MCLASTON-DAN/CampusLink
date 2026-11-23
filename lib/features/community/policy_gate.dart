import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../widgets/section.dart';
import '../legal/policies.dart';

export '../legal/policies.dart' show kPolicyVersion;

/// Opens a policy as a full page. Closing it always returns to where you were.
Future<void> showPolicy(BuildContext context, String key) {
  final doc = allPolicies[key]!;
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(builder: (_) => PolicyScreen(doc: doc)),
  );
}

class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key, required this.doc});
  final PolicyDoc doc;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: PageBody(
        maxWidth: 760,
        children: [
          Text(doc.summary, style: t.bodyLarge),
          const SizedBox(height: 4),
          Text('Version $kPolicyVersion · effective $kPolicyEffective',
              style: t.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
          for (final s in doc.sections) ...[
            const SizedBox(height: 20),
            Text(s.heading,
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SelectableText(s.body, style: t.bodyMedium?.copyWith(height: 1.5)),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

final _acceptedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final c = ref.watch(communityProvider);
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return true;
  final r = await Future.wait([
    c.hasAccepted('privacy', kPolicyVersion),
    c.hasAccepted('terms', kPolicyVersion)
  ]);
  return r.every((x) => x);
});

/// Shows [child] only after the person has accepted the current privacy
/// policy and terms. New users, and everyone after a policy change, see a
/// short "Before you start" page first.
class PolicyAcceptanceGate extends ConsumerStatefulWidget {
  const PolicyAcceptanceGate({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<PolicyAcceptanceGate> createState() => _GateState();
}

class _GateState extends ConsumerState<PolicyAcceptanceGate> {
  bool _ticked = false;
  bool _saving = false;

  Future<void> _accept() async {
    setState(() => _saving = true);
    try {
      final c = ref.read(communityProvider);
      await c.accept('privacy', kPolicyVersion);
      await c.accept('terms', kPolicyVersion);
      ref.invalidate(_acceptedProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Could not save. Check your internet and try again.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accepted = ref.watch(_acceptedProvider);
    // While checking, or if the check fails (offline), don't block the app.
    if (accepted.valueOrNull != false) return widget.child;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: PageBody(
          maxWidth: 640,
          children: [
            const SizedBox(height: 24),
            Icon(Icons.verified_user_rounded,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Before you start',
                style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
                'Please read how CampusLink handles your data and the rules everyone follows. '
                'You only need to do this once, or again if they change.'),
            const SizedBox(height: 20),
            for (final d in [privacyPolicy, termsOfUse])
              Card(
                child: ListTile(
                  leading: Icon(d.key == 'privacy'
                      ? Icons.privacy_tip_rounded
                      : Icons.gavel_rounded),
                  title: Text(d.title),
                  subtitle: Text(d.summary),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showPolicy(context, d.key),
                ),
              ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _ticked,
              onChanged: (v) => setState(() => _ticked = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                  'I have read and agree to the Privacy Policy and Terms of Use.'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: !_ticked || _saving ? null : _accept,
              child: Text(_saving ? 'Saving…' : 'Agree and continue'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(repositoryProvider).signOut(),
              child: const Text('Not now, sign me out'),
            ),
          ],
        ),
      ),
    );
  }
}
