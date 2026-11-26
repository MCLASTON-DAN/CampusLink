import 'package:campuslink/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 26, 22, 0);
  test('posts never show a bare weekday', () {
    expect(friendlyDate(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
    expect(friendlyDate(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
    expect(friendlyDate(DateTime(2026, 11, 26, 9, 0), now: now), '13 h ago');
    expect(friendlyDate(DateTime(2026, 11, 25, 14, 30), now: now), 'Yesterday at 14:30');
    expect(friendlyDate(DateTime(2026, 11, 24, 14, 30), now: now), '24 Nov at 14:30'); // the "Tuesday" case
    expect(friendlyDate(DateTime(2025, 3, 2, 8, 0), now: now), '2 Mar 2025');
  });
  test('upcoming things say today / tomorrow / date', () {
    expect(scheduledDate(DateTime(2026, 11, 27, 9, 0), now: now), 'Tomorrow, 09:00');
    expect(scheduledDate(DateTime(2026, 11, 29, 10, 0), now: now), 'Sun 29 Nov, 10:00');
    expect(scheduledDate(DateTime(2027, 1, 5, 10, 0), now: now), 'Tue 5 Jan 2027, 10:00');
  });
  test('full date for the tooltip', () {
    expect(fullDate(DateTime(2026, 11, 24, 14, 30)), 'Tuesday 24 November 2026 at 14:30');
  });
}
