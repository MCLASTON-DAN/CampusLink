import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../data/access.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import 'requests_screen.dart';

class RequestDetailScreen extends ConsumerStatefulWidget {
  const RequestDetailScreen({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends ConsumerState<RequestDetailScreen> {
  final _msg = TextEditingController();

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  bool _sending = false;

  Future<void> _send({RequestStatus? status}) async {
    if (_sending) return; // one send at a time
    final text = _msg.text.trim();
    if (text.isEmpty && status == null) return;
    setState(() => _sending = true);
    _msg.clear(); // clear at once so it doesn't look like nothing happened
    try {
      await ref.read(repositoryProvider).addRequestUpdate(
            RequestUpdate(
              id: const Uuid().v4(),
              requestId: widget.requestId,
              authorId: ref.read(repositoryProvider).currentUserSync?.id,
              message: text.isEmpty ? 'Status changed to ${status!.label}.' : text,
              newStatus: status?.db,
              createdAt: DateTime.now(),
            ),
            newStatus: status,
          );
      ref.invalidate(requestUpdatesProvider(widget.requestId));
      ref.invalidate(myRequestsProvider);
    } catch (_) {
      if (mounted) {
        if (_msg.text.isEmpty) _msg.text = text; // give the words back
        showSnack(context, 'Not sent. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _move(HelpRequest r, List<HelpOffice> offices) async {
    final pick = await showModalBottomSheet<HelpOffice>(
      useRootNavigator: true, // above the tab bar, never under it
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Send this request to', style: TextStyle(fontWeight: FontWeight.w700))),
          for (final o in offices)
            ListTile(
              leading: Icon(o.id == r.officeId ? Icons.check_circle_rounded : Icons.apartment_rounded),
              title: Text(o.name),
              subtitle: o.description.isEmpty ? null : Text(o.description, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(sheet, o),
            ),
        ]),
      ),
    );
    if (pick == null || pick.id == r.officeId) return;
    try {
      await ref.read(repositoryProvider).moveRequest(r.id, pick.id, pick.name);
      ref.invalidate(myRequestsProvider);
      ref.invalidate(requestUpdatesProvider(r.id));
    } catch (_) {
      if (mounted) showSnack(context, 'Could not move it. Check your connection and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(myRequestsProvider);
    final updates = ref.watch(requestUpdatesProvider(widget.requestId));
    final offices = ref.watch(officesProvider).valueOrNull ?? [];
    final user = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/requests')),
        title: const Text('Request'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(myRequestsProvider);
              ref.invalidate(requestUpdatesProvider(widget.requestId));
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: AsyncBody(
        value: requests,
        builder: (list) {
          final r = list.where((x) => x.id == widget.requestId).firstOrNull;
          if (r == null) return const EmptyState(icon: Icons.error_outline, title: 'Request not found');
          final office = offices.where((o) => o.id == r.officeId).firstOrNull;
          final canClose = r.status != RequestStatus.closed && r.status != RequestStatus.resolved;
          // Acting as the office: same rule as the database (access.dart / 0016).
          final asOffice = canHandleRequest(
            me: user,
            officeId: r.officeId,
            myOffices: ref.watch(myHandledOfficesProvider).valueOrNull ?? const {},
            confidential: office?.confidential ?? false,
          );
          final isMine = user?.id == r.studentId;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              StatusChip(r.status.label, color: statusColor(r.status)),
                              const SizedBox(width: 8),
                              StatusChip(r.priority, color: Colors.blueGrey),
                            ]),
                            const SizedBox(height: 10),
                            Text(r.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            Text(r.description),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(
                                child: Text('${office?.name ?? 'General desk'} · opened ${friendlyDate(r.createdAt)}',
                                    style: Theme.of(context).textTheme.bodySmall),
                              ),
                              if (offices.isNotEmpty && canClose && (asOffice || isMine))
                                TextButton.icon(
                                  onPressed: () => _move(r, offices),
                                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                                  label: Text(r.officeId == null ? 'Choose office' : 'Change office'),
                                ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ProgressBar(status: r.status),
                    const SizedBox(height: 16),
                    const SectionHeader('Updates'),
                    AsyncBody(
                      value: updates,
                      builder: (ups) => Column(
                        children: [
                          for (var i = 0; i < ups.length; i++)
                            _TimelineTile(
                              update: ups[i],
                              isLast: i == ups.length - 1,
                              who: ups[i].authorId == user?.id
                                  ? 'You'
                                  : ups[i].authorId == r.studentId
                                      ? 'Student'
                                      : (office?.name ?? 'Office'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (r.status != RequestStatus.closed)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      children: [
                        if (asOffice)
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final s in RequestStatus.values.where((s) => s != r.status))
                                ActionChip(
                                  label: Text('Mark ${s.label}'),
                                  avatar: Icon(Icons.flag_rounded, size: 16, color: statusColor(s)),
                                  onPressed: _sending ? null : () => _send(status: s),
                                ),
                            ],
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _msg,
                                decoration: const InputDecoration(hintText: 'Add a comment…'),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: _sending ? null : () => _send(),
                              icon: _sending
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.send_rounded),
                            ),
                            if (canClose && isMine && !asOffice)
                              IconButton.outlined(
                                tooltip: 'Close it: my problem is sorted',
                                onPressed: _sending ? null : () => _send(status: RequestStatus.closed),
                                icon: const Icon(Icons.check_rounded),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.status});
  final RequestStatus status;

  @override
  Widget build(BuildContext context) {
    final steps = RequestStatus.values;
    final idx = steps.indexOf(status);
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: i <= idx ? statusColor(steps[i]) : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 6),
                Text(steps[i].label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: i == idx ? FontWeight.w800 : FontWeight.w500,
                        )),
              ],
            ),
          ),
          if (i < steps.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.update, required this.isLast, required this.who});
  final RequestUpdate update;
  final bool isLast;
  final String who;

  @override
  Widget build(BuildContext context) {
    final color = update.newStatus == null
        ? Theme.of(context).colorScheme.primary
        : statusColor(RequestStatusX.parse(update.newStatus));
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(width: 12, height: 12, margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              if (!isLast) Expanded(child: Container(width: 2, color: color.withValues(alpha: 0.3))),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(who, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Text(friendlyDate(update.createdAt), style: Theme.of(context).textTheme.bodySmall),
                  ]),
                  const SizedBox(height: 2),
                  Text(update.message),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
