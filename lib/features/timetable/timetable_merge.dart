import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../widgets/common.dart';

int _mins(String hhmm) {
  final p = hhmm.split(':');
  return (int.tryParse(p.first) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
}

/// Two entries for the same class at the same time (an import repeating what you have).
bool sameClass(TimetableEntry a, TimetableEntry b) =>
    a.dayOfWeek == b.dayOfWeek &&
    a.startTime == b.startTime &&
    a.courseCode.trim().toUpperCase() == b.courseCode.trim().toUpperCase();

/// For each class, the other classes it overlaps on the same day.
/// 08:00–10:00 and 10:00–12:00 touch but do not clash.
Map<String, List<TimetableEntry>> findClashes(List<TimetableEntry> all) {
  final out = <String, List<TimetableEntry>>{};
  for (var i = 0; i < all.length; i++) {
    for (var j = i + 1; j < all.length; j++) {
      final a = all[i], b = all[j];
      if (a.dayOfWeek != b.dayOfWeek) continue;
      if (_mins(a.startTime) < _mins(b.endTime) && _mins(b.startTime) < _mins(a.endTime)) {
        (out[a.id] ??= []).add(b);
        (out[b.id] ??= []).add(a);
      }
    }
  }
  return out;
}

/// Review an import: keep or drop each current class, add or skip each new one,
/// and see clashes before saving. Returns the final timetable, or null.
Future<List<TimetableEntry>?> reviewTimetableImport(
    BuildContext context, List<TimetableEntry> current, List<TimetableEntry> incoming) {
  return Navigator.of(context).push<List<TimetableEntry>>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _ReviewPage(current: current, incoming: incoming),
  ));
}

class _ReviewPage extends StatefulWidget {
  const _ReviewPage({required this.current, required this.incoming});
  final List<TimetableEntry> current, incoming;
  @override
  State<_ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<_ReviewPage> {
  late final List<TimetableEntry> _new;
  late final Set<String> _keep, _add;

  @override
  void initState() {
    super.initState();
    // Classes you already have are not offered twice.
    _new = widget.incoming.where((n) => !widget.current.any((c) => sameClass(c, n))).toList();
    _keep = widget.current.map((e) => e.id).toSet();
    _add = _new.map((e) => e.id).toSet();
  }

  List<TimetableEntry> get _result => [
        ...widget.current.where((e) => _keep.contains(e.id)),
        ..._new.where((e) => _add.contains(e.id)),
      ];

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final clashes = findClashes(result);
    final dupes = widget.incoming.length - _new.length;
    final t = Theme.of(context).textTheme;

    Widget row(TimetableEntry e, Set<String> set, {required bool isNew}) {
      final on = set.contains(e.id);
      final c = on ? clashes[e.id] : null;
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: on,
        onChanged: (v) => setState(() => v == true ? set.add(e.id) : set.remove(e.id)),
        title: Text('${dayNames[e.dayOfWeek - 1]} ${e.startTime}–${e.endTime} · ${e.courseCode}'),
        subtitle: Text(
          [
            if ((e.courseName ?? '').isNotEmpty) e.courseName!,
            if ((e.room ?? '').isNotEmpty) e.room!,
            if (c != null) '⚠ Clashes with ${c.map((x) => x.courseCode).toSet().join(', ')}',
          ].join(' · '),
          style: c == null ? null : TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
        ),
        secondary: isNew ? const Icon(Icons.fiber_new_rounded) : null,
      );
    }

    final sortedCurrent = [...widget.current]..sort(_order);
    final sortedNew = [..._new]..sort(_order);
    return Scaffold(
      appBar: AppBar(title: const Text('Review your timetable')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
        if (clashes.isNotEmpty)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: Text('${clashes.length} classes clash'),
              subtitle: const Text('Untick the ones you don\'t attend, or keep both if you really have both.'),
            ),
          ),
        if (dupes > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('$dupes classes from the file are already in your timetable, so they are not repeated.', style: t.bodySmall),
          ),
        if (widget.current.isNotEmpty) ...[
          Row(children: [
            Expanded(child: Text('Already in your timetable', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            TextButton(onPressed: () => setState(_keep.clear), child: const Text('Drop all')),
            TextButton(onPressed: () => setState(() => _keep.addAll(widget.current.map((e) => e.id))), child: const Text('Keep all')),
          ]),
          for (final e in sortedCurrent) row(e, _keep, isNew: false),
          const Divider(height: 24),
        ],
        Row(children: [
          Expanded(child: Text('New from the file', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          TextButton(onPressed: () => setState(_add.clear), child: const Text('Skip all')),
          TextButton(onPressed: () => setState(() => _add.addAll(_new.map((e) => e.id))), child: const Text('Add all')),
        ]),
        if (_new.isEmpty) const Text('Nothing new: you already have every class in this file.'),
        for (final e in sortedNew) row(e, _add, isNew: true),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () => Navigator.pop(context, result),
            child: Text('Save ${result.length} classes'),
          ),
        ),
      ),
    );
  }

  static int _order(TimetableEntry a, TimetableEntry b) =>
      a.dayOfWeek != b.dayOfWeek ? a.dayOfWeek.compareTo(b.dayOfWeek) : a.startTime.compareTo(b.startTime);
}
