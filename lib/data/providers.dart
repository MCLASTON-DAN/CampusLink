import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'offline_cache.dart';

import 'community_models.dart';
import 'community_repository.dart';
import 'models.dart';
import 'repository.dart';
import 'smart_search.dart';

/// Overridden in main() with the chosen backend.
final repositoryProvider = Provider<CampusRepository>((ref) => throw UnimplementedError());

/// Null in tests and demo: then nothing is cached.
final offlineCacheProvider = Provider<OfflineCache?>((ref) => null);

/// Lists currently shown from the saved copy, with when that copy was saved.
/// Empty means everything on screen is fresh.
final offlineSinceProvider = StateProvider<Map<String, DateTime>>((ref) => const {});

/// When each list was last fetched from the server (this app session).
final _lastFresh = <String, DateTime>{};

/// Lists whose fresh copy was just saved by a background refresh; the very
/// next run shows it without asking the server again.
final _swapped = <String>{};

/// Show the saved copy straight away, fetch fresh data in the background and
/// swap it in when it arrives. With no saved copy: wait for the server. If
/// the server can't be reached, keep showing the saved copy (and say so).
Future<List<T>> _cached<T>(
  Ref ref,
  String key,
  Future<List<T>> Function() fetch,
  Map<String, dynamic> Function(T) toMap,
  T Function(Map<String, dynamic>) fromMap,
) async {
  final cache = ref.watch(offlineCacheProvider);
  final who = ref.watch(_whoProvider);
  void mark(DateTime? at) {
    final n = ref.read(offlineSinceProvider.notifier);
    final next = {...n.state};
    at == null ? next.remove(key) : next[key] = at;
    if (next.length != n.state.length || next[key] != n.state[key]) n.state = next;
  }

  final slot = '$who|$key';
  final saved = (cache != null && who != null) ? cache.load(who, key) : null;
  final last = _lastFresh[slot];
  final age = last == null ? null : DateTime.now().difference(last);
  // This run comes from the background swap below: the saved copy IS fresh.
  if (saved != null && _swapped.remove(slot)) {
    return [for (final r in saved.$1) fromMap(r)];
  }
  // Opening the app, or a screen not loaded for 10 minutes: show the saved
  // copy at once. A reload soon after (e.g. right after posting) waits for
  // the server instead, so new things show immediately and correctly.
  if (saved != null && (age == null || age > const Duration(minutes: 10))) {
    var alive = true;
    ref.onDispose(() => alive = false);
    unawaited(() async {
      try {
        final fresh = await fetch();
        await cache!.save(who!, key, [for (final x in fresh) toMap(x)]);
        _lastFresh[slot] = DateTime.now();
        if (alive) {
          mark(null);
          _swapped.add(slot);
          ref.invalidateSelf();
        }
      } catch (_) {
        if (alive) mark(saved.$2);
      }
    }());
    return [for (final r in saved.$1) fromMap(r)];
  }

  try {
    final fresh = await fetch();
    if (cache != null && who != null) {
      await cache.save(who, key, [for (final x in fresh) toMap(x)]);
      _lastFresh[slot] = DateTime.now();
      mark(null);
    }
    return fresh;
  } catch (_) {
    final saved = (cache != null && who != null) ? cache.load(who, key) : null;
    if (saved == null) rethrow;
    mark(saved.$2);
    return [for (final r in saved.$1) fromMap(r)];
  }
}

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

final announcementsProvider = FutureProvider.autoDispose((ref) => _cached(
    ref, 'announcements', () => _repo(ref).announcements(), (a) => a.toMap(), Announcement.fromMap));

final officesProvider = FutureProvider((ref) => _repo(ref).offices());

/// Help offices I handle requests for (empty for most people).
final myHandledOfficesProvider = FutureProvider((ref) => _repo(ref).myHandledOffices());

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

final eventsProvider = FutureProvider.autoDispose(
    (ref) => _cached(ref, 'events', () => _repo(ref).events(), _eventToCache, CampusEvent.fromMap));

final clubsProvider = FutureProvider.autoDispose((ref) => _repo(ref).clubs());

final timetableProvider = FutureProvider.autoDispose((ref) => _cached(
    ref, 'timetable', () => _repo(ref).timetable(), (t) => t.toMap(), TimetableEntry.fromMap));

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

final postsProvider = FutureProvider.autoDispose.family<List<Post>, String?>((ref, kind) => _cached(
    ref, 'posts:${kind ?? 'all'}', () => _com(ref).posts(kind: kind), _postToCache, Post.fromMap));

final featuredEventsProvider = FutureProvider.autoDispose((ref) => _cached(
    ref, 'featured', () => _com(ref).featuredEvents(), _eventToCache, CampusEvent.fromMap));

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
final courseNoticesProvider = FutureProvider.autoDispose((ref) => _cached(
    ref, 'course_notices', () => _com(ref).courseNotices(), (n) => n.toMap(), CourseNotice.fromMap));
final courseLecturersProvider = FutureProvider.autoDispose((ref) => _com(ref).courseLecturers());
final tutorReportSummaryProvider =
    FutureProvider.autoDispose((ref) => _com(ref).tutorReportSummary());

final notificationsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(currentUserProvider);
  return _cached(ref, 'notifications', () => _com(ref).notifications(), (n) => n.toMap(), AppNotification.fromMap);
});

// Counts are not part of toMap (the database computes them), so keep them in the copy.
Map<String, dynamic> _postToCache(Post p) =>
    {...p.toMap(), 'likes': p.likes, 'comments': p.comments, 'liked_by_me': p.likedByMe};
Map<String, dynamic> _eventToCache(CampusEvent e) =>
    {...e.toMap(), 'likes': e.likes, 'comments': e.comments, 'liked_by_me': e.likedByMe};

/// The lists the "Try again" button reloads.
void retryOffline(WidgetRef ref) {
  for (final p in [announcementsProvider, eventsProvider, timetableProvider, featuredEventsProvider,
      courseNoticesProvider, notificationsProvider]) {
    ref.invalidate(p);
  }
  ref.invalidate(postsProvider);
}
final unreadNotificationsProvider = Provider.autoDispose<int>(
    (ref) => ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.read).length ?? 0);
