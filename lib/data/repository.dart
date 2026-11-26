import 'community_repository.dart';
import 'models.dart';

/// Everything the UI needs from a backend. Two implementations:
/// [LocalRepository] (demo / offline) and [SupabaseRepository] (live).
abstract class CampusRepository {
  // ---- auth ----
  Stream<Profile?> get currentUser;
  Profile? get currentUserSync;
  Future<Profile> signIn({required String email, required String password});
  Future<Profile> signUp({
    required String email,
    required String password,
    required String fullName,
    String? studentNumber,
    String? programme,
    int? yearOfStudy,
  });
  /// Opens Google sign-in. On the web the page reloads signed in; on phones
  /// the app reopens through the login-callback link.
  Future<void> signInWithGoogle();
  Future<void> signOut();
  Future<Profile> updateProfile(Profile p);

  // ---- announcements ----
  Future<List<Announcement>> announcements();
  Future<void> postAnnouncement(Announcement a);

  // ---- help directory ----
  Future<List<HelpOffice>> offices();

  // ---- help requests ----
  Future<List<HelpRequest>> myRequests();
  Future<List<RequestUpdate>> requestUpdates(String requestId);
  Future<HelpRequest> createRequest(HelpRequest r);

  /// Send a request to another office (null = general desk): the student while
  /// it is open, or whoever handles it now. Adds a line to its timeline.
  Future<void> moveRequest(String requestId, String? officeId, String officeName);

  /// Ids of the help offices I handle requests for.
  Future<Set<String>> myHandledOffices();

  /// Who handles an office's requests (super admin and that office's handlers see this).
  Future<List<({String id, String name})>> officeHandlers(String officeId);

  /// Super admin: add or remove a handler. They are notified at once.
  Future<void> setOfficeHandler(String officeId, String userId, {required bool add});

  /// Reload my own profile (after my role or access changed).
  Future<void> reloadMe();
  Future<void> addRequestUpdate(RequestUpdate u, {RequestStatus? newStatus});

  // ---- study ----
  Future<List<Profile>> tutors();
  Future<List<StudyGroup>> studyGroups();
  Future<StudyGroup> createStudyGroup(StudyGroup g);
  Future<void> toggleGroupMembership(String groupId, bool join);

  // ---- pulse ----
  Future<List<PulsePoll>> polls();
  Future<void> vote(String pollId, int optionIndex);

  // ---- buddy ----
  Future<BuddyPair?> myBuddyPair();
  Future<BuddyPair> requestBuddy();
  Future<List<Profile>> mentors();

  // ---- engagement ----
  Future<void> submitFeedback({required String topic, required String message, String? sentiment});
  Future<List<CampusEvent>> events();
  Future<List<Club>> clubs();

  // ---- timetable ----
  Future<List<TimetableEntry>> timetable();
  Future<void> replaceTimetable(List<TimetableEntry> entries);
  Future<void> addTimetableEntry(TimetableEntry e);
  Future<void> deleteTimetableEntry(String id);

  /// News, events, offices, tutors, surveys… (see community_repository.dart)
  CommunityApi get community;
}
