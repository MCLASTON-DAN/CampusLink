import 'package:campuslink/features/account/account_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a signed-in device reads its name, times and kind', () {
    final d = SignedInDevice.fromMap({
      'id': 's1',
      'device': 'Samsung SM-A515F (CampusLink app)',
      'signed_in_at': '2026-11-27T16:26:00Z',
      'last_active_at': '2026-11-27T16:30:00Z',
      'ip': '41.210.1.2',
      'current': true,
    });
    expect(d.isThisDevice, isTrue);
    expect(d.isApp, isTrue);
    expect(d.isPhone, isTrue);
    expect(d.lastActiveAt.isAfter(d.signedInAt), isTrue);
    final web = SignedInDevice.fromMap({
      'id': 's2',
      'device': 'Chrome on Windows',
      'signed_in_at': '2026-11-27T16:26:00Z',
      'last_active_at': '2026-11-27T16:26:00Z',
      'current': false,
    });
    expect(web.isPhone, isFalse);
    expect(web.ip, isNull);
  });
}
