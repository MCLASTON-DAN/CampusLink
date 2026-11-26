import '../../data/exams.dart';
import '../../data/models.dart';

/// One weekly reminder: fires every [weekday] (1 = Monday) at [hour]:[minute],
/// Kampala time.
class ClassReminder {
  const ClassReminder({required this.id, required this.weekday, required this.hour, required this.minute,
      required this.title, required this.body});
  final int id, weekday, hour, minute;
  final String title, body;

  @override
  String toString() => '$id:$weekday:$hour:$minute:$title:$body';
}

/// Reminder ids live in their own range so they never clash with pop-ups.
const reminderIdBase = 70000;

/// Works out the weekly reminders for a timetable, [minutesBefore] each class.
/// Pure: no device calls, so it can be tested.
List<ClassReminder> planClassReminders(List<TimetableEntry> entries, int minutesBefore) {
  if (minutesBefore <= 0) return const [];
  final sorted = [...entries]..sort((a, b) =>
      a.dayOfWeek != b.dayOfWeek ? a.dayOfWeek.compareTo(b.dayOfWeek) : a.startTime.compareTo(b.startTime));
  final out = <ClassReminder>[];
  for (final e in sorted) {
    final parts = e.startTime.split(':');
    final h = int.tryParse(parts.first);
    final m = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    if (h == null || m == null || e.dayOfWeek < 1 || e.dayOfWeek > 7) continue; // bad row: skip, never crash
    // Minutes since Monday 00:00, minus the warning, wrapped round the week.
    const week = 7 * 24 * 60;
    final at = (((e.dayOfWeek - 1) * 24 * 60 + h * 60 + m - minutesBefore) % week + week) % week;
    final name = (e.courseName ?? '').trim().isEmpty ? e.courseCode : '${e.courseCode} · ${e.courseName}';
    out.add(ClassReminder(
      id: reminderIdBase + out.length,
      weekday: at ~/ (24 * 60) + 1,
      hour: (at % (24 * 60)) ~/ 60,
      minute: at % 60,
      title: 'Class in $minutesBefore min: $name',
      body: [
        '${e.startTime}–${e.endTime}',
        if ((e.room ?? '').trim().isNotEmpty) 'Room ${e.room!.trim()}',
        if ((e.lecturer ?? '').trim().isNotEmpty) e.lecturer!.trim(),
      ].join(' · '),
    ));
  }
  return out;
}

/// One-off exam reminders live in their own id range.
const examReminderIdBase = 80000;

class ExamReminder {
  const ExamReminder(this.id, this.at, this.title, this.body);
  final int id;
  final DateTime at; // Kampala wall-clock time
  final String title, body;
  @override
  String toString() => '$id:${at.toIso8601String()}:$title';
}

/// The evening before (19:00) and 1 hour before each exam, future ones only.
List<ExamReminder> planExamReminders(List<ExamEntry> exams, DateTime now) {
  final out = <ExamReminder>[];
  for (final e in exams) {
    final where = [if ((e.room ?? '').isNotEmpty) e.room!, if ((e.campus ?? '').isNotEmpty) e.campus!].join(', ');
    final eve = DateTime(e.date.year, e.date.month, e.date.day - 1, 19);
    final hour = e.startsAt.subtract(const Duration(hours: 1));
    if (eve.isAfter(now)) {
      out.add(ExamReminder(examReminderIdBase + out.length, eve, 'Exam tomorrow: ${e.courseCode}',
          'Starts ${e.start}${where.isEmpty ? '' : ' · $where'}. Bring your exam card.'));
    }
    if (hour.isAfter(now)) {
      out.add(ExamReminder(examReminderIdBase + out.length, hour, 'Exam in 1 hour: ${e.courseCode}',
          '${e.start}–${e.end}${where.isEmpty ? '' : ' · $where'}'));
    }
  }
  return out;
}
