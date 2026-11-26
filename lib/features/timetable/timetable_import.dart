import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';

import '../../data/models.dart';
import 'xlsx_reader.dart';

/// One block of classes from a timetable file, e.g. sheet "BDSA",
/// section "YEAR ONE SEMESTER ONE".
class TimetableGroup {
  TimetableGroup({required this.sheet, required this.title, required this.entries, this.programmeName = ''});
  final String sheet;
  /// Full programme name from the sheet, e.g. "BACHELORS-DATA SCIENCE AND ARTIFICIAL INTELLIGENCE".
  final String programmeName;
  final String title;
  final List<TimetableEntry> entries;
  String get label => title.isEmpty ? sheet : '$sheet · $title';
}

/// Reads CSV or Excel timetables.
///
/// Understands three layouts:
///  1. **Official Cavendish style**: one sheet per programme, a header row
///     "Day | Time | Code | Module | Room | Lecturer", and section rows such as
///     "YEAR ONE SEMESTER ONE". Each section becomes a [TimetableGroup] the
///     student can pick.
///  2. **Row per class**: columns like course_code, day, start, end, room.
///  3. **Grid**: first column = time slots, header row = days.
class TimetableImporter {
  static const _uuid = Uuid();

  /// Every sheet of a CSV or Excel file as rows of trimmed text.
  static Map<String, List<List<String>>> readSheets(Uint8List bytes, {required String fileName}) {
    final lower = fileName.toLowerCase();
    final Map<String, List<List<String>>> sheets;
    if (lower.endsWith('.csv') || lower.endsWith('.tsv') || lower.endsWith('.txt')) {
      final text = String.fromCharCodes(bytes);
      final sep = lower.endsWith('.tsv') || text.split('\n').first.contains('\t') ? '\t' : ',';
      sheets = {
        'File': const CsvToListConverter(shouldParseNumbers: false)
            .convert(text.replaceAll('\r\n', '\n'), fieldDelimiter: sep, eol: '\n')
            .map((r) => r.map((c) => c.toString().trim()).toList())
            .toList(),
      };
    } else if (lower.endsWith('.xlsx') || lower.endsWith('.xlsm')) {
      sheets = readXlsx(bytes);
    } else {
      throw UnsupportedError(
        'Only .csv, .tsv and .xlsx files can be read on-device. '
        'Export your PDF/Word timetable to Excel or CSV first, or add classes manually.',
      );
    }

    return sheets;
  }

  /// Public form of the slot reader: "08:00-10:00", "9.00am - 12.00pm".
  static (String, String)? parseSlot(String s) => _slot(s);

  /// Reads a whole file into pickable groups.
  static List<TimetableGroup> readGroups(Uint8List bytes, {required String fileName}) {
    final sheets = readSheets(bytes, fileName: fileName);

    final official = <TimetableGroup>[];
    final other = <TimetableGroup>[];
    sheets.forEach((name, rows) {
      final o = _parseOfficial(name, rows);
      if (o.isNotEmpty) {
        official.addAll(o);
        return;
      }
      final clean = rows.where((r) => r.any((c) => c.isNotEmpty)).toList();
      if (clean.isEmpty) return;
      final header = clean.first.map((h) => h.toLowerCase()).toList();
      final isRowLayout = header.any((h) => h.contains('course') || h.contains('unit') || h.contains('code')) &&
          header.any((h) => h.contains('day'));
      final e = isRowLayout ? _parseRows(clean) : _parseGrid(clean);
      if (e.isNotEmpty) other.add(TimetableGroup(sheet: name, title: '', entries: e));
    });
    // A file in the official style: only offer the programme sections.
    return official.isNotEmpty ? official : other;
  }

  /// Picks the groups that best match a student's programme and year.
  /// Returns an empty list when nothing matches clearly.
  static List<TimetableGroup> suggest(List<TimetableGroup> groups, {String? programme, int? year}) {
    if (programme == null || programme.trim().isEmpty) return const [];
    final p = programme.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    bool sheetMatches(String sheet) {
      final s = sheet.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
      return s.isNotEmpty && (s == p || p.startsWith(s) || s.startsWith(p));
    }
    // Prefer the closest sheet name (BDSA for BDSAI, not DDSA).
    final sheets = groups.map((g) => g.sheet).where(sheetMatches).toSet().toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (sheets.isEmpty) return const [];
    final inSheet = groups.where((g) => g.sheet == sheets.first).toList();
    if (year == null) return inSheet;
    const words = {1: 'ONE', 2: 'TWO', 3: 'THREE', 4: 'FOUR', 5: 'FIVE'};
    final w = words[year];
    final byYear = inSheet.where((g) {
      final t = g.title.toUpperCase();
      return (w != null && RegExp('YEAR\\s+$w\\b').hasMatch(t)) || RegExp('YEAR\\s*$year\\b').hasMatch(t);
    }).toList();
    return byYear.isEmpty ? inSheet : byYear;
  }

  /// Older one-step API: everything in the file, optionally filtered by course text.
  static List<TimetableEntry> parse(
    Uint8List bytes, {
    required String fileName,
    List<String> courseFilter = const [],
  }) {
    final entries = readGroups(bytes, fileName: fileName).expand((g) => g.entries).toList();
    if (courseFilter.isEmpty) return entries;
    final f = courseFilter.map((c) => c.toLowerCase()).toList();
    final filtered = entries
        .where((e) => f.any((c) =>
            e.courseCode.toLowerCase().contains(c) || (e.courseName ?? '').toLowerCase().contains(c)))
        .toList();
    return filtered.isEmpty ? entries : filtered;
  }

  // ---- official layout ----
  static List<TimetableGroup> _parseOfficial(String sheet, List<List<String>> rows) {
    final hi = rows.indexWhere((r) {
      final l = r.map((c) => c.toLowerCase()).toList();
      return l.contains('day') && l.contains('time') && l.any((c) => c == 'code' || c == 'module');
    });
    // Many sheets have no header row at all: then use the usual column order
    // Day | Time | Code | Module | Room | Lecturer, if enough rows look like that.
    final List<String> h;
    if (hi >= 0) {
      h = rows[hi].map((c) => c.toLowerCase()).toList();
    } else {
      final looksRight = rows
          .where((r) => r.length >= 4 && parseDay(r[0]) != null && _slot(r[1]) != null)
          .length;
      if (looksRight < 3) return const [];
      h = const ['day', 'time', 'code', 'module', 'room', 'lecturer'];
    }
    int col(List<String> keys) => h.indexWhere((x) => keys.any((k) => x == k || x.startsWith(k)));
    final cDay = col(['day']), cTime = col(['time']), cCode = col(['code']);
    final cName = col(['module', 'course', 'title']), cRoom = col(['room', 'venue']);
    final cLect = col(['lecturer', 'instructor', 'tutor']);
    String at(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';

    final progName = rows
        .take(6)
        .expand((r) => r)
        .firstWhere((c) => RegExp(r'BACHELOR|DIPLOMA|MASTER|CERTIFICATE|HIGHER EDUCATION', caseSensitive: false).hasMatch(c),
            orElse: () => '')
        .trim();
    final groups = <TimetableGroup>[];
    var title = '';
    var current = <TimetableEntry>[];
    void close() {
      if (current.isNotEmpty) groups.add(TimetableGroup(sheet: sheet, title: title, entries: current, programmeName: progName));
      current = <TimetableEntry>[];
    }

    for (final r in rows.skip(hi + 1)) { // hi is -1 when there is no header
      final day = parseDay(at(r, cDay));
      final slot = _slot(at(r, cTime));
      if (day == null || slot == null) {
        // A section row like "YEAR ONE SEMESTER ONE".
        final t = r.firstWhere((c) => c.trim().isNotEmpty, orElse: () => '').trim();
        if (t.isNotEmpty && day == null) {
          close();
          title = t.replaceAll(RegExp(r'\s+'), ' ');
        }
        continue;
      }
      final code = at(r, cCode);
      final name = at(r, cName);
      if (code.isEmpty && name.isEmpty) continue;
      current.add(TimetableEntry(
        id: _uuid.v4(),
        courseCode: code.isEmpty ? name : code,
        courseName: name.isEmpty ? null : name,
        dayOfWeek: day,
        startTime: slot.$1,
        endTime: slot.$2,
        room: at(r, cRoom).isEmpty ? null : at(r, cRoom),
        lecturer: at(r, cLect).isEmpty ? null : at(r, cLect),
        source: 'import',
      ));
    }
    close();
    return groups;
  }

  /// "08:00-10:00" or "12:30-02:30" (afternoon written without pm) -> 24h times.
  static (String, String)? _slot(String s) {
    final parts = s.split(RegExp(r'\s*[-–]\s*'));
    if (parts.length != 2) return null;
    var a = normalizeTime(parts[0]);
    var b = normalizeTime(parts[1]);
    if (a == null || b == null) return null;
    final hasAmPm = RegExp('am|pm', caseSensitive: false).hasMatch(s);
    if (!hasAmPm) {
      // Classes run 7am-9pm, so "02:30" means 14:30.
      a = _afternoon(a);
      b = _afternoon(b);
    }
    if (b.compareTo(a) <= 0) b = _plusHours(b, 12);
    return (a, b);
  }

  static String _afternoon(String hhmm) {
    final h = int.parse(hhmm.substring(0, 2));
    return h >= 1 && h <= 6 ? _plusHours(hhmm, 12) : hhmm;
  }

  // ---- layout 1 ----
  static List<TimetableEntry> _parseRows(List<List<String>> rows) {
    final h = rows.first.map((x) => x.toLowerCase()).toList();
    int col(List<String> keys) => h.indexWhere((x) => keys.any((k) => x.contains(k)));
    final cCode = col(['code', 'course', 'unit']);
    final cName = col(['name', 'title', 'description']);
    final cDay = col(['day']);
    final cStart = col(['start', 'from', 'time']);
    final cEnd = col(['end', 'to']);
    final cRoom = col(['room', 'venue', 'hall', 'lab', 'location']);
    final cLect = col(['lecturer', 'teacher', 'instructor', 'tutor']);

    String at(List<String> r, int i) => i >= 0 && i < r.length ? r[i] : '';
    final out = <TimetableEntry>[];
    for (final r in rows.skip(1)) {
      final day = parseDay(at(r, cDay));
      if (day == null) continue;
      var start = normalizeTime(at(r, cStart));
      var end = normalizeTime(at(r, cEnd));
      // "08:00-10:00" in a single "time" column
      if (end == null && at(r, cStart).contains('-')) {
        final sl = _slot(at(r, cStart));
        start = sl?.$1;
        end = sl?.$2;
      }
      if (start == null) continue;
      final code = at(r, cCode);
      if (code.isEmpty) continue;
      out.add(TimetableEntry(
        id: _uuid.v4(),
        courseCode: code,
        courseName: cName >= 0 && cName != cCode ? at(r, cName) : null,
        dayOfWeek: day,
        startTime: start,
        endTime: end ?? _plusHours(start, 2),
        room: at(r, cRoom).isEmpty ? null : at(r, cRoom),
        lecturer: at(r, cLect).isEmpty ? null : at(r, cLect),
        source: 'import',
      ));
    }
    return out;
  }

  // ---- layout 2 ----
  static List<TimetableEntry> _parseGrid(List<List<String>> rows) {
    final header = rows.first;
    final dayCols = <int, int>{};
    for (var i = 1; i < header.length; i++) {
      final d = parseDay(header[i]);
      if (d != null) dayCols[i] = d;
    }
    if (dayCols.isEmpty) return const [];
    final out = <TimetableEntry>[];
    for (final r in rows.skip(1)) {
      if (r.isEmpty) continue;
      final slot = r[0].split(RegExp(r'\s*[-–]\s*'));
      final start = normalizeTime(slot[0]);
      if (start == null) continue;
      final end = slot.length > 1 ? normalizeTime(slot[1]) : null;
      dayCols.forEach((ci, day) {
        if (ci >= r.length || r[ci].isEmpty) return;
        final text = r[ci];
        final codeMatch = RegExp(r'[A-Z]{2,5}\s?\d{3,4}').firstMatch(text);
        final roomMatch = RegExp(r'(?:room|lab|lt|hall)\s*\w+', caseSensitive: false).firstMatch(text);
        out.add(TimetableEntry(
          id: _uuid.v4(),
          courseCode: codeMatch?.group(0)?.replaceAll(' ', '') ?? text.split(RegExp(r'[\n,;]')).first.trim(),
          courseName: codeMatch == null ? null : text.replaceFirst(codeMatch.group(0)!, '').replaceAll(RegExp(r'[\n;,]+'), ' ').trim(),
          dayOfWeek: day,
          startTime: start,
          endTime: end ?? _plusHours(start, 2),
          room: roomMatch?.group(0),
          source: 'import',
        ));
      });
    }
    return out;
  }

  // ---- helpers ----
  static int? parseDay(String s) {
    final t = s.toLowerCase().trim();
    if (t.isEmpty) return null;
    const map = {
      'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7,
    };
    for (final e in map.entries) {
      if (t.startsWith(e.key)) return e.value;
    }
    final n = int.tryParse(t);
    return n != null && n >= 1 && n <= 7 ? n : null;
  }

  /// "8", "8am", "08:00", "8.30", "14h00", "2:30 pm" → "HH:mm"
  static String? normalizeTime(String s) {
    final t = s.toLowerCase().replaceAll(RegExp(r'\s'), '').replaceAll('h', ':').replaceAll('.', ':');
    final m = RegExp(r'^(\d{1,2})(?::(\d{2}))?(am|pm)?$').firstMatch(t);
    if (m == null) return null;
    var h = int.parse(m.group(1)!);
    final mm = m.group(2) ?? '00';
    final ap = m.group(3);
    if (ap == 'pm' && h < 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    if (h > 23) return null;
    return '${h.toString().padLeft(2, '0')}:$mm';
  }

  static String _plusHours(String hhmm, int hours) {
    final h = (int.parse(hhmm.substring(0, 2)) + hours).clamp(0, 23);
    return '${h.toString().padLeft(2, '0')}${hhmm.substring(2)}';
  }
}
