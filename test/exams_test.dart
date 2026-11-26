import 'package:campuslink/core/notify/class_reminders.dart';
import 'package:campuslink/data/exams.dart';
import 'package:flutter_test/flutter_test.dart';

ExamEntry ex(String id, DateTime d, String s, String e, [String code = 'X']) =>
    ExamEntry(id: id, courseCode: code, date: d, start: s, end: e);

void main() {
  test('two Thursdays at the same time do not clash; the same Thursday does', () {
    final thu1 = DateTime(2026, 12, 3), thu2 = DateTime(2026, 12, 10);
    final c = findExamClashes([
      ex('a', thu1, '09:00', '12:00'),
      ex('b', thu2, '09:00', '12:00'),
      ex('c', thu1, '11:00', '13:00'),
      ex('d', thu1, '12:00', '14:00'), // starts when a ends: fine
    ]);
    expect(c['a']!.map((x) => x.id), ['c']);
    expect(c.containsKey('b'), isFalse);
    expect(c['d']!.map((x) => x.id), ['c']);
  });

  test('my exams = official papers for my units + my own, soonest first', () {
    final list = mergeMyExams(
      official: [ex('o1', DateTime(2026, 12, 5), '09:00', '11:00', 'BDA 2207'), ex('o2', DateTime(2026, 12, 1), '09:00', '11:00', 'LAW101')],
      mine: [ex('m1', DateTime(2026, 12, 2), '14:00', '16:00', 'RETAKE')],
      myUnits: {'bda2207'},
    );
    expect(list.map((e) => e.id), ['m1', 'o1']);
  });

  test('reminders: evening before and 1 hour before, never in the past', () {
    final now = DateTime(2026, 12, 4, 20);
    final r = planExamReminders([ex('a', DateTime(2026, 12, 5), '09:00', '12:00'), ex('b', DateTime(2026, 12, 7), '14:00', '16:00')], now);
    expect(r.map((x) => x.at), [DateTime(2026, 12, 5, 8), DateTime(2026, 12, 6, 19), DateTime(2026, 12, 7, 13)]);
  });
}
