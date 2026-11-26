import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'account_api.dart';

/// "Forgot password?" — works while signed out.
///
/// 1. Type your email → we send an email with a link AND a 6-digit code.
/// 2. Type the code here (works on any phone or computer), or tap the link.
/// 3. Choose a new password.
///
/// [onDone] runs after the new password is saved (the person is signed in).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = '', this.onDone});
  final String initialEmail;
  final VoidCallback? onDone;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _api = AccountApi.instance;
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  int _step = 0; // 0 email, 1 code, 2 new password
  bool _busy = false;
  String? _error;
  DateTime? _sentAt;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAccountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final bad = SchoolEmail.quickCheck(_email.text);
    if (bad != null) return setState(() => _error = bad);
    await _run(() async {
      await _api.sendPasswordReset(_email.text);
      _sentAt = DateTime.now();
      setState(() => _step = 1);
    });
  }

  Future<void> _verify() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) return setState(() => _error = 'Type the 6 numbers from the email.');
    await _run(() async {
      await _api.verifyResetCode(_email.text, _code.text);
      setState(() => _step = 2);
    });
  }

  bool get _canResend => _sentAt == null || DateTime.now().difference(_sentAt!) > const Duration(seconds: 60);

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: !_api.available
                    ? const Text('Password reset works in the live app, not in demo mode.')
                    : _step == 2
                        ? NewPasswordForm(
                            email: _email.text,
                            title: 'Choose a new password',
                            onSaved: () {
                              showSnack(context, 'Password changed. You are signed in.');
                              widget.onDone?.call();
                              if (widget.onDone == null) Navigator.of(context).maybePop();
                            },
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Steps(current: _step),
                              const SizedBox(height: 16),
                              if (_step == 0) ...[
                                Text('Type your school email. We will send you a code to reset your password.',
                                    style: TextStyle(color: muted)),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _email,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  decoration: const InputDecoration(
                                      labelText: 'School email', prefixIcon: Icon(Icons.alternate_email)),
                                  onSubmitted: (_) => _send(),
                                ),
                              ] else ...[
                                Text('We sent an email to ${_email.text.trim()}.\n'
                                    'Type the 6-digit code from it, or just tap the link in the email.',
                                    style: TextStyle(color: muted)),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _code,
                                  keyboardType: TextInputType.number,
                                  autofillHints: const [AutofillHints.oneTimeCode],
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                                  style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w700),
                                  textAlign: TextAlign.center,
                                  decoration: const InputDecoration(hintText: '••••••'),
                                  onSubmitted: (_) => _verify(),
                                ),
                                const SizedBox(height: 6),
                                Text("No email after 2 minutes? Check Spam or Promotions.",
                                    style: Theme.of(context).textTheme.bodySmall),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                _ErrorText(_error!),
                              ],
                              const SizedBox(height: 18),
                              FilledButton(
                                onPressed: _busy ? null : (_step == 0 ? _send : _verify),
                                child: _busy
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Text(_step == 0 ? 'Send code' : 'Check code'),
                              ),
                              if (_step == 1)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _canResend
                                          ? _send()
                                          : setState(() => _error = 'Wait a minute before asking for another email.'),
                                  child: const Text('Send a new code'),
                                ),
                              if (_step == 1)
                                TextButton(
                                  onPressed: () => setState(() {
                                    _step = 0;
                                    _code.clear();
                                    _error = null;
                                  }),
                                  child: const Text('Use a different email'),
                                ),
                            ],
                          ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Signed-in: "Create a password" (Google users) or "Change password".
Future<void> showSetPasswordSheet(BuildContext context, {required bool hasPassword, String? email}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: NewPasswordForm(
        email: email,
        title: hasPassword ? 'Change password' : 'Create a password',
        intro: hasPassword
            ? null
            : 'You joined with Google. A password lets you also sign in with your school email, '
                'for example on a computer where Google is not signed in.',
        onSaved: () {
          Navigator.pop(ctx);
          showSnack(context, hasPassword ? 'Password changed.' : 'Password created. You can now sign in with email too.');
        },
      ),
    ),
  );
}

/// Two password boxes, a strength bar and Save. Used by reset, create and change.
class NewPasswordForm extends StatefulWidget {
  const NewPasswordForm({super.key, required this.title, required this.onSaved, this.email, this.intro});
  final String title;
  final String? intro;
  final String? email;
  final VoidCallback onSaved;

  @override
  State<NewPasswordForm> createState() => _NewPasswordFormState();
}

class _NewPasswordFormState extends State<NewPasswordForm> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _nonce = TextEditingController();
  bool _show = false;
  bool _busy = false;
  bool _needNonce = false;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    _nonce.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bad = PasswordRules.check(_pw.text, email: widget.email);
    if (bad != null) return setState(() => _error = bad);
    if (_pw.text != _pw2.text) return setState(() => _error = 'The two passwords are not the same.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AccountApi.instance.setPassword(_pw.text, nonce: _needNonce ? _nonce.text.trim() : null);
      widget.onSaved();
    } catch (e) {
      final m = e.toString().toLowerCase();
      if (m.contains('reauthentication') && !_needNonce) {
        // Project asks for proof before a password change: email a code.
        try {
          await AccountApi.instance.sendReauthCode();
        } catch (_) {}
        if (mounted) setState(() => _needNonce = true);
      }
      if (mounted) setState(() => _error = friendlyAccountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = PasswordRules.strength(_pw.text);
    final colors = [Brand.coral, Brand.amber, Brand.teal, Colors.green];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        if (widget.intro != null) ...[
          const SizedBox(height: 6),
          Text(widget.intro!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _pw,
          obscureText: !_show,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'New password',
            helperText: '8+ characters, letters and numbers',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _show ? 'Hide' : 'Show',
              icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _pw.text.isEmpty ? 0 : (s + 1) / 4,
            minHeight: 6,
            color: colors[s],
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pw2,
          obscureText: !_show,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(labelText: 'Type it again', prefixIcon: Icon(Icons.lock_reset)),
          onSubmitted: (_) => _save(),
        ),
        if (_needNonce) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _nonce,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Code from the email we just sent', prefixIcon: Icon(Icons.pin)),
          ),
        ],
        if (_error != null) ...[const SizedBox(height: 12), _ErrorText(_error!)],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save password'),
        ),
      ],
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.current});
  final int current;
  @override
  Widget build(BuildContext context) {
    const labels = ['Email', 'Code', 'Password'];
    return Row(children: [
      for (var i = 0; i < labels.length; i++) ...[
        CircleAvatar(
          radius: 12,
          backgroundColor: i <= current ? Brand.violet : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text('${i + 1}', style: TextStyle(fontSize: 12, color: i <= current ? Colors.white : null)),
        ),
        const SizedBox(width: 6),
        Flexible(child: Text(labels[i], style: Theme.of(context).textTheme.labelMedium, overflow: TextOverflow.ellipsis)),
        if (i < labels.length - 1) const Expanded(child: Divider(indent: 6, endIndent: 6)),
      ],
    ]);
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline, size: 18, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]);
}


/// Opened by the reset link or code. Asks for the new password.
class SetNewPasswordScreen extends StatelessWidget {
  const SetNewPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = AccountApi.instance;
    final session = api.available ? Supabase.instance.client.auth.currentSession : null;
    return Scaffold(
      appBar: AppBar(title: const Text('New password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: session == null
                    ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const Text('This reset link has expired or was already used.'),
                        const SizedBox(height: 14),
                        FilledButton(onPressed: () => context.go('/forgot-password'), child: const Text('Send a new code')),
                      ])
                    : NewPasswordForm(
                        email: session.user.email,
                        title: 'Choose a new password',
                        onSaved: () {
                          showSnack(context, 'Password changed. You are signed in.');
                          context.go('/home');
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Me → Password: works out whether to offer "Create" (Google users) or "Change".
Future<void> openPasswordSettings(BuildContext context) async {
  final api = AccountApi.instance;
  if (!api.available) return showSnack(context, 'Passwords work in the live app, not in demo mode.');
  try {
    final m = await api.signInMethods();
    if (!context.mounted) return;
    await showSetPasswordSheet(context, hasPassword: m.hasPassword, email: m.email);
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyAccountError(e));
  }
}
