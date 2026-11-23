import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/community_models.dart';
import '../../data/providers.dart';
import '../../widgets/badge.dart';
import '../../widgets/person_picker.dart';
import '../../widgets/section.dart';

/// Course-unit notices: from a lecturer to only the students taking that unit
/// (found from their timetable). A unit shared by several programmes reaches
/// all of them, and nobody else.
class CoursesScreen extends ConsumerWidget {
  const CoursesScreen({super.key});

  static Color priorityColor(String p) => switch (p) {
        'urgent' => const Color(0xFFE53935),
        'important' => const Color(0xFFF59E0B),
        _ => const Color(0xFF64748B),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final units = ref.watch(teachingUnitsProvider).valueOrNull ?? const [];
    final notices = ref.watch(courseNoticesProvider);
    final hasTimetable = (ref.watch(timetableProvider).valueOrNull ?? const []).isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('My course units')),
      floatingActionButton: units.isNotEmpty || (user?.isStaff ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/courses/new'),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send a notice'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(courseNoticesProvider),
        child: PageBody(maxWidth: 820, children: [
          if (units.isNotEmpty)
            Card(
              child: ListTile(
                leading: const VerifiedBadge('orange', size: 22),
                title: const Text('You teach'),
                subtitle: Text(units.join(' · ')),
              ),
            ),
          if (user?.isStaff ?? false)
            Card(
              child: ListTile(
                leading: const Icon(Icons.assignment_ind_rounded),
                title: const Text('Assign lecturers to units'),
                subtitle: const Text('Only assigned lecturers can message a unit'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/courses/lecturers'),
              ),
            ),
          if (!hasTimetable && units.isEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_month_rounded),
                title: const Text('Add your timetable first'),
                subtitle: const Text('Notices reach you for the units in your timetable.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/timetable'),
              ),
            ),
          const SectionTitle('Notices'),
          ...notices.when(
            loading: () => [const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))],
            error: (e, _) => [Text('Could not load: $e')],
            data: (list) => list.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No notices for your units yet.', textAlign: TextAlign.center),
                    ),
                  ]
                : [for (final n in list) _NoticeCard(n)],
          ),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard(this.n);
  final CourseNotice n;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pc = CoursesScreen.priorityColor(n.priority);
    return Card(
      shape: n.priority == 'normal'
          ? null
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: pc, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in n.courseCodes)
              Chip(label: Text(c), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            if (n.priority != 'normal')
              Chip(
                label: Text(n.priority.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                backgroundColor: pc,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ]),
          const SizedBox(height: 8),
          Text(n.title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SelectableText(n.body),
          if (n.linkUrl != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse(n.linkUrl!), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open link'),
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Flexible(child: NameWithBadge(n.lecturerName.isEmpty ? 'Lecturer' : n.lecturerName, 'orange', style: t.bodySmall)),
            Text(' · ${DateFormat('EEE d MMM, HH:mm').format(n.createdAt.toLocal())}', style: t.bodySmall),
          ]),
        ]),
      ),
    );
  }
}

class ComposeCourseNoticeScreen extends ConsumerStatefulWidget {
  const ComposeCourseNoticeScreen({super.key});
  @override
  ConsumerState<ComposeCourseNoticeScreen> createState() => _ComposeState();
}

class _ComposeState extends ConsumerState<ComposeCourseNoticeScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _link = TextEditingController();
  final _extra = TextEditingController();
  final _picked = <String>{};
  String _priority = 'normal';
  bool _sending = false;

  Future<void> _send() async {
    final codes = {
      ..._picked,
      ..._extra.text.split(RegExp(r'[,\s]+')).map((c) => c.trim().toUpperCase()).where((c) => c.length >= 3),
    }.toList();
    if (codes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick at least one unit.')));
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await ref.read(communityProvider).sendCourseNotice(
            courseCodes: codes,
            title: _title.text,
            body: _body.text,
            linkUrl: _link.text,
            priority: _priority,
          );
      ref.invalidate(courseNoticesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sent to students taking ${codes.join(', ')}')));
        context.pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(teachingUnitsProvider).valueOrNull ?? const [];
    final staff = ref.watch(currentUserProvider).valueOrNull?.isStaff ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Notice to a unit')),
      body: Form(
        key: _form,
        child: PageBody(maxWidth: 720, children: [
          const Text('Only students with these units in their timetable receive it. '
              'If a unit is shared by several programmes (for example Machine Learning for BSE, BCS and BDSAI), '
              'pick every code it uses so all of them get it.'),
          const SizedBox(height: 16),
          if (units.isNotEmpty) ...[
            Text('Your units', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final u in units)
                FilterChip(
                  label: Text(u),
                  selected: _picked.contains(u),
                  onSelected: (v) => setState(() => v ? _picked.add(u) : _picked.remove(u)),
                ),
            ]),
            const SizedBox(height: 12),
          ],
          if (staff)
            TextField(
              controller: _extra,
              decoration: const InputDecoration(labelText: 'Other unit codes (staff)', hintText: 'BDA1202, BSE2201'),
            ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'normal', label: Text('Normal')),
              ButtonSegment(value: 'important', label: Text('Important')),
              ButtonSegment(value: 'urgent', label: Text('Urgent')),
            ],
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _title,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Title', hintText: 'CAT 1 moved to Friday'),
            validator: (v) => (v ?? '').trim().length < 3 ? 'Add a short title' : null,
          ),
          TextFormField(
            controller: _body,
            minLines: 4,
            maxLines: 12,
            maxLength: 4000,
            decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
            validator: (v) => (v ?? '').trim().length < 5 ? 'Write the message' : null,
          ),
          TextFormField(
            controller: _link,
            decoration: const InputDecoration(labelText: 'Link (optional)', hintText: 'https://meet.google.com/…'),
            validator: (v) {
              final s = (v ?? '').trim();
              return s.isEmpty || s.startsWith('https://') ? null : 'Links must start with https://';
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send_rounded),
            label: Text(_sending ? 'Sending…' : 'Send notice'),
          ),
        ]),
      ),
    );
  }
}

class LecturersScreen extends ConsumerStatefulWidget {
  const LecturersScreen({super.key});
  @override
  ConsumerState<LecturersScreen> createState() => _LecturersState();
}

class _LecturersState extends ConsumerState<LecturersScreen> {
  final _codes = TextEditingController();
  PersonHit? _who;
  bool _busy = false;

  Future<void> _add() async {
    final codes = _codes.text.split(RegExp(r'[,\s]+')).where((c) => c.trim().length >= 3).toList();
    if (_who == null || codes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose the lecturer and type at least one unit code.')));
      return;
    }
    setState(() => _busy = true);
    try {
      for (final c in codes) {
        await ref.read(communityProvider).assignLecturer(userId: _who!.id, courseCode: c);
      }
      _codes.clear();
      ref.invalidate(courseLecturersProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(courseLecturersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Lecturers and units')),
      body: PageBody(maxWidth: 760, children: [
        const Text('A lecturer gets the orange badge and can message the students of the units assigned here. '
            'They must sign in to CampusLink once before you can find them.'),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: _who == null ? const Icon(Icons.person_search_rounded) : PersonAvatar(name: _who!.fullName, url: _who!.avatar),
            title: Text(_who == null ? 'Choose the lecturer' : _who!.fullName),
            subtitle: Text(_who == null ? 'Search by @username or name' : '@${_who!.username ?? ''}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final p = await pickPerson(context, ref.read(communityProvider), title: 'Find the lecturer');
              if (p != null) setState(() => _who = p);
            },
          ),
        ),
        const SizedBox(height: 8),
        TextField(controller: _codes, decoration: const InputDecoration(labelText: 'Unit codes', hintText: 'BDA1202, COM221')),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _add, child: Text(_busy ? 'Saving…' : 'Assign')),
        const SectionTitle('Assigned'),
        ...list.when(
          loading: () => [const Center(child: CircularProgressIndicator())],
          error: (e, _) => [Text('$e')],
          data: (l) => l.isEmpty
              ? [const Text('No lecturers assigned yet.')]
              : [
                  for (final x in l)
                    Card(
                      child: ListTile(
                        leading: const VerifiedBadge('orange', size: 20),
                        title: Text(x.name.isEmpty ? 'Lecturer' : x.name),
                        subtitle: Text(x.courseCode),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () async {
                            await ref.read(communityProvider).removeLecturer(courseCode: x.courseCode, lecturerId: x.lecturerId);
                            ref.invalidate(courseLecturersProvider);
                          },
                        ),
                      ),
                    ),
                ],
        ),
      ]),
    );
  }
}
