import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

Future<void> showNewRequestSheet(BuildContext context, WidgetRef ref, {String? officeId}) async {
  final offices = await ref.read(officesProvider.future);
  if (!context.mounted) return;
  final title = TextEditingController();
  final desc = TextEditingController();
  String? office = officeId;
  var priority = 'normal';
  // One id for this form. Tapping twice, or retrying after a network error,
  // sends the same id, so it can only ever make one complaint.
  final requestId = const Uuid().v4();
  var busy = false;
  String? error;

  final created = await showModalBottomSheet<HelpRequest>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New help request', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Tell us what you need. You will get a tracking status on every update.',
                style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            if (offices.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('No offices are set up yet, so this goes to the general desk. '
                    'Staff will send it to the right office.'),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: office ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Which office?'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Not sure – general desk will route it')),
                  for (final o in offices) DropdownMenuItem(value: o.id, child: Text(o.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: busy ? null : (v) => setS(() => office = (v == null || v.isEmpty) ? null : v),
              ),
            const SizedBox(height: 12),
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Short title', hintText: 'e.g. Missing marks for BDA2207')),
            const SizedBox(height: 12),
            TextField(controller: desc, maxLines: 4, decoration: const InputDecoration(labelText: 'Details')),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'low', label: Text('Low')),
                ButtonSegment(value: 'normal', label: Text('Normal')),
                ButtonSegment(value: 'urgent', label: Text('Urgent')),
              ],
              selected: {priority},
              onSelectionChanged: (s) => setS(() => priority = s.first),
            ),
            const SizedBox(height: 18),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (title.text.trim().length < 3) {
                        setS(() => error = 'Give it a short title (3+ letters).');
                        return;
                      }
                      setS(() {
                        busy = true;
                        error = null;
                      });
                      final uid = ref.read(repositoryProvider).currentUserSync?.id ?? 'anon';
                      final r = HelpRequest(
                        id: requestId,
                        studentId: uid,
                        officeId: office,
                        title: title.text.trim(),
                        description: desc.text.trim(),
                        priority: priority,
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      );
                      try {
                        final saved = await ref.read(repositoryProvider).createRequest(r);
                        if (ctx.mounted) Navigator.pop(ctx, saved);
                      } catch (_) {
                        // Safe to tap again: the same id means no duplicate.
                        if (ctx.mounted) {
                          setS(() {
                            busy = false;
                            error = 'Could not send. Check your connection and tap Submit again.';
                          });
                        }
                      }
                    },
              child: busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit request'),
            ),
          ],
        ),
      ),
    ),
  );

  if (created != null && context.mounted) {
    ref.invalidate(myRequestsProvider);
    showSnack(context, 'Request submitted. Track it under Requests.');
    context.go('/requests/${created.id}');
  }
}
