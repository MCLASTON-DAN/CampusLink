import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/community_models.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// "I'm going", your entry ticket (QR + code), Add to calendar, and for the
/// organising office a check-in scanner.
class EventRsvpPanel extends ConsumerStatefulWidget {
  const EventRsvpPanel({super.key, required this.event});
  final CampusEvent event;
  @override
  ConsumerState<EventRsvpPanel> createState() => _EventRsvpPanelState();
}

class _EventRsvpPanelState extends ConsumerState<EventRsvpPanel> {
  Rsvp? _mine;
  (int, int) _counts = (0, 0);
  bool _loading = true;
  bool _busy = false;

  CampusEvent get e => widget.event;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(communityProvider);
    try {
      final r = await Future.wait([api.myRsvp(e.id), api.rsvpCounts([e.id])]);
      if (!mounted) return;
      setState(() {
        _mine = r[0] as Rsvp?;
        _counts = (r[1] as Map<String, (int, int)>)[e.id] ?? (0, 0);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _toggle() async {
    setState(() => _busy = true);
    final api = ref.read(communityProvider);
    try {
      if (_mine == null) {
        final r = await api.rsvp(e.id);
        if (!mounted) return;
        setState(() {
          _mine = r;
          _counts = (_counts.$1 + 1, _counts.$2);
        });
        _say('You\'re going. Show your ticket at the door.');
      } else {
        await api.cancelRsvp(e.id);
        if (!mounted) return;
        setState(() {
          _mine = null;
          _counts = (_counts.$1 > 0 ? _counts.$1 - 1 : 0, _counts.$2);
        });
      }
    } catch (err) {
      if (mounted) _say('$err'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens Google Calendar with the event filled in (works on every device).
  Future<void> _addToCalendar() async {
    String fmt(DateTime d) => '${DateFormat("yyyyMMdd'T'HHmmss").format(d.toUtc())}Z';
    final end = e.endsAt ?? e.startsAt.add(const Duration(hours: 2));
    final details = [
      if (e.description.isNotEmpty) e.description,
      if ((e.onlineUrl ?? '').isNotEmpty) 'Join: ${e.onlineUrl}',
      'From CampusLink',
    ].join('\n\n');
    final uri = Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': e.title,
      'dates': '${fmt(e.startsAt)}/${fmt(end)}',
      'details': details,
      'location': e.location ?? (e.onlineUrl ?? 'Online'),
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showTicket() {
    final r = _mine!;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Your ticket', style: Theme.of(sheet).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(e.title, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(data: 'campuslink:checkin:${e.id}:${r.code}', size: 220),
            ),
            const SizedBox(height: 12),
            SelectableText(r.code,
                style: Theme.of(sheet).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 6)),
            const SizedBox(height: 8),
            Text(
              r.checkedInAt == null
                  ? 'Show this at the door. The organiser scans it, or types the code.'
                  : 'Checked in at ${DateFormat('HH:mm').format(r.checkedInAt!.toLocal())}. Enjoy!',
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    final past = e.startsAt.isBefore(DateTime.now().subtract(const Duration(hours: 6)));
    final mems = ref.watch(myMembershipsProvider).valueOrNull ?? const <Membership>[];
    final me = ref.watch(currentUserProvider).valueOrNull;
    final organiser = mems.any((m) => m.isActive && m.publisherId == e.publisherId && m.can('events')) || (me?.isSuperAdmin ?? false);
    final going = _counts.$1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.groups_rounded, color: s.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _loading ? '…' : going == 0 ? 'Be the first to say you\'re going' : '$going going${_counts.$2 > 0 ? ' · ${_counts.$2} checked in' : ''}',
                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (!past)
              _mine == null
                  ? FilledButton.icon(
                      onPressed: _busy || _loading ? null : _toggle,
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('I\'m going'),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: _showTicket,
                      icon: const Icon(Icons.qr_code_2_rounded),
                      label: const Text('My ticket'),
                    ),
            OutlinedButton.icon(
              onPressed: _addToCalendar,
              icon: const Icon(Icons.event_available_rounded),
              label: const Text('Add to calendar'),
            ),
            if (_mine != null && _mine!.checkedInAt == null && !past)
              TextButton(onPressed: _busy ? null : _toggle, child: const Text('Can\'t go any more')),
            if (organiser)
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CheckInScreen(event: e),
                  fullscreenDialog: true,
                )).then((_) => _load()),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Check people in'),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// For the organising office: scan tickets, or type the 6-character code.
class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key, required this.event});
  final CampusEvent event;
  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  final _code = TextEditingController();
  final _done = <String>[];
  String? _last;
  bool _busy = false;
  DateTime _lastScan = DateTime(2000);
  bool _camera = true;

  Future<void> _submit(String raw) async {
    var code = raw.trim();
    // QR holds "campuslink:checkin:<event id>:<code>".
    if (code.startsWith('campuslink:checkin:')) {
      final parts = code.split(':');
      if (parts.length != 4 || parts[2] != widget.event.id) {
        setState(() => _last = 'That ticket is for a different event.');
        return;
      }
      code = parts[3];
    }
    if (code.length < 4 || _busy) return;
    setState(() => _busy = true);
    try {
      final msg = await ref.read(communityProvider).checkIn(widget.event.id, code);
      if (!mounted) return;
      setState(() {
        _last = '✅ $msg';
        _done.insert(0, msg);
        _code.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _last = '⚠️ ${'$e'.replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Check people in'), actions: [
        IconButton(
          tooltip: _camera ? 'Type codes instead' : 'Use the camera',
          icon: Icon(_camera ? Icons.keyboard_rounded : Icons.qr_code_scanner_rounded),
          onPressed: () => setState(() => _camera = !_camera),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.event.title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (_camera)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 280,
              child: MobileScanner(
                onDetect: (cap) {
                  final v = cap.barcodes.firstOrNull?.rawValue;
                  // Ignore the same ticket being seen many times a second.
                  if (v == null || DateTime.now().difference(_lastScan).inMilliseconds < 1500) return;
                  _lastScan = DateTime.now();
                  _submit(v);
                },
                errorBuilder: (context, error) => Container(
                  color: Colors.black12,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(16),
                  child: const Text('Camera not available. Tap the keyboard icon to type codes.', textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Or type the 6-character code', counterText: ''),
              onSubmitted: _submit,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : () => _submit(_code.text), child: const Text('Check in')),
        ]),
        if (_last != null) ...[
          const SizedBox(height: 12),
          Text(_last!, style: t.titleSmall),
        ],
        if (_done.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Checked in now (${_done.length})', style: t.labelLarge),
          for (final d in _done) ListTile(dense: true, leading: const Icon(Icons.check_rounded), title: Text(d)),
        ],
      ]),
    );
  }
}
