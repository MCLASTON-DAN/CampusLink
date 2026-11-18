import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/community_models.dart';
import '../../data/community_repository.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';
import 'news_screen.dart';

String countdownText(DateTime start, DateTime now) {
  final d = start.difference(now);
  if (d.isNegative) return 'Started';
  if (d.inDays >= 1) return 'in ${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours >= 1) return 'in ${d.inHours}h ${d.inMinutes % 60}m';
  return 'in ${d.inMinutes}m';
}

/// Ticks once a minute so countdowns stay right.
class Countdown extends StatefulWidget {
  const Countdown(this.start, {super.key, this.style});
  final DateTime start;
  final TextStyle? style;
  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(countdownText(widget.start, DateTime.now()), style: widget.style);
}

/// Home banner: major events from 24h before start, max 2.
class FeaturedEventsBanner extends ConsumerWidget {
  const FeaturedEventsBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(featuredEventsProvider).valueOrNull ?? const <CampusEvent>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      for (final e in list.take(2))
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: ListTile(
            onTap: () => context.push('/events/${e.id}'),
            leading: const Icon(Icons.campaign_rounded),
            title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${eventDate(e.startsAt)} · ${e.location ?? 'Online'}'),
            trailing: Countdown(e.startsAt, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
    ]);
  }
}

final _eventListProvider = FutureProvider.autoDispose((ref) => ref.watch(repositoryProvider).events());

class EventsListScreen extends ConsumerWidget {
  const EventsListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    final mems = ref.watch(myMembershipsProvider).valueOrNull ?? [];
    final canPost = mems.any((m) => m.isActive && m.can('events'));
    return Scaffold(
      appBar: AppBar(title: const Text('Events'), actions: [
        if (me?.isSuperAdmin ?? false)
          IconButton(
              tooltip: 'Major event requests',
              icon: const Icon(Icons.approval_rounded),
              onPressed: () => context.push('/events/requests')),
      ]),
      floatingActionButton: canPost
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/events/new');
                ref.invalidate(_eventListProvider);
              },
              icon: const Icon(Icons.add),
              label: const Text('Event'))
          : null,
      body: AsyncBody(
        value: ref.watch(_eventListProvider),
        onRetry: () => ref.invalidate(_eventListProvider),
        builder: (list) {
          final now = DateTime.now();
          final up = list.where((e) => e.status == 'published' && e.startsAt.isAfter(now.subtract(const Duration(hours: 3)))).toList()
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
          if (up.isEmpty) return const EmptyState(icon: Icons.event_busy_rounded, title: 'No upcoming events');
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
            itemCount: up.length,
            itemBuilder: (_, i) {
              final e = up[i];
              return Card(
                child: ListTile(
                  onTap: () => context.push('/events/${e.id}'),
                  title: Row(children: [
                    Flexible(child: Text(e.title, overflow: TextOverflow.ellipsis)),
                    if (e.isMajor) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.star_rounded, color: Colors.amber, size: 18)),
                  ]),
                  subtitle: Text('${eventDate(e.startsAt)}\n${e.publisherName}'),
                  isThreeLine: true,
                  trailing: Countdown(e.startsAt, style: Theme.of(context).textTheme.labelMedium),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final String eventId;
  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailState();
}

class _EventDetailState extends ConsumerState<EventDetailScreen> {
  CampusEvent? _e;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    ref.read(communityProvider).event(widget.eventId).then((e) {
      if (mounted) setState(() {
        _e = e;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    final me = ref.watch(currentUserProvider).valueOrNull;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Event')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : e == null
              ? const EmptyState(icon: Icons.search_off_rounded, title: 'Event not found')
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text(e.title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  NameWithBadge('By ${e.publisherName}', e.badge, style: t.titleSmall),
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.schedule_rounded),
                      title: Text(eventDate(e.startsAt)),
                      subtitle: Text(e.location ?? 'Online'),
                      trailing: Countdown(e.startsAt, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  if (e.isMajor) const Padding(padding: EdgeInsets.only(top: 4), child: StatusChip('Major event · approved by the super admin', color: Colors.amber)),
                  if ((e.topic ?? '').isNotEmpty) ...[const SizedBox(height: 12), Text('What it is about', style: t.titleSmall), Text(e.topic!)],
                  if ((e.impact ?? '').isNotEmpty) ...[const SizedBox(height: 12), Text('How it helps you', style: t.titleSmall), Text(e.impact!)],
                  if (e.description.isNotEmpty) ...[const SizedBox(height: 12), Text(e.description)],
                  if (e.speakers.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Speakers & panel', style: t.titleMedium),
                    for (final s in e.speakers)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                            backgroundImage: (s.photoUrl ?? '').isEmpty ? null : NetworkImage(s.photoUrl!),
                            child: (s.photoUrl ?? '').isEmpty ? Text(s.name.isEmpty ? '?' : s.name[0]) : null),
                        title: Text(s.name),
                        subtitle: Text([s.roleLabel, if ((s.title ?? '').isNotEmpty) s.title!].join(' · ')),
                      ),
                  ],
                  if ((e.onlineUrl ?? '').isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: FilledButton.icon(
                            onPressed: () => launchUrl(Uri.parse(e.onlineUrl!)),
                            icon: const Icon(Icons.video_call_rounded),
                            label: const Text('Join online'))),
                  const SizedBox(height: 8),
                  Reactions(
                      targetType: 'event',
                      targetId: e.id,
                      likes: e.likes,
                      liked: e.likedByMe,
                      canRemove: me?.isSuperAdmin ?? false,
                      onRemoved: () => context.pop()),
                  const Divider(height: 28),
                  CommentsSection(targetType: 'event', targetId: e.id),
                ]),
    );
  }
}

class ComposeEventScreen extends ConsumerStatefulWidget {
  const ComposeEventScreen({super.key});
  @override
  ConsumerState<ComposeEventScreen> createState() => _ComposeEventState();
}

class _ComposeEventState extends ConsumerState<ComposeEventScreen> {
  final _title = TextEditingController(), _topic = TextEditingController(), _impact = TextEditingController();
  final _loc = TextEditingController(), _url = TextEditingController(), _reason = TextEditingController();
  final _speakers = <List<TextEditingController>>[];
  DateTime _start = DateTime.now().add(const Duration(days: 3));
  bool _major = false, _busy = false;
  Membership? _mem;

  Future<void> _pick() async {
    final d = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t == null) return;
    setState(() => _start = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final mems = (ref.watch(myMembershipsProvider).valueOrNull ?? []).where((m) => m.isActive && m.can('events')).toList();
    if (mems.isEmpty) {
      return Scaffold(appBar: AppBar(title: const Text('New event')), body: const EmptyState(icon: Icons.lock_outline, title: 'Only office holders can add events'));
    }
    _mem ??= mems.first;
    return Scaffold(
      appBar: AppBar(title: const Text('New event')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (mems.length > 1)
          DropdownButtonFormField<Membership>(
            initialValue: _mem,
            decoration: const InputDecoration(labelText: 'Posting as'),
            items: [for (final m in mems) DropdownMenuItem(value: m, child: Text('${m.positionTitle} · ${m.publisherName}'))],
            onChanged: (v) => setState(() => _mem = v),
          ),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Event name')),
        const SizedBox(height: 8),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.schedule), title: Text(eventDate(_start)), trailing: TextButton(onPressed: _pick, child: const Text('Change'))),
        TextField(controller: _loc, decoration: const InputDecoration(labelText: 'Where (leave empty if online only)')),
        const SizedBox(height: 8),
        TextField(controller: _url, decoration: const InputDecoration(labelText: 'Online link (optional)')),
        const SizedBox(height: 8),
        TextField(controller: _topic, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'What is it about?')),
        const SizedBox(height: 8),
        TextField(controller: _impact, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'How does it help students?')),
        const SizedBox(height: 12),
        Text('Speakers & panel', style: Theme.of(context).textTheme.titleSmall),
        for (final s in _speakers)
          Row(children: [
            Expanded(child: TextField(controller: s[0], decoration: const InputDecoration(labelText: 'Name'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: s[1], decoration: const InputDecoration(labelText: 'Title'))),
          ]),
        TextButton.icon(
            onPressed: () => setState(() => _speakers.add([TextEditingController(), TextEditingController()])),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add speaker')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _major,
          onChanged: (v) => setState(() => _major = v),
          title: const Text('Ask for "Major event" status'),
          subtitle: const Text('Shows on everyone\'s home screen 24h before. Only 2 at a time. The super admin decides.'),
        ),
        if (_major) TextField(controller: _reason, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Why is it major? (30+ letters)')),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Publish event')),
      ]),
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().length < 4) return showSnack(context, 'Give the event a name.');
    if (_loc.text.trim().isEmpty && _url.text.trim().isEmpty) return showSnack(context, 'Add a place or an online link.');
    if (_major && _reason.text.trim().length < 30) return showSnack(context, 'Explain why it is major (30+ letters).');
    setState(() => _busy = true);
    try {
      await ref.read(communityProvider).createEvent(CampusEvent(
            id: '',
            title: _title.text,
            startsAt: _start,
            location: _loc.text.trim().isEmpty ? null : _loc.text.trim(),
            publisherId: _mem!.publisherId,
            publisherName: _mem!.publisherName,
            topic: _topic.text,
            impact: _impact.text,
            onlineUrl: _url.text.trim(),
            majorStatus: _major ? 'requested' : 'none',
            majorReason: _major ? _reason.text.trim() : null,
            speakers: [
              for (final s in _speakers.where((s) => s[0].text.trim().isNotEmpty))
                EventSpeaker(id: '', name: s[0].text.trim(), title: s[1].text.trim(), role: 'guest'),
            ],
          ));
      if (mounted) context.pop();
    } on CommunityException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
    if (mounted) setState(() => _busy = false);
  }
}

class MajorRequestsScreen extends ConsumerWidget {
  const MajorRequestsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(communityProvider);
    Future<void> decide(CampusEvent e, String s) async {
      try {
        await api.setMajorStatus(e.id, s);
        ref.invalidate(majorRequestsProvider);
        ref.invalidate(featuredEventsProvider);
      } on CommunityException catch (x) {
        if (context.mounted) showSnack(context, x.message);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Major event requests')),
      body: AsyncBody(
        value: ref.watch(majorRequestsProvider),
        builder: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.inbox_rounded, title: 'No requests waiting')
            : ListView(padding: const EdgeInsets.all(12), children: [
                for (final e in list)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.title, style: Theme.of(context).textTheme.titleMedium),
                        Text('${e.publisherName} · ${eventDate(e.startsAt)}'),
                        const SizedBox(height: 6),
                        Text('Reason: ${e.majorReason ?? '-'}'),
                        const SizedBox(height: 8),
                        Row(children: [
                          FilledButton(onPressed: () => decide(e, 'approved'), child: const Text('Approve')),
                          const SizedBox(width: 8),
                          OutlinedButton(onPressed: () => decide(e, 'rejected'), child: const Text('Reject')),
                        ]),
                      ]),
                    ),
                  ),
              ]),
      ),
    );
  }
}
