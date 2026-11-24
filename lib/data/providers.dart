import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'community_models.dart';
import 'community_repository.dart';
import 'models.dart';
import 'repository.dart';
import 'smart_search.dart';

/// Overridden in main() with the chosen backend.
final repositoryProvider = Provider<CampusRepository>((ref) => throw UnimplementedError());

final isDemoModeProvider = Provider<bool>((ref) => true);

final currentUserProvider = StreamProvider<Profile?>(
  (ref) => ref.watch(repositoryProvider).currentUser,
);

/// Who is signed in (just the id). Every list below watches it, so when one
/// person signs out and another signs in on the same phone, nothing from the
/// first person is shown to the second.
final _whoProvider = Provider<String?>((ref) => ref.watch(currentUserProvider).valueOrNull?.id);

CampusRepository _repo(Ref ref) {
  ref.watch(_whoProvider);
  return ref.watch(repositoryProvider);
}

CommunityApi _com(Ref ref) {
  ref.watch(_whoProvider);
  return ref.watch(communityProvider);
}

final announcementsProvider =
    FutureProvider.autoDispose((ref) => _repo(ref).announcements());

final officesProvider = FutureProvider((ref) => _repo(ref).offices());

final myRequestsProvider =
    FutureProvider.autoDispose((ref) => _repo(ref).myRequests());

final requestUpdatesProvider = FutureProvider.autoDispose
    .family<List<RequestUpdate>, String>((ref, id) => _repo(ref).requestUpdates(id));

final tutorsProvider = FutureProvider.autoDispose((ref) => _repo(ref).tutors());

final studyGroupsProvider =
    FutureProvider.autoDispose((ref) => _repo(ref).studyGroups());

final pollsProvider = FutureProvider.autoDispose((ref) => _repo(ref).polls());

final buddyPairProvider =
    FutureProvider.autoDispose((ref) => _repo(ref).myBuddyPair());

final mentorsProvider = FutureProvider.autoDispose((ref) => _repo(ref).mentors());

final eventsProvider = FutureProvider.autoDispose((ref) => _repo(ref).events());

final clubsProvider = FutureProvider.autoDispose((ref) => _repo(ref).clubs());

final timetableProvider =
    FutureProvider.autoDispose((ref) => _repo(ref).timetable());

/// "Where do I go?" – searches offices, announcements, events, groups, clubs.
final smartSearchProvider =
    FutureProvider.autoDispose.family<List<SearchHit>, String>((ref, query) async {
  if (query.trim().length < 2) return const [];
  final repo = _repo(ref);
  final results = await Future.wait([
    repo.offices(),
    repo.announcements(),
    repo.events(),
    repo.studyGroups(),
    repo.clubs(),
  ]);
  return SmartSearch.run(
    query,
    offices: results[0] as List<HelpOffice>,
    announcements: results[1] as List<Announcement>,
    events: results[2] as List<CampusEvent>,
    groups: results[3] as List<StudyGroup>,
    clubs: results[4] as List<Club>,
  );
});

// ---- community ----
final communityProvider = Provider<CommunityApi>((ref) => ref.watch(repositoryProvider).community);

final postsProvider = FutureProvider.autoDispose.family<List<Post>, String?>(
    (ref, kind) => _com(ref).posts(kind: kind));

final featuredEventsProvider =
    FutureProvider.autoDispose((ref) => _com(ref).featuredEvents());

final myMembershipsProvider = FutureProvider.autoDispose((ref) async {
  ref.watch(currentUserProvider);
  return _com(ref).myMemberships();
});

final campusesProvider = FutureProvider.autoDispose((ref) => _com(ref).campuses());

final majorRequestsProvider =
    FutureProvider.autoDispose((ref) => _com(ref).majorRequests());

final moderationLogProvider =
    FutureProvider.autoDispose((ref) => _com(ref).moderationLog());

final lostFoundProvider = FutureProvider.autoDispose((ref) => _com(ref).lostFound());

final surveysProvider = FutureProvider.autoDispose((ref) => _com(ref).surveys());

final tutorCardsProvider = FutureProvider.autoDispose((ref) => _com(ref).tutorCards());

final myTutorRequestsProvider =
    FutureProvider.autoDispose((ref) => _com(ref).myTutorRequests());

// ---- course units, tutor reports, notifications ----
final teachingUnitsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(currentUserProvider);
  return _com(ref).myTeachingUnits();
});
final courseNoticesProvider = FutureProvider.autoDispose((ref) => _com(ref).courseNotices());
final courseLecturersProvider = FutureProvider.autoDispose((ref) => _com(ref).courseLecturers());
final tutorReportSummaryProvider =
    FutureProvider.autoDispose((ref) => _com(ref).tutorReportSummary());

final notificationsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(currentUserProvider);
  return _com(ref).notifications();
});
final unreadNotificationsProvider = Provider.autoDispose<int>(
    (ref) => ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.read).length ?? 0);
