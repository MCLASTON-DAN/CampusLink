import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../requests/new_request_sheet.dart';

final myExamsProvider = FutureProvider.autoDispose((ref) => ref.watch(repositoryProvider).myExams());
final _papersProvider = FutureProvider.autoDispose((ref) => ref.watch(repositoryProvider).examPapers());
final _canManageProvider = FutureProvider.autoDispose((ref) => ref.watch(repositoryProvider).canManageExams());

String _when(DateTime d) {
  final today = DateTime.now();
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
  final label = DateFormat('EEE d MMM').format(d);
  return days == 0 ? '$label · today' : days == 1 ? '$label · tomorrow' : '$label · in $days days';
}

class ExamsScreen extends ConsumerWidget {
  const ExamsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(_canManageProvider).valueOrNull ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('My exams'), actions: [
        IconButton(tooltip: 'Refresh', onPressed: () => ref.invalidate(myExamsProvider), icon: const Icon(Icons.refresh_rounded)),
        if (canManage)
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExamPapersScreen())),
            icon: const Icon(Icons.edit_calendar_rounded),
            label: const Text('Official list'),
          ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add my exam'),
        onPressed: () async {
          final e = await examForm(context, official: false);
          if (e == null) return;
          try {
            await ref.read(repositoryProvider).addMyExam(e);
            ref.invalidate(myExamsProvider);
          } catch (_) {
            if (context.mounted) showSnack(context, 'Could not save. Check your connection.');
          }
        },
      ),
      body: AsyncBody(
        value: ref.watch(myExamsProvider),
        onRetry: () => ref.invalidate(myExamsProvider),
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.event_note_rounded,
              title: 'No exams yet',
              subtitle: 'When the Examinations office posts dates for the units on your timetable, they appear here by themselves. '
                  'You can also add your own.',
            );
          }
          final clashes = findExamClashes(list);
          final days = <DateTime, List<ExamEntry>>{};
          for (final e in list) {
            (days[DateTime(e.date.year, e.date.month, e.date.day)] ??= []).add(e);
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myExamsProvider),
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: [
              if (clashes.isNotEmpty)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: Text('${clashes.length} exams clash'),
                    subtitle: const Text('Two papers at the same time on the same day. Tell the Examinations office early.'),
                  ),
                ),
              for (final d in days.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                  child: Text(_when(d.key), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                for (final e in d.value)
                  Card(
                    child: ListTile(
                      title: Text('${e.courseCode}${e.courseName == null ? '' : ' · ${e.courseName}'}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text([
                          '${e.start}–${e.end}',
                          if ((e.room ?? '').isNotEmpty) e.room!,
                          if ((e.campus ?? '').isNotEmpty) e.campus!,
                        ].join(' · ')),
                        if ((e.notes ?? '').isNotEmpty) Text(e.notes!),
                        Text(e.official ? 'Official – Examinations office' : 'Added by you',
                            style: Theme.of(context).textTheme.bodySmall),
                        if (clashes[e.id] != null) ...[
                          Text('⚠ Clashes with ${clashes[e.id]!.map((x) => x.courseCode).join(', ')}',
                              style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
                          TextButton(
                            onPressed: () async {
                              final offices = await ref.read(officesProvider.future);
                              final exams = offices.where((o) => o.name.toLowerCase().contains('exam')).firstOrNull;
                              if (context.mounted) await showNewRequestSheet(context, ref, officeId: exams?.id);
                            },
                            child: const Text('Tell the Examinations office'),
                          ),
                        ],
                      ]),
                      trailing: e.official
                          ? null
                          : IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () async {
                                await ref.read(repositoryProvider).deleteMyExam(e.id);
                                ref.invalidate(myExamsProvider);
                              },
                            ),
                    ),
                  ),
              ],
            ]),
          );
        },
      ),
    );
  }
}

/// The Examinations office's official list: add, change or remove papers.
class ExamPapersScreen extends ConsumerWidget {
  const ExamPapersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> save(ExamEntry? old) async {
      final e = await examForm(context, official: true, initial: old);
      if (e == null) return;
      try {
        await ref.read(repositoryProvider).saveExamPaper(e);
        ref.invalidate(_papersProvider);
        ref.invalidate(myExamsProvider);
      } catch (err) {
        if (context.mounted) showSnack(context, '$err'.replaceFirst('Exception: ', ''));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Official exam list')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => save(null), icon: const Icon(Icons.add_rounded), label: const Text('Add paper')),
      body: AsyncBody(
        value: ref.watch(_papersProvider),
        onRetry: () => ref.invalidate(_papersProvider),
        builder: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.event_note_rounded,
                title: 'No papers yet',
                subtitle: 'Add each paper once. Students taking that unit see it and get reminders.')
            : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: [
                for (final e in list)
                  Card(
                    child: ListTile(
                      onTap: () => save(e),
                      title: Text('${e.courseCode} · ${DateFormat('EEE d MMM yyyy').format(e.date)}'),
                      subtitle: Text(['${e.start}–${e.end}', if (e.room != null) e.room!, if (e.campus != null) e.campus!].join(' · ')),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          await ref.read(repositoryProvider).deleteExamPaper(e.id);
                          ref.invalidate(_papersProvider);
                        },
                      ),
                    ),
                  ),
              ]),
      ),
    );
  }
}

/// Form for one exam on a real date. Returns null if cancelled.
Future<ExamEntry?> examForm(BuildContext context, {required bool official, ExamEntry? initial}) async {
  final code = TextEditingController(text: initial?.courseCode), name = TextEditingController(text: initial?.courseName);
  final room = TextEditingController(text: initial?.room), campus = TextEditingController(text: initial?.campus);
  final notes = TextEditingController(text: initial?.notes);
  var date = initial?.date;
  var start = initial == null ? const TimeOfDay(hour: 9, minute: 0) : _tod(initial.start);
  var end = initial == null ? const TimeOfDay(hour: 12, minute: 0) : _tod(initial.end);
  String hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String? error;
  return showDialog<ExamEntry>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(initial == null ? (official ? 'Add official paper' : 'Add my exam') : 'Change paper'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Unit code', hintText: 'BDA2207')),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Unit name (optional)')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_rounded),
              title: Text(date == null ? 'Pick the date' : DateFormat('EEEE d MMMM yyyy').format(date!)),
              onTap: () async {
                final d = await showDatePicker(
                    context: ctx,
                    initialDate: date ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 400)));
                if (d != null) setS(() => date = d);
              },
            ),
            Row(children: [
              Expanded(
                child: TextButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: ctx, initialTime: start);
                      if (t != null) setS(() => start = t);
                    },
                    child: Text('Starts ${hhmm(start)}')),
              ),
              Expanded(
                child: TextButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: ctx, initialTime: end);
                      if (t != null) setS(() => end = t);
                    },
                    child: Text('Ends ${hhmm(end)}')),
              ),
            ]),
            TextField(controller: room, decoration: const InputDecoration(labelText: 'Room (optional)')),
            TextField(controller: campus, decoration: const InputDecoration(labelText: 'Campus (optional)')),
            if (official) TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes for students (optional)')),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              String? v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
              if (code.text.trim().length < 2) return setS(() => error = 'Enter the unit code.');
              if (date == null) return setS(() => error = 'Pick the date.');
              if (hhmm(end).compareTo(hhmm(start)) <= 0) return setS(() => error = 'The end must be after the start.');
              Navigator.pop(
                ctx,
                ExamEntry(
                  id: initial?.id ?? const Uuid().v4(),
                  courseCode: code.text.trim().toUpperCase(),
                  courseName: v(name),
                  date: date!,
                  start: hhmm(start),
                  end: hhmm(end),
                  room: v(room),
                  campus: v(campus),
                  notes: v(notes),
                  official: official,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

TimeOfDay _tod(String hhmm) {
  final p = hhmm.split(':');
  return TimeOfDay(hour: int.tryParse(p.first) ?? 9, minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
}
