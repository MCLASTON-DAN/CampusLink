import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/person_picker.dart';

final _handlersProvider =
    FutureProvider.autoDispose.family((ref, String officeId) => ref.watch(repositoryProvider).officeHandlers(officeId));

/// Who handles this office's help requests, and whether it is confidential.
/// The super admin manages it; the office's own handlers can see it.
class OfficeAccessPanel extends ConsumerWidget {
  const OfficeAccessPanel({super.key, required this.office});
  final HelpOffice office;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    final mine = ref.watch(myHandledOfficesProvider).valueOrNull ?? const <String>{};
    final admin = me?.isSuperAdmin ?? false;
    if (!admin && !mine.contains(office.id)) return const SizedBox.shrink();
    final handlers = ref.watch(_handlersProvider(office.id));

    Future<void> change(String userId, bool add) async {
      try {
        await ref.read(repositoryProvider).setOfficeHandler(office.id, userId, add: add);
        ref.invalidate(_handlersProvider(office.id));
        ref.invalidate(myHandledOfficesProvider);
      } catch (e) {
        if (context.mounted) showSnack(context, '$e'.replaceFirst('Exception: ', ''));
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Who handles requests here', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            office.confidential
                ? 'Confidential: only these people (and the student) can read requests sent here. Not even the super admin.'
                : 'Only these people (and the student) can read and answer requests sent here. The super admin can too.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (admin)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Confidential office'),
              subtitle: const Text('For private matters like counselling.'),
              value: office.confidential,
              onChanged: (v) async {
                try {
                  await ref.read(communityProvider).saveOffice(office.copyWith(confidential: v));
                  ref.invalidate(officesProvider);
                } catch (e) {
                  if (context.mounted) showSnack(context, 'Could not change it. Check your connection.');
                }
              },
            ),
          handlers.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text('Could not load. Pull down to refresh.'),
            data: (list) => Column(children: [
              if (list.isEmpty)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.warning_amber_rounded, color: Color(0xFFF2780C)),
                  title: Text('Nobody handles this office yet'),
                  subtitle: Text('Requests sent here wait until someone is added.'),
                ),
              for (final h in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(h.name),
                  trailing: admin
                      ? IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.person_remove_outlined),
                          onPressed: () => change(h.id, false),
                        )
                      : null,
                ),
            ]),
          ),
          if (admin)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Add a handler'),
                onPressed: () async {
                  final p = await pickPerson(context, ref.read(communityProvider), title: 'Who handles ${office.name}?');
                  if (p != null) await change(p.id, true);
                },
              ),
            ),
        ]),
      ),
    );
  }
}
