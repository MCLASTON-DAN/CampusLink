import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/section.dart';
import 'account_api.dart';

/// Me → Close my account. Nothing is deleted for 30 days; signing in during
/// that time offers "Keep my account". After that, personal data is wiped by
/// the database's nightly job (finish_account_closures, 0027).
class CloseAccountScreen extends ConsumerStatefulWidget {
  const CloseAccountScreen({super.key});
  @override
  ConsumerState<CloseAccountScreen> createState() => _CloseAccountScreenState();
}

class _CloseAccountScreenState extends ConsumerState<CloseAccountScreen> {
  final _confirm = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _confirm.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    setState(() => (_busy = true, _error = null));
    try {
      // Fresh proof it's really them: refresh the sign-in first. A stolen,
      // stale session can't close someone's account.
      await Supabase.instance.client.auth.refreshSession();
      await AccountApi.instance.requestClosure(reason: _reason.text.trim().isEmpty ? null : _reason.text.trim());
      await AccountApi.instance.deleteMyPhotos();
      await ref.read(repositoryProvider).reloadMe();
      if (mounted) context.go('/account/closing');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ready = _confirm.text.trim().toUpperCase() == 'CLOSE';
    return Scaffold(
      appBar: AppBar(title: const Text('Close my account')),
      body: PageBody(maxWidth: 620, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('What happens', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const _Point(Icons.pause_circle_outline_rounded,
                  'Straight away your profile is hidden: no search, tutor list or buddy matching, and notifications stop. Your profile photo is removed.'),
              const _Point(Icons.undo_rounded,
                  'For 30 days nothing else is deleted. Sign in and tap "Keep my account" to get everything back.'),
              const _Point(Icons.delete_outline_rounded,
                  'After 30 days your personal details, timetable, exams, settings and sign-in are deleted for good.'),
              const _Point(Icons.forum_outlined,
                  'Replies in request threads and group chats, and reviews you wrote, stay so others\' conversations make sense. They show "Former student".'),
              const _Point(Icons.person_add_alt_rounded,
                  'You can join again later with the same email, as a new account.'),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reason,
          maxLength: 300,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Why are you leaving? (optional, not stored)'),
        ),
        TextField(
          controller: _confirm,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Type CLOSE to confirm'),
        ),
        if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: TextStyle(color: t.colorScheme.error))],
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: t.colorScheme.error, foregroundColor: t.colorScheme.onError),
          onPressed: ready && !_busy ? _close : null,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Close my account'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: () => context.pop(), child: const Text('Keep my account')),
      ]),
    );
  }
}

/// Shown instead of the app while an account is closing.
class AccountClosingScreen extends ConsumerStatefulWidget {
  const AccountClosingScreen({super.key});
  @override
  ConsumerState<AccountClosingScreen> createState() => _AccountClosingScreenState();
}

class _AccountClosingScreenState extends ConsumerState<AccountClosingScreen> {
  bool _busy = false;

  Future<void> _keep() async {
    setState(() => _busy = true);
    try {
      await AccountApi.instance.cancelClosure();
      await ref.read(repositoryProvider).reloadMe();
      if (mounted) {
        showSnack(context, 'Welcome back. Your account is staying.');
        context.go('/home');
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyAccountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = ref.watch(currentUserProvider).valueOrNull;
    final when = u?.closingAt == null ? '' : DateFormat('d MMMM yyyy').format(u!.closingAt!.toLocal());
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Icon(Icons.hourglass_bottom_rounded, size: 56),
                  const SizedBox(height: 14),
                  Text('Your account is closing',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    when.isEmpty
                        ? 'Your personal data will be deleted soon.'
                        : 'On $when your personal data will be deleted for good. Until then you can change your mind.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _keep,
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Keep my account'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: () => ref.read(repositoryProvider).signOut(), child: const Text('Sign out')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );
}
