import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/repository.dart' show EmailConfirmationNeeded;
import '../../widgets/common.dart';
import '../account/account_api.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _studentNo = TextEditingController();
  final _programme = TextEditingController(text: 'BDSAI');
  int _year = 1;
  bool _signup = false;
  bool _busy = false;
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);
  String? _emailHint; // "Cavendish University Uganda student" once the email is recognised

  @override
  void initState() {
    super.initState();
    // Coming back from Google with an error (e.g. a personal Gmail was refused):
    // the reason is in the web address. Show it instead of a silent failure.
    final q = {...Uri.base.queryParameters, ...Uri.splitQueryString(Uri.base.fragment.contains('=') ? Uri.base.fragment.replaceFirst(RegExp(r'^/?[^?]*\?'), '') : '')};
    final err = q['error_description'] ?? q['error'];
    if (err != null && err.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showProblem(friendlyAuthError(err));
      });
    }
  }

  void _showProblem(String msg) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.info_outline_rounded),
          title: const Text("Couldn't sign you in"),
          content: Text(msg),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );

  Future<void> _checkEmail() async {
    if (!_signup || ref.read(isDemoModeProvider)) return;
    final email = _email.text.trim();
    if (SchoolEmail.quickCheck(email) != null) return setState(() => _emailHint = null);
    final r = await AccountApi.instance.checkEmail(email);
    if (!mounted) return;
    setState(() => _emailHint = r.allowed
        ? (r.institution == null ? null : '${r.institution}${r.kind == 'staff' ? ' staff' : r.kind == 'student' ? ' student' : ''}')
        : null);
    if (!r.allowed && r.message != null) showSnack(context, r.message!);
  }

  Future<void> _confirmSent(String email) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.mark_email_read_rounded, size: 40),
          title: const Text('Check your school email'),
          content: Text('We sent a link to $email. Open it to finish making your account, then sign in here.\n\n'
              'Not there after 2 minutes? Look in Spam or Promotions.'),
          actions: [
            TextButton(
              onPressed: () async {
                try {
                  await AccountApi.instance.resendConfirmation(email);
                  if (ctx.mounted) showSnack(ctx, 'Sent again.');
                } catch (e) {
                  if (ctx.mounted) showSnack(ctx, friendlyAuthError(e));
                }
              },
              child: const Text('Send again'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _signup = false);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );

  @override
  void dispose() {
    _anim.dispose();
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _studentNo.dispose();
    _programme.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final repo = ref.read(repositoryProvider);
    final demo = ref.read(isDemoModeProvider);
    try {
      if (_signup && !demo) {
        // Friendly early check; the database checks again when the account is made.
        final r = await AccountApi.instance.checkEmail(_email.text);
        if (!r.allowed) {
          if (mounted) _showProblem(r.message ?? friendlyAuthError('school email'));
          return;
        }
      }
      if (_signup) {
        await repo.signUp(
          email: _email.text.trim(),
          password: _password.text,
          fullName: _name.text.trim(),
          studentNumber: _studentNo.text.trim().isEmpty ? null : _studentNo.text.trim(),
          programme: _programme.text.trim(),
          yearOfStudy: _year,
        );
      } else {
        await repo.signIn(email: _email.text.trim(), password: _password.text);
      }
    } on EmailConfirmationNeeded {
      if (mounted) await _confirmSent(_email.text.trim());
    } catch (e) {
      if (mounted) {
        final m = friendlyAuthError(e);
        m.contains('school email') ? _showProblem(m) : showSnack(context, m);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) showSnack(context, friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final demo = ref.watch(isDemoModeProvider);
    final wide = ScreenSize.of(context) >= ScreenSize.expanded;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(Brand.indigo, Brand.violet, _anim.value)!,
                Color.lerp(Brand.violet, Brand.coral, _anim.value)!,
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 920 : 460),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: _Hero()),
                            const SizedBox(width: 40),
                            Expanded(child: _card(context, demo)),
                          ],
                        )
                      : Column(
                          children: [
                            _Hero(compact: true),
                            const SizedBox(height: 24),
                            _card(context, demo),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, bool demo) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_signup ? 'Create your account' : 'Welcome back',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  demo
                      ? 'Demo mode: any email and password work. Use an email containing "staff" to see staff tools.'
                      : _signup
                          ? 'Only school email addresses can join.'
                          : 'Sign in with your school account.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                if (!demo) ...[
                  _GoogleButton(onPressed: _busy ? null : _google),
                  const SizedBox(height: 6),
                  Text('Pick your school account, like od251945@students.cavendish.ac.ug',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('or use email', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 16),
                ],
                if (_signup) ...[
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _studentNo,
                          decoration: const InputDecoration(labelText: 'Student no.', prefixIcon: Icon(Icons.badge_outlined)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _programme,
                          decoration: const InputDecoration(labelText: 'Programme', prefixIcon: Icon(Icons.school_outlined)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _year,
                    decoration: const InputDecoration(labelText: 'Year of study', prefixIcon: Icon(Icons.timeline_rounded)),
                    items: [for (var y = 1; y <= 5; y++) DropdownMenuItem(value: y, child: Text('Year $y'))],
                    onChanged: (v) => setState(() => _year = v ?? 1),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: demo ? 'Email' : 'School email',
                    hintText: 'od251945@students.cavendish.ac.ug',
                    prefixIcon: const Icon(Icons.alternate_email),
                    helperText: _signup ? _emailHint : null,
                  ),
                  onEditingComplete: () {
                    _checkEmail();
                    FocusScope.of(context).nextFocus();
                  },
                  validator: (v) {
                    if (demo) return (v ?? '').contains('@') ? null : 'Enter a valid email';
                    // New accounts need a school email. Signing in stays open, so
                    // older accounts (made before the rule) still get in.
                    if (_signup) return SchoolEmail.quickCheck(v ?? '');
                    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter your email';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: [_signup ? AutofillHints.newPassword : AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                  validator: (v) {
                    if (demo) return (v ?? '').length < 6 ? 'At least 6 characters' : null;
                    if (_signup) return PasswordRules.check(v ?? '', email: _email.text);
                    return (v ?? '').isEmpty ? 'Enter your password' : null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (!_signup && !demo)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => context.push('/forgot-password', extra: _email.text.trim()),
                      child: const Text('Forgot password?'),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_signup ? 'Create account' : 'Sign in'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _signup = !_signup),
                  child: Text(_signup ? 'I already have an account' : 'New here? Create an account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final white = Colors.white;
    return Column(
      crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 64 : 80,
          height: compact ? 64 : 80,
          decoration: BoxDecoration(
            color: white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: white.withValues(alpha: 0.4)),
          ),
          child: Icon(Icons.hub_rounded, color: white, size: compact ? 34 : 44),
        ),
        const SizedBox(height: 18),
        Text(AppConfig.appName,
            style: TextStyle(color: white, fontSize: compact ? 32 : 44, fontWeight: FontWeight.w900, letterSpacing: -1)),
        const SizedBox(height: 8),
        Text(
          'Every answer a ${AppConfig.university} student needs — in one place.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(color: white.withValues(alpha: 0.92), fontSize: compact ? 15 : 18, height: 1.4),
        ),
        if (!compact) ...[
          const SizedBox(height: 28),
          for (final f in const [
            ('Where do I go?', 'Ask in plain words, get the right office.'),
            ('Track your requests', 'See every help ticket move from open to resolved.'),
            ('Find your people', 'Tutors, study groups and a first-year buddy.'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: white.withValues(alpha: 0.9), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(color: white.withValues(alpha: 0.92), fontSize: 15),
                        children: [
                          TextSpan(text: '${f.$1}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: f.$2),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}


/// Turns sign-in errors into words a student understands.
String friendlyAuthError(Object e) => friendlyAccountError(e);

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: Theme.of(context).colorScheme.surface,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Google's four colours in a simple "G" mark.
          ShaderMask(
            shaderCallback: (r) => const SweepGradient(
              colors: [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335), Color(0xFF4285F4)],
            ).createShader(r),
            child: const Text('G', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          const Text('Continue with Google', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
      );
}
