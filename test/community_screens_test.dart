import 'package:campuslink/data/local_repository.dart';
import 'package:campuslink/data/providers.dart';
import 'package:campuslink/features/community/events_screens.dart';
import 'package:campuslink/features/community/map_screen.dart';
import 'package:campuslink/features/community/more_screens.dart';
import 'package:campuslink/features/community/news_screen.dart';
import 'package:campuslink/features/community/office_edit.dart';
import 'package:campuslink/features/home/home_screen.dart';
import 'package:campuslink/features/hubs/hubs.dart';
import 'package:campuslink/features/install/install_screen.dart';
import 'package:campuslink/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campuslink/features/courses/courses_screen.dart';
import 'package:campuslink/features/community/insights_screen.dart';
import 'package:campuslink/features/admin/admin_dashboard.dart';
import 'package:campuslink/features/notifications/notifications.dart';
import 'package:campuslink/features/community/policy_gate.dart';
import 'package:campuslink/features/legal/policies.dart';
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
    'campuses': () => const CampusesScreen(),
    'home': () => const Scaffold(body: HomeScreen()),
    'feed': () => const FeedScreen(),
    'campus hub': () => const CampusHubScreen(),
    'study hub': () => const StudyHubScreen(),
    'me': () => const ProfileScreen(),
    'install': () => const InstallScreen(),
    'notifications': () => const NotificationsScreen(),
    'insights': () => const PostInsightsScreen(),
    'dashboard': () => const AdminDashboardScreen(),
    'courses': () => const CoursesScreen(),
    'course notice': () => const ComposeCourseNoticeScreen(),
    'lecturers': () => const LecturersScreen(),
    'tutor reports': () => const TutorReportsScreen(),
    'privacy': () => const PolicyScreen(doc: privacyPolicy),
    'terms': () => const PolicyScreen(doc: termsOfUse),
    'edit office': () => const OfficeEditScreen(officeId: 'off-registrar'),
  };

  for (final email in ['super@x.ug', 'guild@x.ug', 'student@x.ug']) {
    for (final (scale, size) in [(1.0, const Size(390, 844)), (1.8, const Size(390, 844)), (1.0, const Size(1440, 900))]) {
      for (final e in screens.entries) {
        testWidgets('${e.key} draws for $email at text x$scale on ${size.width.toInt()}px', (tester) async {
          tester.view.physicalSize = size;
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
