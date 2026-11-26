import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import 'new_request_sheet.dart';

Color statusColor(RequestStatus s) => switch (s) {
      RequestStatus.open => Brand.amber,
      RequestStatus.inProgress => const Color(0xFF0EA5E9),
      RequestStatus.resolved => const Color(0xFF059669),
      RequestStatus.closed => const Color(0xFF64748B),
    };

class RequestsScreen extends ConsumerWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(myRequestsProvider);
    final offices = ref.watch(officesProvider).valueOrNull ?? [];
    final user = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Help requests')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showNewRequestSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New request'),
      ),
      body: AsyncBody(
        value: data,
        onRetry: () => ref.invalidate(myRequestsProvider),
        builder: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.support_agent_rounded,
              title: 'No requests yet',
              subtitle: 'Raise a request with any office and follow its progress here.',
              action: FilledButton(onPressed: () => showNewRequestSheet(context, ref), child: const Text('Create one')),
            );
          }
          final openCount = list.where((r) => r.status == RequestStatus.open || r.status == RequestStatus.inProgress).length;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myRequestsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
              children: [
                Row(
                  children: [
                    _Stat('Active', openCount, Brand.violet),
                    const SizedBox(width: 10),
                    _Stat('Resolved', list.where((r) => r.status == RequestStatus.resolved).length, const Color(0xFF059669)),
                    const SizedBox(width: 10),
                    _Stat('Total', list.length, Brand.indigo),
                  ],
                ),
                const SizedBox(height: 16),
                TopicGroups(
                  requests: list.where((r) => r.studentId != user?.id).toList(),
                  offices: offices,
                ),
                for (final (i, r) in [
                  ...list.where((r) => r.studentId == user?.id),
                  ...list.where((r) => r.studentId != user?.id),
                ].indexed) ...[
                  if (i == 0 && r.studentId == user?.id) const SectionHeader('Sent by me'),
                  if (r.studentId != user?.id && (i == 0 || list.where((x) => x.studentId == user?.id).length == i))
                    const SectionHeader('For my office'),
                  Card(
                    child: ListTile(
                      onTap: () => context.go('/requests/${r.id}'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${offices.where((o) => o.id == r.officeId).firstOrNull?.name ?? 'General'} · updated ${friendlyDate(r.updatedAt)}',
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          StatusChip(r.status.label, color: statusColor(r.status)),
                          if (r.priority == 'urgent')
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text('URGENT', style: TextStyle(fontSize: 10, color: Brand.coral, fontWeight: FontWeight.w800)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}


/// Office view: open requests grouped by topic, answer a whole group at once.
class TopicGroups extends ConsumerWidget {
  const TopicGroups({super.key, required this.requests, required this.offices});
  final List<HelpRequest> requests;
  final List<HelpOffice> offices;

  Future<void> _replyAll(BuildContext context, WidgetRef ref, String? officeId, String topic, int count) async {
    final msg = TextEditingController();
    RequestStatus? status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Reply to all $count: $topic'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: msg,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'One reply for everyone', hintText: 'e.g. Marks for BDA2207 are now on the portal.'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<RequestStatus?>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Also change status'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Keep as it is')),
                DropdownMenuItem(value: RequestStatus.inProgress, child: Text('In progress')),
                DropdownMenuItem(value: RequestStatus.resolved, child: Text('Resolved')),
              ],
              onChanged: (v) => setS(() => status = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send to all')),
          ],
        ),
      ),
    );
    if (ok != true || msg.text.trim().length < 3) return;
    try {
      final n = await ref
          .read(repositoryProvider)
          .replyToTopic(officeId: officeId, topic: topic, message: msg.text.trim(), status: status);
      ref.invalidate(myRequestsProvider);
      if (context.mounted) showSnack(context, 'Sent to $n students.');
    } catch (e) {
      if (context.mounted) showSnack(context, '$e'.replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = <(String?, String), int>{};
    for (final r in requests) {
      if (r.topic == null || (r.status != RequestStatus.open && r.status != RequestStatus.inProgress)) continue;
      groups.update((r.officeId, r.topic!), (n) => n + 1, ifAbsent: () => 1);
    }
    final big = groups.entries.where((e) => e.value >= 2).toList()..sort((a, b) => b.value.compareTo(a.value));
    if (big.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Same problem, many students', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const Text('Fix it once and answer everyone together.'),
          for (final e in big)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('${e.value}')),
              title: Text(e.key.$2),
              subtitle: Text(offices.where((o) => o.id == e.key.$1).firstOrNull?.name ?? 'General desk'),
              trailing: TextButton(
                onPressed: () => _replyAll(context, ref, e.key.$1, e.key.$2, e.value),
                child: const Text('Reply to all'),
              ),
            ),
        ]),
      ),
    );
  }
}
