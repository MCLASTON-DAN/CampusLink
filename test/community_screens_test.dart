import 'package:campuslink/data/local_repository.dart';
import 'package:campuslink/data/providers.dart';
import 'package:campuslink/features/community/events_screens.dart';
import 'package:campuslink/features/community/map_screen.dart';
import 'package:campuslink/features/community/more_screens.dart';
import 'package:campuslink/features/community/news_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final screens = <String, Widget Function()>{
    'hub': () => const CommunityHubScreen(),
    'news': () => const NewsScreen(),
    'compose post': () => const ComposePostScreen(),
    'events': () => const EventsListScreen(),
    'compose event': () => const ComposeEventScreen(),
    'major requests': () => const MajorRequestsScreen(),
    'map': () => const CampusMapScreen(),
    'lost & found': () => const LostFoundScreen(),
    'surveys': () => const SurveysScreen(),
    'new survey': () => const CreateSurveyScreen(),
    'tutors': () => const TutorsScreen(),
    'my lessons': () => const MyLessonsScreen(),
    'tutor profile': () => const TutorProfileEditScreen(),
    'removal log': () => const ModerationLogScreen(),
    'reports': () => const ReportsScreen(),
    'members': () => const MembersScreen(),
  };

  for (final email in ['super@x.ug', 'guild@x.ug', 'student@x.ug']) {
    for (final scale in [1.0, 1.8]) {
      for (final e in screens.entries) {
        testWidgets('${e.key} draws for $email at text x$scale', (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          SharedPreferences.setMockInitialValues({});
          final prefs = await tester.runAsync(SharedPreferences.getInstance);
          final repo = LocalRepository(prefs!);
          await tester.runAsync(() => repo.signIn(email: email, password: 'password1'));
          await tester.pumpWidget(ProviderScope(
            overrides: [repositoryProvider.overrideWithValue(repo), isDemoModeProvider.overrideWithValue(true)],
            child: MaterialApp(
              builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
              home: e.value(),
            ),
          ));
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 200));
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
