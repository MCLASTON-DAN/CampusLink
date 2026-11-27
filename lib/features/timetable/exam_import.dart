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
/// Files from different offices look different, so each row is read by what
/// its cells contain, not by where they are:
///   * a date  ("Sat | 05-Dec", "07/12/2026", "Monday 7th December 2026", Excel numbers)
///   * a time  ("09:00-12:00", "2.00pm - 5.00pm", "MORNING")
///   * a course code ("BDA1101", "LLM 711", "IRDS-316")
/// A heading row (Date or Day, Time, Code, Module, Room, Campus, Lecturer)
/// is used when there is one, to name the other cells. Rows whose columns
/// are shifted still read correctly, and sheets without headings work too.
/// Section rows such as "YEAR TWO SEMESTER ONE" split a sheet into pickable
/// groups. A date written once for several rows (merged cells) carries down.
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

  // BDA1101, LLM 711, IRDS-316, and variants with a suffix like BJC110-HS.
  static final _code = RegExp(r'^[A-Z]{2,6}[ -]?\d{3,4}[A-Z]?(-[A-Z]{1,4})?$');
  static final _section =
      RegExp(r'\b(YEAR|SEMESTER|LEVEL|GROUP|STREAM|INTAKE|COHORT|WEEKEND|EVENING|MODULAR|PART)\b', caseSensitive: false);
  static final _person = RegExp(r'^(dr|mr|mrs|ms|miss|prof|assoc|eng|rev|sr|fr)\b\.?', caseSensitive: false);

  /// The course codes in a cell: "BDA1101", "LLM 711", or a paper shared by
  /// several programmes, "BIT122/BSE121/DDA1204". Empty if it isn't codes.
  static List<String> courseCodes(String cell) {
    final parts = cell.trim().toUpperCase().split(RegExp(r'\s*(?:/|,|;|&|\bAND\b)\s*')).where((x) => x.isNotEmpty).toList();
    if (parts.isEmpty || !parts.every(_code.hasMatch)) return const [];
    // Same rule as the rest of CampusLink (norm_code): capitals, no spaces.
    return [for (final x in parts) x.replaceAll(RegExp(r'\s+'), '')];
  }

  static bool isCourseCode(String s) => courseCodes(s).isNotEmpty;

  static List<ExamGroup> _parseSheet(String sheet, List<List<String>> rows) {
    final head = _Heading.find(rows);
    final progName = rows
        .take(6)
        .expand((r) => r)
        .firstWhere((c) => RegExp(r'BACHELOR|DIPLOMA|MASTER|CERTIFICATE|DOCTOR', caseSensitive: false).hasMatch(c), orElse: () => '')
        .trim();

    final groups = <ExamGroup>[];
    var title = '';
    var current = <ExamEntry>[];
    final seen = <String>{};
    void close() {
      if (current.isNotEmpty) groups.add(ExamGroup(sheet: sheet, title: title, entries: current, programmeName: progName));
      current = <ExamEntry>[];
    }

    DateTime? lastDate; // merged date cells: the date is only on the first row
    for (final r in rows.skip(head == null ? 0 : head.row + 1)) {
      if (r.every((c) => c.trim().isEmpty)) continue;
      final row = _readRow(r, head);
      if (row == null) {
        // Not an exam. A short text row may start a new section.
        // Ignore stray cells: numbers and Excel errors like "#REF!".
        final words = {
          for (final c in r)
            if (RegExp('[A-Za-z]{2}').hasMatch(c) && !c.trim().startsWith('#')) c.trim().replaceAll(RegExp(r'\s+'), ' ')
        };
        final text = words.join(' ');
        final isSection = words.length <= 2 &&
            text.length <= 80 &&
            RegExp('[A-Za-z]').hasMatch(text) &&
            !words.any((w) => isCourseCode(w) || _looksLikeDate(w) || parseExamSlot(w) != null) &&
            (_section.hasMatch(text) || current.isNotEmpty || groups.isNotEmpty || head != null);
        if (isSection) {
          close();
          title = text;
          lastDate = null;
        }
        continue;
      }
      final date = row.date ?? lastDate;
      if (date == null) continue;
      lastDate = date;
      // A shared paper becomes one exam per code, so each programme's students get it.
      for (final code in row.codes) {
        if (!seen.add('$title|$code|${date.toIso8601String()}|${row.slot.$1}')) continue; // same exam twice
        current.add(ExamEntry(
          id: _uuid.v4(),
          courseCode: code,
          courseName: row.name,
          date: date,
          start: row.slot.$1,
          end: row.slot.$2,
          room: row.room,
          campus: row.campus,
          notes: row.lecturer == null ? null : 'Lecturer: ${row.lecturer}',
        ));
      }
    }
    close();
    return groups;
  }

  /// One exam from one row, or null if the row isn't an exam.
  static _Row? _readRow(List<String> raw, _Heading? h) {
    final cells = [for (final c in raw) c.trim()];
    String at(int i) => i >= 0 && i < cells.length ? cells[i] : '';

    // 1. The course code anchors the row. If this row is shifted against the
    //    heading (extra or missing cells in front), move the heading with it.
    var codeAt = h != null && isCourseCode(at(h.code)) ? h.code : cells.indexWhere(isCourseCode);
    final shift = h != null && h.code >= 0 && codeAt >= 0 ? codeAt - h.code : 0;
    int col(int i) => i < 0 ? -1 : i + shift;

    // 2. The time: the heading's column, a Start/End pair, or any time cell.
    (String, String)? slot;
    var slotAt = -1;
    if (h != null && h.start >= 0 && h.end >= 0) {
      slot = _pair(at(col(h.start)), at(col(h.end)));
      if (slot != null) slotAt = col(h.start);
    }
    if (slot == null && h != null && (slot = parseExamSlot(at(col(h.time)))) != null) slotAt = col(h.time);
    if (slot == null) {
      for (var i = 0; i < cells.length; i++) {
        if (i == codeAt) continue;
        final s = parseExamSlot(cells[i]);
        if (s != null) {
          slot = s;
          slotAt = i;
          break;
        }
      }
    }
    if (slot == null) return null;

    // 3. The date: the heading's column, else the date cell nearest the time
    //    (some files have other dates further along the row).
    DateTime? date;
    var dateAt = -1;
    if (h != null && (date = parseDate(at(col(h.date)))) != null) dateAt = col(h.date);
    if (date == null) {
      var best = 1 << 30;
      for (var i = 0; i < cells.length; i++) {
        if (i == codeAt || i == slotAt || !_looksLikeDate(cells[i])) continue;
        final d = parseDate(cells[i]);
        if (d != null && (i - slotAt).abs() < best) {
          best = (i - slotAt).abs();
          date = d;
          dateAt = i;
        }
      }
    }

    // 4. The paper's name: the heading's column, else the first text after the code.
    bool free(int i) => i != codeAt && i != slotAt && i != dateAt && at(i).isNotEmpty;
    var nameAt = h != null && free(col(h.name)) && !isCourseCode(at(col(h.name))) ? col(h.name) : -1;
    if (nameAt < 0) {
      for (var i = codeAt < 0 ? 0 : codeAt + 1; i < cells.length; i++) {
        if (free(i) && !isCourseCode(cells[i]) && !_looksLikeDate(cells[i]) && RegExp('[A-Za-z]{3}').hasMatch(cells[i])) {
          nameAt = i;
          break;
        }
      }
    }
    if (codeAt < 0 && nameAt < 0) return null;

    String? pick(int i) => i >= 0 && free(i) && i != nameAt ? at(i) : null;
    // Without a heading: room is the cell after the name, lecturer is the one with a title (Dr, Mr…).
    final room = h != null && h.room >= 0 ? pick(col(h.room)) : pick(nameAt + 1);
    final campus = h != null && h.campus >= 0 ? pick(col(h.campus)) : null;
    var lecturer = h != null && h.lecturer >= 0 ? pick(col(h.lecturer)) : null;
    if (lecturer == null && h == null) {
      for (var i = nameAt + 1; i < cells.length; i++) {
        if (free(i) && _person.hasMatch(cells[i])) {
          lecturer = cells[i];
          break;
        }
      }
    }
    return _Row(
      codes: codeAt >= 0 ? courseCodes(at(codeAt)) : [at(nameAt).toUpperCase()],
      name: nameAt >= 0 ? at(nameAt) : null,
      date: date,
      slot: slot,
      room: room,
      campus: campus,
      lecturer: lecturer,
    );
  }

  /// A cheap check before parseDate when guessing which cell is the date, so
  /// a paper called "Decision Analysis 2" isn't read as 2 December.
  static bool _looksLikeDate(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty || s.length > 40) return false;
    if (RegExp(r'^\d{5}(\.\d+)?$').hasMatch(s)) return true; // Excel date number
    if (RegExp(r'^\d{4}-\d{1,2}-\d{1,2}|^\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}$').hasMatch(s)) return true;
    final hasMonth = RegExp(r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)').hasMatch(s);
    return hasMonth && (_weekday.hasMatch(s) || RegExp(r'\d{4}').hasMatch(s) || RegExp(r'^\d{1,2}(st|nd|rd|th)?[\s\-/.]*[a-z]').hasMatch(s));
  }

  static final _weekday = RegExp(r'\b(mon|tue|wed|thu|fri|sat|sun)[a-z]*\b');
  static const _weekdays = {'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7};

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
    return _guessYear(mo, int.parse(day), _weekday.firstMatch(s)?.group(1), DateTime.now());
  }

  /// No year written ("Sat | 05-Dec"). If a weekday is given, the year where
  /// that date falls on that weekday (nearest to today); otherwise the next
  /// time the date comes round (up to 60 days back counts as this season).
  static DateTime? _guessYear(int month, int day, String? weekday, DateTime now) {
    final wanted = weekday == null ? null : _weekdays[weekday];
    if (wanted != null) {
      final fits = [
        for (final y in [now.year, now.year + 1, now.year - 1])
          if (_ok(y, month, day)?.weekday == wanted) _ok(y, month, day)!
      ];
      if (fits.isNotEmpty) return fits.first;
    }
    final d = _ok(now.year, month, day);
    if (d == null) return null;
    return d.isBefore(now.subtract(const Duration(days: 60))) ? _ok(now.year + 1, month, day) : d;
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


/// Which column holds what, from a heading row like
/// "Day | Time | Code | Module | Campus | Room | Lecturer".
class _Heading {
  const _Heading(this.row, {this.date = -1, this.time = -1, this.start = -1, this.end = -1, this.code = -1, this.name = -1,
      this.room = -1, this.campus = -1, this.lecturer = -1});
  final int row, date, time, start, end, code, name, room, campus, lecturer;

  static _Heading? find(List<List<String>> rows) {
    for (var i = 0; i < rows.length && i < 25; i++) {
      final l = [for (final c in rows[i]) c.toLowerCase().trim()];
      int col(List<String> starts, {List<String> exact = const [], int not = -1}) => l.indexWhere(
          (x) => x.isNotEmpty && (exact.contains(x) || starts.any(x.startsWith)) && l.indexOf(x) != not);
      final date = col(['date', 'day', 'exam date', 'exam day']);
      final code = col(['code', 'course code', 'unit code', 'module code', 'paper code', 'subject code']);
      final name = col(['module', 'paper', 'course', 'subject', 'unit', 'title', 'description'], not: code);
      if (date < 0 || (code < 0 && name < 0)) continue;
      return _Heading(
        i,
        date: date,
        time: col(['time', 'session', 'period', 'slot']),
        start: col(['start', 'from']),
        end: col(['end', 'finish'], exact: ['to']),
        code: code,
        name: name,
        room: col(['room', 'venue', 'hall', 'location', 'centre', 'center']),
        campus: col(['campus']),
        lecturer: col(['lecturer', 'examiner', 'invigilator', 'tutor', 'teacher']),
      );
    }
    return null;
  }
}

class _Row {
  const _Row({required this.codes, required this.slot, this.date, this.name, this.room, this.campus, this.lecturer});
  final List<String> codes;
  final (String, String) slot;
  final DateTime? date;
  final String? name, room, campus, lecturer;
}
