import 'package:campuslink/core/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ScreenSize> sizeFor(WidgetTester t, Size s) async {
  late ScreenSize got;
  await t.pumpWidget(MediaQuery(
    data: MediaQueryData(size: s),
    child: Builder(builder: (c) {
      got = ScreenSize.of(c);
      return const SizedBox();
    }),
  ));
  return got;
}

void main() {
  testWidgets('phones stay compact, even in browser Desktop site mode', (t) async {
    expect(await sizeFor(t, const Size(412, 915)), ScreenSize.compact); // normal phone
    expect(await sizeFor(t, const Size(980, 2100)), ScreenSize.compact); // phone, Desktop site
  });
  testWidgets('upright tablets, sideways tablets and desktops keep the big layout', (t) async {
    expect(await sizeFor(t, const Size(1024, 1366)), ScreenSize.expanded); // iPad Pro upright
    expect(await sizeFor(t, const Size(900, 1440)), ScreenSize.expanded); // big Android tablet upright
    expect(await sizeFor(t, const Size(800, 1280)), ScreenSize.medium); // 10" tablet upright
    expect(await sizeFor(t, const Size(1280, 800)), ScreenSize.large); // tablet sideways
    expect(await sizeFor(t, const Size(1440, 900)), ScreenSize.large); // laptop
  });
  test('columns and comparisons', () {
    expect(ScreenSize.forWidth(599), ScreenSize.compact);
    expect(ScreenSize.forWidth(600), ScreenSize.medium);
    expect(ScreenSize.large >= ScreenSize.expanded, isTrue);
    expect(ScreenSize.medium.columns(), 2);
  });
}
