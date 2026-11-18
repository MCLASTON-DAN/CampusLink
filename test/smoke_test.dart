import 'package:campuslink/app.dart';
import 'package:campuslink/data/local_repository.dart';
import 'package:campuslink/data/models.dart';
import 'package:campuslink/features/home/home_screen.dart';
import 'package:campuslink/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app boots in demo mode and shows the login screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(LocalRepository(prefs)),
          isDemoModeProvider.overrideWithValue(true),
        ],
        child: const CampusLinkApp(),
      ),
    );
    // The login screen has a looping gradient animation, so pumpAndSettle
    // would never return. Pump a few frames instead.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.textContaining('CampusLink'), findsWidgets);
  });

  // The "today's classes" card only shows on days with a class, so a bug there
  // can hide for days. Force a class today and also test large text sizes.
  for (final scale in [1.0, 1.6]) {
    testWidgets('home shows today\'s class without overflow (text x$scale)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final today = TimetableEntry(
        id: 't1',
        courseCode: 'RMC2101',
        courseName: 'Research Methodology in Computing',
        dayOfWeek: DateTime.now().weekday,
        startTime: '14:00',
        endTime: '17:00',
        room: 'LT 1',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(LocalRepository(prefs)),
            isDemoModeProvider.overrideWithValue(true),
            timetableProvider.overrideWith((ref) async => [today]),
          ],
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale), size: const Size(800, 900)),
            child: const MaterialApp(home: Scaffold(body: HomeScreen())),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.textContaining('RMC2101'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
