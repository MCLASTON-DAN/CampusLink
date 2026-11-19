import 'package:campuslink/features/install/install_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads Android version from browser user agent', () {
    expect(androidMajorVersion('Mozilla/5.0 (Linux; Android 6.0.1; SM-J500F) Chrome/90'), 6);
    expect(androidMajorVersion('Mozilla/5.0 (Linux; Android 10; K) Chrome/130'), 10);
    expect(androidMajorVersion('Mozilla/5.0 (Windows NT 10.0; Win64; x64)'), isNull);
  });

  test('old phones get the web app instead of the APK', () {
    expect(apkFitsThisPhone('Linux; Android 5.1; Tecno'), isFalse);
    expect(apkFitsThisPhone('Linux; Android 6.0.1; SM-J500F'), isFalse);
    expect(apkFitsThisPhone('Linux; Android 7.0; Infinix'), isTrue);
    expect(apkFitsThisPhone('Linux; Android 14; Pixel'), isTrue);
    expect(apkFitsThisPhone('Windows NT 10.0'), isTrue);
  });
}
