import 'package:campuslink/features/update/app_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rel = AppRelease(
    build: 170,
    version: '1.0.170',
    url: 'https://example.com/campuslink.apk',
    sizeBytes: 25 * 1048576,
    notes: ['Faster feed', 'Password reset with a code'],
  );

  test('reads old and new version.json', () {
    final old = AppRelease.fromMap({'build': 150, 'version': '1.0.150', 'url': 'u'});
    expect(old.notes, isEmpty);
    expect(old.sizeLabel, '');
    final now = AppRelease.fromMap({'build': 170, 'size': 26214400, 'sha256': 'ab', 'notes': ['A']});
    expect(now.sizeLabel, '25 MB');
    expect(now.version, '170');
  });

  testWidgets('required page cannot be left and shows what is new', (t) async {
    await t.pumpWidget(const MaterialApp(home: UpdateRequiredPage(release: rel)));
    expect(find.text('Time to update CampusLink'), findsOneWidget);
    expect(find.text('Faster feed'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    expect(find.textContaining('25 MB'), findsOneWidget);
  });

  testWidgets('details page from Me', (t) async {
    updateState.value = const UpdateState(UpdateLevel.available, release: rel);
    await t.pumpWidget(const MaterialApp(home: UpdateDetailsScreen()));
    expect(find.text('Password reset with a code'), findsOneWidget);
    updateState.value = const UpdateState(UpdateLevel.none);
  });

  test('version headers are only sent by apps, not the website', () {
    final h = appVersionHeaders();
    expect(h['x-app-platform'], isNotNull); // tests run as a desktop/mobile app
  });
}
