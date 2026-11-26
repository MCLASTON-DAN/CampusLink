import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../data/exams.dart';
import 'timetable_import.dart';

/// One block of exams from a file, e.g. sheet "BDSA", "YEAR TWO SEMESTER ONE".
class ExamGroup {
  ExamGroup({required this.sheet, required this.title, required this.entries, this.programmeName = ''});
  final String sheet, title, programmeName;
  final List<ExamEntry> entries;
  String get label => title.isEmpty ? sheet : '$sheet · $title';
}

/// Reads an exam timetable from Excel or CSV, the same way class timetables
/// are read, but every row has a real DATE.
///
/// Understands: a header row with a Date column (plus Time or Start/End,
/// Code, Module/Paper, Room/Venue, Campus); section rows such as
/// "YEAR TWO SEMESTER ONE" that split the sheet into pickable groups; and
/// sheets with no header in the order Date | Time | Code | Module | Room.
class ExamImporter {
  static const _uuid = Uuid();

  static List<ExamGroup> readGroups(Uint8List bytes, {required String fileName}) {
    final out = <ExamGroup>[];
    TimetableImporter.readSheets(bytes, fileName: fileName).forEach((name, rows) => out.addAll(_parseSheet(name, rows)));
    return out;
  }

  /// Picks the groups that match a student's programme and year (same rules as classes).
  static List<ExamGroup> suggest(List<ExamGroup> groups, {String? programme, int? year}) {
    final asClasses = [for (final g in groups) TimetableGroup(sheet: g.sheet, title: g.title, entries: const [], programmeName: g.programmeName)];
    var picked = TimetableImporter.suggest(asClasses, programme: programme, year: year).toSet();
    // One sheet for everyone (no programme sheets): match the year alone.
    if (picked.isEmpty && groups.map((g) => g.sheet).toSet().length == 1 && year != null) {
      const words = {1: 'ONE', 2: 'TWO', 3: 'THREE', 4: 'FOUR', 5: 'FIVE'};
      picked = {
        for (final g in asClasses)
          if (RegExp('YEAR\\s+${words[year]}\\b|YEAR\\s*$year\\b').hasMatch(g.title.toUpperCase())) g
      };
    }
    return [for (var i = 0; i < groups.length; i++) if (picked.contains(asClasses[i])) groups[i]];
  }

  static List<ExamGroup> _parseSheet(String sheet, List<List<String>> rows) {
    final hi = rows.indexWhere((r) {
      final l = r.map((c) => c.toLowerCase().trim()).toList();
      return l.any((c) => c.startsWith('date')) && l.any((c) => c.contains('code') || c.contains('module') || c.contains('paper') || c.contains('course'));
    });
    List<String> h;
    if (hi >= 0) {
      h = rows[hi].map((c) => c.toLowerCase().trim()).toList();
    } else {
      // No header: accept the usual order if enough rows start with a date.
      final dated = rows.where((r) => r.length >= 3 && parseDate(r[0]) != null).length;
      if (dated < 2) return const [];
      h = const ['date', 'time', 'code', 'module', 'room'];
    }
    int col(List<String> keys) => h.indexWhere((x) => keys.any((k) => x == k || x.startsWith(k) || x.contains(k)));
    final cDate = col(['date']), cTime = col(['time', 'session', 'period']);
    final cStart = col(['start', 'from']), cEnd = col(['end', 'to', 'finish']);
    final cCode = col(['code']);
    final cName = col(['module', 'paper', 'course name', 'subject', 'title', 'course']);
    final cRoom = col(['room', 'venue', 'hall']), cCampus = col(['campus']);
    String at(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';

    final progName = rows
        .take(6)
        .expand((r) => r)
        .firstWhere((c) => RegExp(r'BACHELOR|DIPLOMA|MASTER|CERTIFICATE', caseSensitive: false).hasMatch(c), orElse: () => '')
        .trim();
    final groups = <ExamGroup>[];
    var title = '';
    var current = <ExamEntry>[];
    void close() {
      if (current.isNotEmpty) groups.add(ExamGroup(sheet: sheet, title: title, entries: current, programmeName: progName));
      current = <ExamEntry>[];
    }

    DateTime? lastDate; // merged date cells: the date is only on the first row
    for (final r in rows.skip(hi + 1)) {
      if (r.every((c) => c.trim().isEmpty)) continue;
      final rawDate = at(r, cDate);
      final date = parseDate(rawDate) ?? (rawDate.isEmpty ? lastDate : null);
      final slot = cStart >= 0 && cEnd >= 0 && cStart != cTime
          ? _pair(at(r, cStart), at(r, cEnd))
          : parseExamSlot(at(r, cTime));
      final code = at(r, cCode), name = cName == cCode ? '' : at(r, cName);
      if (date == null || slot == null || (code.isEmpty && name.isEmpty)) {
        // A section row like "YEAR TWO SEMESTER ONE" (text, no date, no code).
        final t = r.firstWhere((c) => c.trim().isNotEmpty, orElse: () => '').trim();
        if (t.isNotEmpty && parseDate(t) == null && code.isEmpty && slot == null) {
          close();
          title = t.replaceAll(RegExp(r'\s+'), ' ');
          lastDate = null;
        }
        continue;
      }
      lastDate = date;
      current.add(ExamEntry(
        id: _uuid.v4(),
        courseCode: (code.isEmpty ? name : code).toUpperCase(),
        courseName: name.isEmpty ? null : name,
        date: date,
        start: slot.$1,
        end: slot.$2,
        room: at(r, cRoom).isEmpty ? null : at(r, cRoom),
        campus: at(r, cCampus).isEmpty ? null : at(r, cCampus),
      ));
    }
    close();
    return groups;
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Excel date numbers, 07/12/2026 (day first, as in Uganda), 2026-12-07,
  /// "Monday 7th December 2026", "7-Dec-26", "Dec 7, 2026".
  static DateTime? parseDate(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    // Excel stores dates as days since 30 Dec 1899.
    final n = double.tryParse(s);
    if (n != null) {
      if (n < 30000 || n > 80000) return null; // 1982..2119, so codes like 2207 aren't dates
      return DateTime(1899, 12, 30).add(Duration(days: n.floor()));
    }
    var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (m != null) return _ok(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    m = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})$').firstMatch(s);
    if (m != null) return _ok(_year(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
    // Words: find a day number, a month name and maybe a year.
    final month = RegExp(r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*').firstMatch(s);
    if (month == null) return null;
    final nums = RegExp(r'\d+').allMatches(s).map((x) => x[0]!).toList();
    final day = nums.where((x) => x.length <= 2 && int.parse(x) >= 1 && int.parse(x) <= 31).firstOrNull;
    if (day == null) return null;
    final yearText = nums.where((x) => x.length == 4 || (x.length == 2 && x != day)).lastOrNull;
    final mo = _months[month[1]!]!;
    if (yearText != null) return _ok(_year(yearText), mo, int.parse(day));
    // No year written: the next time that date comes round.
    final now = DateTime.now();
    final d = DateTime(now.year, mo, int.parse(day));
    return d.isBefore(now.subtract(const Duration(days: 60))) ? DateTime(now.year + 1, mo, int.parse(day)) : d;
  }

  static int _year(String y) => y.length == 2 ? 2000 + int.parse(y) : int.parse(y);
  static DateTime? _ok(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final t = DateTime(y, m, d);
    return t.month == m ? t : null; // 31/02 is not a date
  }

  /// "9:00-12:00", "9.00am - 12.00pm", "MORNING", "Afternoon (2:00-5:00)".
  static (String, String)? parseExamSlot(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final inside = RegExp(r'\(([^)]*)\)').firstMatch(s)?.group(1);
    final direct = TimetableImporter.parseSlot(inside ?? s);
    if (direct != null) return direct;
    final l = s.toLowerCase();
    if (l.startsWith('morning') || l == 'am') return ('09:00', '12:00');
    if (l.startsWith('afternoon') || l == 'pm') return ('14:00', '17:00');
    if (l.startsWith('evening')) return ('17:30', '20:30');
    return null;
  }

  static (String, String)? _pair(String a, String b) {
    String? t(String x) {
      final f = double.tryParse(x); // Excel time = fraction of a day
      if (f != null && f > 0 && f < 1) {
        final mins = (f * 24 * 60).round();
        return '${(mins ~/ 60).toString().padLeft(2, '0')}:${(mins % 60).toString().padLeft(2, '0')}';
      }
      return TimetableImporter.normalizeTime(x);
    }

    final s = t(a), e = t(b);
    return s == null || e == null || e.compareTo(s) <= 0 ? null : (s, e);
  }
}
