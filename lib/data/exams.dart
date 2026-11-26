/// One exam on a real date. Official papers come from the Examinations office;
/// students can add their own (e.g. a retake).
class ExamEntry {
  const ExamEntry({
    required this.id,
    required this.courseCode,
    this.courseName,
    required this.date,
    required this.start,
    required this.end,
    this.room,
    this.campus,
    this.notes,
    this.official = false,
  });
  final String id, courseCode, start, end; // times as HH:MM
  final String? courseName, room, campus, notes;
  final DateTime date; // the day (time part ignored)
  final bool official;

  DateTime get startsAt => _at(start);
  DateTime get endsAt => _at(end);
  DateTime _at(String hhmm) {
    final p = hhmm.split(':');
    return DateTime(date.year, date.month, date.day, int.tryParse(p.first) ?? 0, p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  factory ExamEntry.fromMap(Map<String, dynamic> m, {bool official = false}) => ExamEntry(
        id: m['id'] as String,
        courseCode: m['course_code'] as String,
        courseName: m['course_name'] as String?,
        date: DateTime.parse(m['exam_date'] as String),
        start: (m['start_time'] as String).substring(0, 5),
        end: (m['end_time'] as String).substring(0, 5),
        room: m['room'] as String?,
        campus: m['campus'] as String?,
        notes: m['notes'] as String?,
        official: official,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'course_code': courseCode,
        'course_name': courseName,
        'exam_date': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'start_time': start,
        'end_time': end,
        'room': room,
        'campus': campus,
        if (official) 'notes': notes,
      };
}

/// Exams that overlap: same DATE and overlapping times. Two Thursdays never clash.
Map<String, List<ExamEntry>> findExamClashes(List<ExamEntry> all) {
  final out = <String, List<ExamEntry>>{};
  for (var i = 0; i < all.length; i++) {
    for (var j = i + 1; j < all.length; j++) {
      final a = all[i], b = all[j];
      if (a.startsAt.isBefore(b.endsAt) && b.startsAt.isBefore(a.endsAt)) {
        (out[a.id] ??= []).add(b);
        (out[b.id] ??= []).add(a);
      }
    }
  }
  return out;
}

String _norm(String c) => c.toUpperCase().replaceAll(RegExp(r'\s+'), '');

/// My exams: official papers for my units, plus my own, soonest first.
List<ExamEntry> mergeMyExams({required List<ExamEntry> official, required List<ExamEntry> mine, required Set<String> myUnits}) {
  final units = {for (final u in myUnits) _norm(u)};
  return [...official.where((e) => units.contains(_norm(e.courseCode))), ...mine]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
}
