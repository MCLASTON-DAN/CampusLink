import 'dart:async';

import 'package:campuslink/data/write_once.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('three taps while sending = one save', () async {
    final g = WriteOnce();
    var saves = 0;
    final slow = Completer<void>();
    Future<void> send() => g.run('comment|r1|hello', () async {
          saves++;
          await slow.future;
        });
    final a = send(), b = send(), c = send();
    slow.complete();
    await Future.wait([a, b, c]);
    expect(saves, 1);
  });

  test('a tap right after it finished is still one save; a different message is new', () async {
    var t = DateTime(2026, 1, 1, 10);
    final g = WriteOnce(clock: () => t);
    var saves = 0;
    Future<int> send(String m) => g.run('comment|r1|$m', () async => ++saves);
    await send('hello');
    await send('hello');
    expect(saves, 1);
    await send('second message');
    expect(saves, 2);
    t = t.add(const Duration(seconds: 10)); // later, the same words again on purpose
    await send('hello');
    expect(saves, 3);
  });

  test('a failed save is forgotten, so trying again works', () async {
    final g = WriteOnce();
    var tries = 0;
    Future<void> send() => g.run('post|x', () async {
          tries++;
          if (tries == 1) throw Exception('no network');
        });
    await expectLater(send(), throwsException);
    await send();
    expect(tries, 2);
  });

  test('toggles: like then unlike quickly still both happen', () async {
    final g = WriteOnce();
    var flips = 0;
    Future<void> tap() => g.run('like|post|1', () async => flips++, toggle: true);
    await tap();
    await tap();
    expect(flips, 2);
  });
}
