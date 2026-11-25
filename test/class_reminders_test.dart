import 'package:campuslink/core/notify/class_reminders.dart';
import 'package:campuslink/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

TimetableEntry t(int day, String start, {String code = 'BDS101', String? room}) =>
    TimetableEntry(id: '$day$start', courseCode: code, dayOfWeek: day, startTime: start, endTime: '10:00', room: room);

void main() {
  test('15 min before Monday 08:00 is Monday 07:45, with room in the text', () {
    final r = planClassReminders([t(1, '08:00', room: 'Lab 2')], 15).single;
    expect((r.weekday, r.hour, r.minute), (1, 7, 45));
    expect(r.title, contains('15 min'));
    expect(r.body, contains('Room Lab 2'));
  });

  test('a warning before Monday just after midnight goes back to Sunday night', () {
    final r = planClassReminders([t(1, '00:10')], 30).single;
    expect((r.weekday, r.hour, r.minute), (7, 23, 40));
  });

  test('off means none; bad rows are skipped; ids are unique and in their own range', () {
    expect(planClassReminders([t(2, '09:00')], 0), isEmpty);
    final list = planClassReminders([t(3, '14:00'), t(9, '08:00'), t(2, 'xx'), t(2, '09:00')], 10);
    expect(list.length, 2);
    expect(list.first.weekday, 2, reason: 'sorted by day');
    expect(list.map((r) => r.id).toSet().length, 2);
    expect(list.every((r) => r.id >= reminderIdBase), isTrue);
  });
}
