import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/confirm_send.dart';
import '../community/social.dart';

/// "Seen by" numbers for a set of announcements (only authors and staff get rows back).
final _seenProvider = FutureProvider.autoDispose.family<Map<String, (int, DateTime?)>, String>(
    (ref, key) => key.isEmpty ? Future.value(const {}) : SocialApi.instance.seenCounts(key.split(',')));

/// Announcements already marked as seen in this session, so we tell the server once.
final _recorded = <String>{};

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  String _filter = 'all';

  /// "For me" keeps notices that target everyone or match the user's year/faculty/programme.
  bool _forMe(Announcement a, Profile? u) {
    if (a.audience == 'all' || u == null) return true;
    final parts = a.audience.split(':');
    if (parts.length != 2) return true;
    return switch (parts[0]) {
      'year' => u.yearOfStudy?.toString() == parts[1],
      'faculty' => u.faculty == parts[1],
      'programme' => u.programme == parts[1],
      _ => true,
    };
  }

  /// Tells the server which notices this person has now seen (after the frame, once each).
  void _markSeen(List<Announcement> shown) {
    if (!SocialApi.instance.live) return;
    final fresh = [for (final a in shown) if (!_recorded.contains(a.id)) a.id];
    if (fresh.isEmpty) return;
    _recorded.addAll(fresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SocialApi.instance.recordAnnouncementViews(fresh).catchError((_) => _recorded.removeAll(fresh));
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final data = ref.watch(announcementsProvider);
    final categories = ['all', 'for me', 'academic', 'finance', 'events', 'welfare', 'general'];

    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: user?.isStaff == true
          ? FloatingActionButton.extended(
              onPressed: () => _compose(context),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Post'),
            )
          : null,
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = categories[i];
                final sel = c == _filter;
                return ChoiceChip(
                  label: Text(c[0].toUpperCase() + c.substring(1)),
                  selected: sel,
                  onSelected: (_) => setState(() => _filter = c),
                );
              },
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: data,
              onRetry: () => ref.invalidate(announcementsProvider),
              builder: (list) {
                final shown = list.where((a) {
                  if (_filter == 'all') return true;
                  if (_filter == 'for me') return _forMe(a, user);
                  return a.category == _filter;
                }).toList();
                if (shown.isEmpty) {
                  return const EmptyState(icon: Icons.campaign_rounded, title: 'Nothing here yet');
                }
                _markSeen(shown);
                final seenKey = user?.isStaff == true && SocialApi.instance.live ? (shown.map((a) => a.id).toList()..sort()).join(',') : '';
                final seen = ref.watch(_seenProvider(seenKey)).valueOrNull ?? const {};
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(announcementsProvider);
                    ref.invalidate(_seenProvider);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _AnnouncementCard(shown[i], seen: seen[shown[i].id]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _compose(BuildContext context) async {
    final title = TextEditingController();
    final body = TextEditingController();
    var category = 'general';
    var audience = 'all';
    var pinned = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('New announcement'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
                const SizedBox(height: 10),
                TextField(controller: body, maxLines: 4, decoration: const InputDecoration(labelText: 'Message')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: [for (final c in ['general', 'academic', 'finance', 'events', 'welfare']) DropdownMenuItem(value: c, child: Text(c))],
                      onChanged: (v) => setS(() => category = v ?? 'general'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: audience,
                      decoration: const InputDecoration(labelText: 'Audience'),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Everyone')),
                        DropdownMenuItem(value: 'year:1', child: Text('Year 1')),
                        DropdownMenuItem(value: 'faculty:FST', child: Text('FST')),
                      ],
                      onChanged: (v) => setS(() => audience = v ?? 'all'),
                    ),
                  ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pin to top'),
                  value: pinned,
                  onChanged: (v) => setS(() => pinned = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Post')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty || !mounted) return;
    if (!await confirmBeforeSending(context,
        title: title.text.trim(),
        preview: body.text.trim(),
        reach: 'Everyone on CampusLink. It is an official announcement.',
        sendLabel: 'Post')) {
      return;
    }
    if (!mounted) return;
    await ref.read(repositoryProvider).postAnnouncement(Announcement(
          id: const Uuid().v4(),
          title: title.text.trim(),
          body: body.text.trim(),
          category: category,
          audience: audience,
          isPinned: pinned,
          createdAt: DateTime.now(),
        ));
    ref.invalidate(announcementsProvider);
    if (!mounted) return;
    showSnack(this.context, 'Announcement posted');
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard(this.a, {this.seen});
  final Announcement a;
  final (int, DateTime?)? seen;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(a.category);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusChip(a.category, color: color),
                if (a.audience != 'all') ...[
                  const SizedBox(width: 6),
                  StatusChip(a.audience.replaceAll(':', ' '), color: Brand.violet),
                ],
                const Spacer(),
                if (a.isPinned) const Icon(Icons.push_pin_rounded, size: 16, color: Brand.coral),
                const SizedBox(width: 6),
                TimeStamp(a.createdAt),
              ],
            ),
            if (a.isRetracted) RetractedBanner(word: 'Retracted', reason: a.retractReason),
            const SizedBox(height: 10),
            Text(a.title,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16, decoration: a.isRetracted ? TextDecoration.lineThrough : null)),
            const SizedBox(height: 6),
            Opacity(
              opacity: a.isRetracted ? 0.55 : 1,
              child: Text(a.body, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4)),
            ),
            EditedMark(a.editedAt),
            if (seen != null) _SeenRow(a, seen!),
            if (!a.isRetracted) _RetractButton(a),
          ],
        ),
      ),
    );
  }
}

/// "Seen by N" for staff, plus a one-time nudge to everyone who has not opened it yet.
class _SeenRow extends ConsumerStatefulWidget {
  const _SeenRow(this.a, this.seen);
  final Announcement a;
  final (int, DateTime?) seen;
  @override
  ConsumerState<_SeenRow> createState() => _SeenRowState();
}

class _SeenRowState extends ConsumerState<_SeenRow> {
  bool _busy = false;
  DateTime? _sentAt;

  Future<void> _remind() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remind people?'),
        content: const Text('Everyone it was meant for who has not opened it gets one alert. You can only do this once per announcement.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send reminder')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final n = await SocialApi.instance.remindAnnouncement(widget.a.id);
      if (!mounted) return;
      setState(() => _sentAt = DateTime.now());
      showSnack(context, n == 0 ? 'Everyone has already seen it.' : 'Reminder sent to $n ${n == 1 ? 'person' : 'people'}.');
    } catch (e) {
      if (mounted) showSnack(context, '$e'.contains('already') ? 'A reminder was already sent.' : 'Could not send the reminder.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    final (n, remindedAt) = widget.seen;
    final when = _sentAt ?? remindedAt;
    final canRemind = !widget.a.isRetracted && me != null && (me.isSuperAdmin || me.id == widget.a.authorId);
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        const Icon(Icons.visibility_outlined, size: 16),
        const SizedBox(width: 4),
        Text('Seen by $n', style: style),
        const Spacer(),
        if (when != null)
          Text('Reminded ${friendlyDate(when)}', style: style)
        else if (canRemind)
          TextButton.icon(
            onPressed: _busy ? null : _remind,
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: const Text("Remind those who haven't seen it"),
          ),
      ]),
    );
  }
}

/// The author or the super admin can retract a wrong announcement (with a public reason).
class _RetractButton extends ConsumerWidget {
  const _RetractButton(this.a);
  final Announcement a;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    if (me == null || !(me.isSuperAdmin || me.id == a.authorId)) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        icon: const Icon(Icons.report_rounded, size: 18),
        label: const Text('Retract'),
        onPressed: () async {
          final why = await askReason(context, title: 'Retract this announcement?', hint: 'e.g. The deadline is 5 Dec, not 3 Dec.');
          if (why == null) return;
          try {
            await ref.read(repositoryProvider).retractAnnouncement(a.id, why);
            ref.invalidate(announcementsProvider);
          } catch (e) {
            if (context.mounted) showSnack(context, '$e'.replaceFirst('Exception: ', '').replaceFirst(RegExp(r'^.*?: '), ''));
          }
        },
      ),
    );
  }
}
