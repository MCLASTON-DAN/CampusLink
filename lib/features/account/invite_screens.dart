import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/repository.dart' show EmailConfirmationNeeded;
import '../../widgets/common.dart';
import 'account_api.dart';

String _date(dynamic iso) => iso == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse('$iso').toLocal());

/// What someone opening an invite link sees (works signed out).
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key, required this.token});
  final String token;
  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final _api = AccountApi.instance;
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _pw = TextEditingController();
  Map<String, dynamic>? _info;
  bool _claimed = false;
  bool _busy = false;
  bool _usePassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api.inviteInfo(widget.token).then((i) {
      if (mounted) setState(() => _info = i);
    }).catchError((_) {
      if (mounted) setState(() => _info = {'valid': false, 'reason': 'Could not open the invite. Check your internet.'});
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    setState(() => (_busy = true, _error = null));
    try {
      final r = await _api.claimInvite(widget.token, _email.text);
      if (r['ok'] != true) {
        setState(() => _error = '${r['reason']}');
      } else if (r['school'] == true) {
        setState(() => _error = "That's a school email: you don't need an invite. Go back and sign in normally.");
      } else {
        setState(() => _claimed = true);
      }
    } catch (e) {
      setState(() => _error = friendlyAccountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() => (_busy = true, _error = null));
    try {
      await ref.read(repositoryProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAccountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signUp() async {
    final bad = PasswordRules.check(_pw.text, email: _email.text);
    if (_name.text.trim().length < 2) return setState(() => _error = 'Enter your name.');
    if (bad != null) return setState(() => _error = bad);
    setState(() => (_busy = true, _error = null));
    try {
      await ref.read(repositoryProvider).signUp(email: _email.text.trim(), password: _pw.text, fullName: _name.text.trim());
    } on EmailConfirmationNeeded {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.mark_email_read_rounded, size: 40),
            title: const Text('Check your email'),
            content: Text('We sent a link to ${_email.text.trim()}. Open it within 2 hours to finish joining.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAccountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    final signedIn = ref.watch(currentUserProvider).valueOrNull != null;
    final t = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: Brand.primaryGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: i == null
                        ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
                        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                            Text("You're invited to CampusLink",
                                style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            if (signedIn) ...[
                              const Text("You're already signed in."),
                              const SizedBox(height: 12),
                              FilledButton(onPressed: () => context.go('/home'), child: const Text('Open CampusLink')),
                            ] else if (i['valid'] != true) ...[
                              Text('${i['reason']}'),
                              const SizedBox(height: 6),
                              const Text('Ask the person who invited you for a new link.'),
                              const SizedBox(height: 12),
                              OutlinedButton(onPressed: () => context.go('/login'), child: const Text('Go to sign in')),
                            ] else ...[
                              Text(i['level'] == 'member'
                                  ? 'You can use CampusLink like a student. Others will see a "Guest" label next to your name.'
                                  : 'As a visitor you can read campus news, events and office information.'),
                              const SizedBox(height: 4),
                              Text(i['access_until'] == null
                                  ? 'Your access has no end date.'
                                  : 'Your access lasts until ${_date(i['access_until'])}.',
                                  style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                              if (i['email_hint'] != null)
                                Text('This invite is for ${i['email_hint']}.', style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _email,
                                enabled: !_claimed,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(labelText: 'Your email', hintText: 'Any email: Gmail, Outlook, Proton…'),
                              ),
                              if (!_claimed) ...[
                                const SizedBox(height: 12),
                                FilledButton(
                                    onPressed: _busy ? null : _claim,
                                    child: _busy
                                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Text('Continue')),
                              ] else ...[
                                const SizedBox(height: 12),
                                Text('Your place is saved for 2 hours. Now make your account with this exact email:',
                                    style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                                const SizedBox(height: 10),
                                if (!_usePassword)
                                  FilledButton.icon(
                                    onPressed: _busy ? null : _google,
                                    icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                                    label: const Text('Continue with Google'),
                                  ),
                                TextButton(
                                  onPressed: () => setState(() => _usePassword = !_usePassword),
                                  child: Text(_usePassword ? 'Use Google instead' : 'Use a password instead'),
                                ),
                                if (_usePassword) ...[
                                  TextField(controller: _name, decoration: const InputDecoration(labelText: 'Your name')),
                                  TextField(
                                    controller: _pw,
                                    obscureText: true,
                                    decoration: const InputDecoration(labelText: 'Password', helperText: '8+ characters, letters and numbers'),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton(onPressed: _busy ? null : _signUp, child: const Text('Create my account')),
                                ],
                              ],
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(_error!, style: TextStyle(color: t.colorScheme.error)),
                            ],
                          ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Super admin: make invite links, see who joined, end guests' access.
class InvitesAdminScreen extends StatefulWidget {
  const InvitesAdminScreen({super.key});
  @override
  State<InvitesAdminScreen> createState() => _InvitesAdminScreenState();
}

class _InvitesAdminScreenState extends State<InvitesAdminScreen> {
  final _api = AccountApi.instance;
  List<Map<String, dynamic>> _invites = [];
  List<Map<String, dynamic>> _guests = [];
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
      final r = await Future.wait([_api.invites(), _api.guests()]);
      setState(() => (_invites = r[0], _guests = r[1], _loading = false, _error = null));
    } catch (e) {
      setState(() => (_loading = false, _error = '$e'));
    }
  }

  Future<void> _create() async {
    final made = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _NewInviteSheet(),
    );
    if (made == null || !mounted) return;
    await _load();
    if (!mounted) return;
    final url = AccountApi.inviteUrl(made);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite link ready'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Copy or share it now. For safety it is shown only once.'),
          const SizedBox(height: 10),
          SelectableText(url, style: const TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (ctx.mounted) showSnack(ctx, 'Copied');
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => SharePlus.instance.share(ShareParams(text: "You're invited to CampusLink: $url")),
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }

  Future<void> _guestMenu(Map<String, dynamic> g, String action) async {
    try {
      switch (action) {
        case 'end':
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('End access for ${g['name']}?'),
              content: const Text('They are signed out within minutes and cannot sign in again.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('End access')),
              ],
            ),
          );
          if (ok == true) await _api.setGuestAccess('${g['id']}', endNow: true);
        case 'extend':
          final d = await showDatePicker(
            context: context,
            firstDate: DateTime.now().add(const Duration(days: 1)),
            lastDate: DateTime.now().add(const Duration(days: 730)),
            initialDate: DateTime.now().add(const Duration(days: 30)),
          );
          if (d != null) await _api.setGuestAccess('${g['id']}', until: DateTime(d.year, d.month, d.day, 23, 59));
        case 'forever':
          await _api.setGuestAccess('${g['id']}');
        case 'member':
        case 'visitor':
          await _api.setGuestLevel('${g['id']}', action);
      }
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final live = _invites.where((i) =>
        i['revoked_at'] == null && DateTime.parse('${i['link_expires_at']}').isAfter(DateTime.now()) && (i['uses'] as int) < (i['max_uses'] as int));
    return Scaffold(
      appBar: AppBar(title: const Text('Invites and guests')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _create, icon: const Icon(Icons.add_link_rounded), label: const Text('New invite')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: TextButton(onPressed: _load, child: const Text('Could not load. Retry')))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
                    Text('Invite people without a school email: parents, visiting lecturers, partners. '
                        'Each link has an end date and a limit, and you can cancel it any time.',
                        style: TextStyle(color: muted)),
                    const SizedBox(height: 16),
                    Text('Open links (${live.length})', style: Theme.of(context).textTheme.titleMedium),
                    if (live.isEmpty) Text('None.', style: TextStyle(color: muted)),
                    for (final i in live)
                      Card(
                        child: ListTile(
                          leading: Icon(i['kind'] == 'group' ? Icons.groups_rounded : Icons.person_rounded),
                          title: Text(i['note'] ?? (i['kind'] == 'group' ? 'Group link' : '${i['email']}')),
                          subtitle: Text([
                            i['access_level'] == 'member' ? 'Member' : 'Visitor',
                            '${i['uses']}/${i['max_uses']} joined',
                            'link ends ${_date(i['link_expires_at'])}',
                            i['access_until'] == null ? 'access: no end' : 'access until ${_date(i['access_until'])}',
                          ].join(' · ')),
                          trailing: IconButton(
                            tooltip: 'Cancel link',
                            icon: const Icon(Icons.link_off_rounded),
                            onPressed: () async {
                              await _api.revokeInvite('${i['id']}');
                              await _load();
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text('Guests (${_guests.length})', style: Theme.of(context).textTheme.titleMedium),
                    if (_guests.isEmpty) Text('Nobody has joined by invite yet.', style: TextStyle(color: muted)),
                    for (final g in _guests)
                      Card(
                        child: ListTile(
                          title: Text('${g['name']}'.isEmpty ? '${g['email']}' : '${g['name']}'),
                          subtitle: Text([
                            '${g['email']}',
                            g['access_level'] == 'member' ? 'Member' : 'Visitor',
                            g['access_until'] == null ? 'no end date' : 'until ${_date(g['access_until'])}',
                            if (g['invite_note'] != null) '${g['invite_note']}',
                          ].join(' · ')),
                          trailing: PopupMenuButton<String>(
                            onSelected: (a) => _guestMenu(g, a),
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'extend', child: Text('Change end date')),
                              const PopupMenuItem(value: 'forever', child: Text('No end date')),
                              PopupMenuItem(
                                  value: g['access_level'] == 'member' ? 'visitor' : 'member',
                                  child: Text(g['access_level'] == 'member' ? 'Make visitor (read only)' : 'Make member')),
                              const PopupMenuItem(value: 'end', child: Text('End access now')),
                            ],
                          ),
                        ),
                      ),
                  ]),
                ),
    );
  }
}

class _NewInviteSheet extends StatefulWidget {
  const _NewInviteSheet();
  @override
  State<_NewInviteSheet> createState() => _NewInviteSheetState();
}

class _NewInviteSheetState extends State<_NewInviteSheet> {
  bool _personal = true;
  final _email = TextEditingController();
  final _note = TextEditingController();
  String _level = 'visitor';
  int _people = 10;
  int _linkDays = 7;
  String _access = '30'; // days, or 'none'
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    setState(() => (_busy = true, _error = null));
    try {
      final t = await AccountApi.instance.createInvite(
        personal: _personal,
        email: _personal ? _email.text.trim() : null,
        level: _level,
        maxUses: _personal ? 1 : _people,
        linkDays: _personal ? _linkDays : _linkDays.clamp(1, 7),
        accessUntil: _access == 'none' ? null : DateTime.now().add(Duration(days: int.parse(_access))),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (mounted) Navigator.pop(context, t);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final linkChoices = _personal ? const [3, 7, 14, 30] : const [1, 3, 7];
    if (!linkChoices.contains(_linkDays)) _linkDays = linkChoices.last;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('New invite', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('One person'), icon: Icon(Icons.person_rounded)),
              ButtonSegment(value: false, label: Text('A group'), icon: Icon(Icons.groups_rounded)),
            ],
            selected: {_personal},
            onSelectionChanged: (s) => setState(() => _personal = s.first),
          ),
          const SizedBox(height: 12),
          if (_personal)
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Their email', helperText: 'Only this email can use the link.'),
            )
          else
            DropdownButtonFormField<int>(
              initialValue: _people,
              decoration: const InputDecoration(labelText: 'How many people', helperText: 'At most 50. A leaked link can let in only this many.'),
              items: [for (final n in const [5, 10, 20, 30, 50]) DropdownMenuItem(value: n, child: Text('$n people'))],
              onChanged: (v) => setState(() => _people = v ?? 10),
            ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'visitor', label: Text('Visitor'), icon: Icon(Icons.visibility_rounded)),
              ButtonSegment(value: 'member', label: Text('Member'), icon: Icon(Icons.how_to_reg_rounded)),
            ],
            selected: {_level},
            onSelectionChanged: (s) => setState(() => _level = s.first),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _level == 'visitor'
                  ? 'Reads news, events and office info. Cannot post, join, message or see students.'
                  : 'Uses CampusLink like a student, with a Guest label.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _linkDays,
            decoration: const InputDecoration(labelText: 'Link works for'),
            items: [for (final d in linkChoices) DropdownMenuItem(value: d, child: Text('$d day${d == 1 ? '' : 's'}'))],
            onChanged: (v) => setState(() => _linkDays = v ?? 7),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _access,
            decoration: const InputDecoration(labelText: 'Their access lasts'),
            items: const [
              DropdownMenuItem(value: '1', child: Text('1 day')),
              DropdownMenuItem(value: '7', child: Text('1 week')),
              DropdownMenuItem(value: '30', child: Text('1 month')),
              DropdownMenuItem(value: '120', child: Text('1 semester (4 months)')),
              DropdownMenuItem(value: '365', child: Text('1 year')),
              DropdownMenuItem(value: 'none', child: Text('No end (like a student)')),
            ],
            onChanged: (v) => setState(() => _access = v ?? '30'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _note, maxLength: 200, decoration: const InputDecoration(labelText: 'Note for you (e.g. "Parents day")')),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _make,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Make invite link'),
          ),
        ]),
      ),
    );
  }
}
