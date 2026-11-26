import 'package:campuslink/data/models.dart';
import 'package:campuslink/features/account/account_api.dart';
import 'package:campuslink/features/account/interests.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quiet hours across midnight', () {
    const s = UserSettings(quietStart: '22:00', quietEnd: '06:00');
    expect(s.isQuiet(DateTime(2026, 1, 1, 23, 30)), isTrue);
    expect(s.isQuiet(DateTime(2026, 1, 1, 5, 59)), isTrue);
    expect(s.isQuiet(DateTime(2026, 1, 1, 6, 0)), isFalse);
    expect(s.isQuiet(DateTime(2026, 1, 1, 14, 0)), isFalse);
    expect(s.allows('event', now: DateTime(2026, 1, 1, 23)), isFalse);
    expect(s.allows('request', urgent: true, now: DateTime(2026, 1, 1, 23)), isTrue);
    expect(s.copyWith(kinds: ['course']).allows('event', now: DateTime(2026, 1, 1, 12)), isFalse);
    expect(const UserSettings(quietEnabled: false).isQuiet(DateTime(2026, 1, 1, 23)), isFalse);
  });

  test('settings round trip', () {
    final s = UserSettings.fromMap({'notify_kinds': ['course'], 'quiet_enabled': true, 'quiet_start': '21:30:00', 'quiet_end': '07:00:00'});
    expect(s.quietStart, '21:30');
    expect(s.toMap()['quiet_end'], '07:00');
  });

  test('interests match event words', () {
    expect(matchesInterests('Inter-faculty FOOTBALL final', ['sports']), isTrue);
    expect(matchesInterests('IEEE hackathon weekend', ['tech']), isTrue);
    expect(matchesInterests('Career fair with 20 employers', ['careers']), isTrue);
    expect(matchesInterests('Guild elections debate', ['tech']), isFalse);
    expect(matchesInterests('Repair the main hall', ['arts']), isFalse); // "art" only at word start
  });

  test('profile reads nickname, guest and closing fields', () {
    final p = Profile.fromMap({
      'id': 'x',
      'full_name': 'Okecho Danmark',
      'display_name': 'Dan',
      'account_type': 'guest',
      'access_level': 'visitor',
      'closing_at': '2026-12-26T10:00:00Z',
      'interests': ['tech'],
    });
    expect(p.shownName, 'Dan');
    expect(p.isVisitor, isTrue);
    expect(p.isClosing, isTrue);
    expect(Profile.fromMap(p.toMap()).interests, ['tech']);
    expect(const Profile(id: 'y', fullName: 'Amina').shownName, 'Amina');
  });
}
