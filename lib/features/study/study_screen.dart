import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key});

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  String _q = '';

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tutors & study groups'),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Find a tutor'), Tab(text: 'Study groups')]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGroup,
        icon: const Icon(Icons.group_add_rounded),
        label: const Text('New group'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.toLowerCase()),
              decoration: const InputDecoration(hintText: 'Search a subject or course code…', prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_TutorsTab(query: _q), _GroupsTab(query: _q)],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createGroup() async {
    final name = TextEditingController();
    final code = TextEditingController();
    final desc = TextEditingController();
    final time = TextEditingController();
    final place = TextEditingController();
    var invite = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        title: const Text('Start a study group'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Group name')),
            const SizedBox(height: 10),
            TextField(controller: code, decoration: const InputDecoration(labelText: 'Course code', hintText: 'BDA2207')),
            const SizedBox(height: 10),
            TextField(controller: desc, decoration: const InputDecoration(labelText: 'What will you work on?')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: time, decoration: const InputDecoration(labelText: 'When', hintText: 'Tue 16:00'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: place, decoration: const InputDecoration(labelText: 'Where'))),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Invite only'),
              subtitle: const Text('People ask to join and you approve them.'),
              value: invite,
              onChanged: (v) => setS(() => invite = v),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      )),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final uid = ref.read(repositoryProvider).currentUserSync?.id;
    await ref.read(repositoryProvider).createStudyGroup(StudyGroup(
          id: const Uuid().v4(),
          name: name.text.trim(),
          courseCode: code.text.trim().toUpperCase(),
          description: desc.text.trim(),
          meetingTime: time.text.trim(),
          location: place.text.trim(),
          ownerId: uid,
          memberIds: uid == null ? [] : [uid],
          privacy: invite ? 'invite' : 'open',
        ));
    ref.invalidate(studyGroupsProvider);
    if (mounted) {
      _tabs.animateTo(1);
      showSnack(context, 'Group created');
    }
  }
}

class _TutorsTab extends ConsumerWidget {
  const _TutorsTab({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(tutorsProvider);
    return AsyncBody(
      value: data,
      onRetry: () => ref.invalidate(tutorsProvider),
      builder: (list) {
        final shown = list
            .where((t) => query.isEmpty ||
                t.fullName.toLowerCase().contains(query) ||
                t.tutorSubjects.any((s) => s.toLowerCase().contains(query)))
            .toList();
        if (shown.isEmpty) {
          return const EmptyState(icon: Icons.person_search_rounded, title: 'No tutor for that yet',
              subtitle: 'Try another subject, or start a study group instead.');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          itemCount: shown.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final t = shown[i];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Brand.violet.withValues(alpha: 0.15),
                      child: Text(t.fullName.split(' ').map((w) => w[0]).take(2).join(),
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.violet)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.fullName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          Text('${t.programme ?? ''} · Year ${t.yearOfStudy ?? '-'}', style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            for (final s in t.tutorSubjects) StatusChip(s, color: Brand.teal),
                          ]),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => showSnack(context, 'Request sent to ${t.fullName.split(' ').first}. They will reply in the app.'),
                      child: const Text('Ask'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GroupsTab extends ConsumerWidget {
  const _GroupsTab({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(studyGroupsProvider);
    final uid = ref.watch(currentUserProvider).valueOrNull?.id;
    final pending = ref.watch(_pendingProvider).valueOrNull ?? const <String>{};
    return AsyncBody(
      value: data,
      onRetry: () => ref.invalidate(studyGroupsProvider),
      builder: (list) {
        final shown = list
            .where((g) => query.isEmpty ||
                g.name.toLowerCase().contains(query) ||
                g.courseCode.toLowerCase().contains(query))
            .toList();
        if (shown.isEmpty) {
          return const EmptyState(icon: Icons.groups_rounded, title: 'No groups found', subtitle: 'Be the first to start one!');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          itemCount: shown.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final g = shown[i];
            final joined = uid != null && g.memberIds.contains(uid);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      StatusChip(g.courseCode, color: Brand.indigo),
                      if (g.inviteOnly) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.lock_outline_rounded, size: 16),
                        const Text(' Invite only', style: TextStyle(fontSize: 12)),
                      ],
                      const Spacer(),
                      Text('${g.memberIds.length}/${g.maxMembers} members', style: Theme.of(context).textTheme.bodySmall),
                    ]),
                    const SizedBox(height: 8),
                    Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    if (g.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(g.description, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.schedule_rounded, size: 16),
                      const SizedBox(width: 4),
                      Text(g.meetingTime ?? 'TBD'),
                      const SizedBox(width: 14),
                      const Icon(Icons.place_outlined, size: 16),
                      const SizedBox(width: 4),
                      Expanded(child: Text(g.location ?? 'TBD', overflow: TextOverflow.ellipsis)),
                      _GroupAction(group: g, joined: joined, pending: pending.contains(g.id)),
                    ]),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}


final _pendingProvider = FutureProvider.autoDispose((ref) => ref.watch(repositoryProvider).myPendingGroupRequests());

/// Join (open), Ask to join (invite only), Requested, or Open chat (member).
class _GroupAction extends ConsumerWidget {
  const _GroupAction({required this.group, required this.joined, required this.pending});
  final StudyGroup group;
  final bool joined, pending;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    if (joined) {
      return FilledButton.tonalIcon(
        onPressed: () => context.push('/groups/${group.id}'),
        icon: const Icon(Icons.forum_rounded, size: 18),
        label: const Text('Open'),
      );
    }
    if (pending) return const OutlinedButton(onPressed: null, child: Text('Requested'));
    final full = group.memberIds.length >= group.maxMembers;
    return FilledButton(
      onPressed: full
          ? null
          : () async {
              try {
                if (group.inviteOnly) {
                  final note = TextEditingController();
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Ask to join ${group.name}'),
                      content: TextField(
                        controller: note,
                        maxLength: 300,
                        decoration: const InputDecoration(labelText: 'A short note to the owner (optional)'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  await repo.requestToJoinGroup(group.id, note.text.trim().isEmpty ? null : note.text.trim());
                  ref.invalidate(_pendingProvider);
                  if (context.mounted) showSnack(context, 'Asked. You will be told when the owner decides.');
                } else {
                  await repo.toggleGroupMembership(group.id, true);
                  ref.invalidate(studyGroupsProvider);
                }
              } catch (e) {
                if (context.mounted) showSnack(context, '$e'.replaceFirst('Exception: ', ''));
              }
            },
      child: Text(full ? 'Full' : group.inviteOnly ? 'Ask to join' : 'Join'),
    );
  }
}
