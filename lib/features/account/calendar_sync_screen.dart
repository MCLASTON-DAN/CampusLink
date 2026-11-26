import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'account_api.dart';

/// "Put CampusLink in my calendar".
///
/// Why a subscription link and not "write into Google Calendar"? Writing into
/// a school Google Calendar needs a sensitive Google permission, a Google
/// review, and can be blocked by the university's IT. A private link works
/// today with Google, Outlook and Apple Calendar, updates by itself, and the
/// student can switch it off at any time.
class CalendarSyncScreen extends StatefulWidget {
  const CalendarSyncScreen({super.key});
  @override
  State<CalendarSyncScreen> createState() => _CalendarSyncScreenState();
}

class _CalendarSyncScreenState extends State<CalendarSyncScreen> {
  final _api = AccountApi.instance;
  CalendarFeedInfo? _info;
  String? _token;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_api.available) return setState(() => _loading = false);
    try {
      final info = await _api.feedInfo();
      final t = info == null ? null : await _api.savedFeedToken();
      if (mounted) setState(() => (_info = info, _token = t, _loading = false, _error = null));
    } catch (e) {
      if (mounted) setState(() => (_loading = false, _error = friendlyAccountError(e)));
    }
  }

  Future<void> _make() async {
    setState(() => _busy = true);
    try {
      final t = await _api.createFeed();
      final info = await _api.feedInfo();
      if (mounted) setState(() => (_token = t, _info = info));
    } catch (e) {
      if (mounted) showSnack(context, friendlyAccountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOff() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off the calendar link?'),
        content: const Text('Your calendar app will stop getting CampusLink updates. '
            'Old entries may stay until you remove the CampusLink calendar there.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Turn off')),
        ],
      ),
    );
    if (ok != true) return;
    await _api.deleteFeed();
    if (mounted) setState(() => (_info = null, _token = null));
  }

  Future<void> _parts({bool? events, bool? classes, bool? exams}) async {
    final i = _info!;
    final next = CalendarFeedInfo(
        events: events ?? i.events, classes: classes ?? i.classes, exams: exams ?? i.exams, lastFetched: i.lastFetched);
    setState(() => _info = next);
    try {
      await _api.setFeedParts(events: next.events, classes: next.classes, exams: next.exams);
    } catch (e) {
      if (mounted) {
        setState(() => _info = i);
        showSnack(context, friendlyAccountError(e));
      }
    }
  }

  String get _https => AccountApi.feedUrl(_token!);
  String get _webcal => _https.replaceFirst(RegExp('^https://'), 'webcal://');

  Future<void> _open(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      if (mounted) showSnack(context, 'Could not open it. Use "Copy link" instead.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('My calendar')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(gradient: Brand.oceanGradient, borderRadius: BorderRadius.circular(20)),
                  child: const Row(children: [
                    Icon(Icons.event_available_rounded, color: Colors.white, size: 36),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'See your classes, exams and campus events inside Google Calendar, '
                        'Outlook or your phone calendar. It updates by itself.',
                        style: TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                if (!_api.available)
                  const Card(child: ListTile(title: Text('Calendar sync works in the live app, not in demo mode.')))
                else if (_error != null)
                  Card(
                      child: ListTile(
                          title: Text(_error!), trailing: TextButton(onPressed: _load, child: const Text('Retry'))))
                else if (_info == null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const Text('How it works', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text('1. Make your private link.\n2. Tap "Add to Google Calendar" (or Apple / Outlook).\n'
                            '3. Done. New events you join show up within a few hours.',
                            style: TextStyle(color: muted, height: 1.5)),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _busy ? null : _make,
                          icon: const Icon(Icons.link_rounded),
                          label: const Text('Make my calendar link'),
                        ),
                      ]),
                    ),
                  )
                else ...[
                  if (_token == null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('Your link was made on another device'),
                        subtitle: const Text('For safety the link is not stored. Make a new one here: '
                            'the old one stops working, so add the new one to your calendar again.'),
                        trailing: TextButton(onPressed: _busy ? null : _make, child: const Text('New link')),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          FilledButton.icon(
                            icon: const Icon(Icons.calendar_month_rounded),
                            label: const Text('Add to Google Calendar'),
                            onPressed: () => _open(
                                'https://calendar.google.com/calendar/render?cid=${Uri.encodeComponent(_webcal)}'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.phone_iphone_rounded),
                            label: const Text('Apple Calendar / Outlook'),
                            onPressed: () => _open(_webcal),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copy link'),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: _https));
                              if (context.mounted) showSnack(context, 'Link copied. Keep it private: it shows your timetable.');
                            },
                          ),
                          const SizedBox(height: 4),
                          Text('Use your school Google account in Google Calendar to keep school things together.',
                              style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.celebration_rounded),
                        title: const Text('Campus events'),
                        subtitle: const Text("Ones you're going to, plus major campus events"),
                        value: _info!.events,
                        onChanged: (v) => _parts(events: v),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.schedule_rounded),
                        title: const Text('My classes'),
                        subtitle: const Text('From your timetable, every week this semester'),
                        value: _info!.classes,
                        onChanged: (v) => _parts(classes: v),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.edit_note_rounded),
                        title: const Text('My exams'),
                        subtitle: const Text('With a reminder the day before'),
                        value: _info!.exams,
                        onChanged: (v) => _parts(exams: v),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(_info!.lastFetched == null
                        ? 'Not added to a calendar yet'
                        : 'Your calendar last updated ${DateFormat('d MMM, HH:mm').format(_info!.lastFetched!)}'),
                    subtitle: const Text('Calendar apps check for changes every few hours.'),
                  ),
                  TextButton(onPressed: _busy ? null : _make, child: const Text('Link shared by mistake? Make a new one')),
                  TextButton(
                    onPressed: _turnOff,
                    style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    child: const Text('Turn off calendar link'),
                  ),
                ],
              ],
            ),
    );
  }
}
