import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, AuthChangeEvent;

import 'core/config.dart';
import 'core/theme.dart';
import 'data/providers.dart';
import 'features/study/group_chat_screen.dart';
import 'features/timetable/exams_screen.dart';
import 'features/community/tutor_checks.dart';
import 'features/timetable/class_reminders_sync.dart';
import 'features/announcements/announcements_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/account/calendar_sync_screen.dart';
import 'features/account/email_rules_admin.dart';
import 'features/account/password_screens.dart';
import 'features/account/tutor_offer.dart';
import 'features/buddy/buddy_screen.dart';
import 'features/community/policy_gate.dart';
import 'features/courses/courses_screen.dart';
import 'features/community/insights_screen.dart';
import 'features/admin/admin_dashboard.dart';
import 'features/notifications/notifications.dart';
import 'features/update/app_update.dart';
import 'features/update/app_updates_admin.dart';
import 'features/community/events_screens.dart';
import 'features/community/map_screen.dart';
import 'features/community/more_screens.dart';
import 'features/community/news_screen.dart';
import 'features/community/office_edit.dart';
import 'features/hubs/hubs.dart';
import 'features/install/install_screen.dart';
import 'features/directory/directory_screen.dart';
import 'features/directory/office_detail_screen.dart';
import 'features/engage/engage_screen.dart';
import 'features/home/home_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/pulse/pulse_screen.dart';
import 'features/requests/request_detail_screen.dart';
import 'features/requests/requests_screen.dart';
import 'features/search/where_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/study/study_screen.dart';
import 'features/timetable/timetable_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

// The router is made ONCE. It used to be rebuilt every time the signed-in
// profile changed (sign-in, token refresh, profile reload), which restarted
// the whole app and made the screen flash 2-3 times after signing in.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/home',
    redirect: (context, state) {
      final auth = ref.read(currentUserProvider);
      if (auth.isLoading) return null;
      final signedIn = auth.valueOrNull != null;
      final onLogin = state.matchedLocation == '/login';
      // Password reset pages work signed in or out: the reset itself signs you
      // in for a moment, and the profile may not have loaded yet.
      if (const {'/forgot-password', '/set-password'}.contains(state.matchedLocation)) return null;
      if (!signedIn && !onLogin) return '/login';
      if (signedIn && onLogin) return '/home';
      return null;
    },
    refreshListenable: _AuthNotifier(ref),
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/forgot-password',
          builder: (_, s) => ForgotPasswordScreen(initialEmail: s.extra is String ? s.extra as String : '')),
      GoRoute(path: '/set-password', builder: (_, __) => const SetNewPasswordScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            NotificationHost(
                child: ClassReminderSync(
                    child: PolicyAcceptanceGate(child: AppShell(location: state.matchedLocation, child: child)))),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/announcements', builder: (_, __) => const AnnouncementsScreen()),
          GoRoute(
            path: '/directory',
            builder: (_, __) => const DirectoryScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => OfficeDetailScreen(officeId: s.pathParameters['id']!),
                routes: [
                  GoRoute(path: 'edit', builder: (_, s) => OfficeEditScreen(officeId: s.pathParameters['id']!)),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/requests',
            builder: (_, __) => const RequestsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => RequestDetailScreen(requestId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/study', builder: (_, __) => const StudyHubScreen()),
          GoRoute(path: '/groups', builder: (_, __) => const StudyScreen()),
          GoRoute(path: '/feed', builder: (_, s) => FeedScreen(initialTab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0)),
          GoRoute(path: '/campus', builder: (_, __) => const CampusHubScreen()),
          GoRoute(path: '/install', builder: (_, __) => const InstallScreen()),
          GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
          GoRoute(path: '/tutor-reports', builder: (_, __) => const TutorReportsScreen()),
          GoRoute(path: '/tutor-checks', builder: (_, __) => const GradeChecksScreen()),
          GoRoute(path: '/insights', builder: (_, __) => const PostInsightsScreen()),
          GoRoute(path: '/dashboard', builder: (_, __) => const AdminDashboardScreen()),
          GoRoute(
            path: '/courses',
            builder: (_, __) => const CoursesScreen(),
            routes: [
              GoRoute(path: 'new', builder: (_, __) => const ComposeCourseNoticeScreen()),
              GoRoute(path: 'lecturers', builder: (_, __) => const LecturersScreen()),
            ],
          ),
          GoRoute(path: '/pulse', builder: (_, __) => const PulseScreen()),
          GoRoute(path: '/buddy', builder: (_, __) => const BuddyScreen()),
          GoRoute(path: '/where', builder: (_, __) => const WhereScreen()),
          GoRoute(path: '/engage', builder: (_, __) => const EngageScreen()),
          GoRoute(path: '/timetable', builder: (_, __) => const TimetableScreen()),
          GoRoute(path: '/exams', builder: (_, __) => const ExamsScreen()),
          GoRoute(path: '/groups/:id', builder: (_, st) => GroupChatScreen(groupId: st.pathParameters['id']!)),
          GoRoute(path: '/community', builder: (_, __) => const CommunityHubScreen()),
          GoRoute(path: '/news', builder: (_, __) => const NewsScreen()),
          GoRoute(path: '/news/new', builder: (_, __) => const ComposePostScreen()),
          GoRoute(path: '/news/:id', builder: (_, s) => PostDetailScreen(postId: s.pathParameters['id']!)),
          GoRoute(path: '/events', builder: (_, __) => const EventsListScreen()),
          GoRoute(path: '/events/new', builder: (_, __) => const ComposeEventScreen()),
          GoRoute(path: '/events/requests', builder: (_, __) => const MajorRequestsScreen()),
          GoRoute(path: '/events/:id', builder: (_, s) => EventDetailScreen(eventId: s.pathParameters['id']!)),
          GoRoute(path: '/map', builder: (_, __) => const CampusMapScreen()),
          GoRoute(path: '/lostfound', builder: (_, __) => const LostFoundScreen()),
          GoRoute(path: '/lostfound/:id', builder: (_, s) => ClaimsScreen(itemId: s.pathParameters['id']!)),
          GoRoute(path: '/surveys', builder: (_, __) => const SurveysScreen()),
          GoRoute(path: '/surveys/new', builder: (_, __) => const CreateSurveyScreen()),
          GoRoute(path: '/surveys/:id', builder: (_, s) => TakeSurveyScreen(surveyId: s.pathParameters['id']!)),
          GoRoute(path: '/surveys/:id/results', builder: (_, s) => SurveyResultsScreen(surveyId: s.pathParameters['id']!)),
          GoRoute(path: '/tutors', builder: (_, __) => const TutorsScreen()),
          GoRoute(path: '/tutors/mine', builder: (_, __) => const MyLessonsScreen()),
          GoRoute(path: '/tutors/profile', builder: (_, __) => const TutorProfileEditScreen()),
          GoRoute(path: '/tutors/offer', builder: (_, __) => const TutorOfferScreen()),
          GoRoute(path: '/account/calendar', builder: (_, __) => const CalendarSyncScreen()),
          GoRoute(path: '/admin/email-rules', builder: (_, __) => const EmailRulesAdminScreen()),
          GoRoute(path: '/admin/app-updates', builder: (_, __) => const AppUpdatesAdminScreen()),
          GoRoute(path: '/update', builder: (_, __) => const UpdateDetailsScreen()),
          GoRoute(path: '/moderation', builder: (_, __) => const ModerationLogScreen()),
          GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
          GoRoute(path: '/campuses', builder: (_, __) => const CampusesScreen()),
          GoRoute(path: '/members', builder: (_, __) => const MembersScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
    ],
  );
  // The reset email (link or 6-digit code) signs the person in "for recovery":
  // send them straight to "Choose a new password".
  if (AppConfig.hasSupabase) {
    try {
      final sub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
        if (s.event == AuthChangeEvent.passwordRecovery) router.go('/set-password');
      });
      ref.onDispose(sub.cancel);
    } catch (_) {/* demo fallback: Supabase not started */}
  }
  return router;
});

/// Re-checks the route only when someone signs in or out (not on every
/// profile reload), so pages are not rebuilt for nothing.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(Ref ref) {
    ref.listen(currentUserProvider, (prev, next) {
      final before = prev?.valueOrNull?.id;
      final after = next.valueOrNull?.id;
      if (before != after || (prev?.isLoading ?? true) != next.isLoading) notifyListeners();
    });
  }
}

class CampusLinkApp extends ConsumerWidget {
  const CampusLinkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: router,
      // Status bar (clock, battery) blends with the app: same colour as the
      // page, with icons that stay readable in light and dark mode.
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Theme.of(context).colorScheme.surface,
          ),
          child: UpdateChecker(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
