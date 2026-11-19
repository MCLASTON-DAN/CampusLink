import 'package:flutter/material.dart';

import '../../data/models.dart';
import 'timetable_import.dart';

/// Lets a student choose their programme and year/semester sections from an
/// official timetable file. Returns the chosen classes, or null if cancelled.
Future<List<TimetableEntry>?> pickTimetableGroups(
  BuildContext context,
  List<TimetableGroup> groups, {
  String? programme,
  int? year,
}) {
  // One group only (e.g. a personal CSV): nothing to choose.
  if (groups.length == 1) return Future.value(groups.first.entries);
  return Navigator.of(context).push<List<TimetableEntry>>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _PickerPage(groups: groups, programme: programme, year: year),
  ));
}

class _PickerPage extends StatefulWidget {
  const _PickerPage({required this.groups, this.programme, this.year});
  final List<TimetableGroup> groups;
  final String? programme;
  final int? year;
  @override
  State<_PickerPage> createState() => _PickerPageState();
}

class _PickerPageState extends State<_PickerPage> {
  late final List<String> _sheets = widget.groups.map((g) => g.sheet).toSet().toList();
  late String _sheet;
  final _chosen = <TimetableGroup>{};

  @override
  void initState() {
    super.initState();
    final s = TimetableImporter.suggest(widget.groups, programme: widget.programme, year: widget.year);
    _sheet = s.isNotEmpty ? s.first.sheet : _sheets.first;
    _chosen.addAll(s);
  }

  String _name(String sheet) {
    final n = widget.groups.firstWhere((g) => g.sheet == sheet).programmeName;
    return n.isEmpty ? sheet : '$sheet – ${_tidy(n)}';
  }

  static String _tidy(String s) => s
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final inSheet = widget.groups.where((g) => g.sheet == _sheet).toList();
    final count = _chosen.fold<int>(0, (n, g) => n + g.entries.length);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose your classes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Text('This file has timetables for ${_sheets.length} programmes. Pick yours, then your year and semester.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _sheet,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Programme'),
            items: [
              for (final s in _sheets)
                DropdownMenuItem(value: s, child: Text(_name(s), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              _sheet = v!;
              _chosen.clear();
            }),
          ),
          const SizedBox(height: 16),
          Text('Year and semester', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final g in inSheet)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _chosen.contains(g),
              onChanged: (v) => setState(() => v == true ? _chosen.add(g) : _chosen.remove(g)),
              title: Text(g.title.isEmpty ? 'All classes' : _tidy(g.title)),
              subtitle: Text('${g.entries.length} classes · '
                  '${g.entries.map((e) => e.courseCode).take(3).join(', ')}${g.entries.length > 3 ? '…' : ''}'),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: count == 0
                ? null
                : () => Navigator.pop(context, _chosen.expand((g) => g.entries).toList()),
            child: Text(count == 0 ? 'Pick at least one section' : 'Import $count classes'),
          ),
        ),
      ),
    );
  }
}
