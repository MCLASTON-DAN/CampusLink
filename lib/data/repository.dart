import 'community_repository.dart';
import 'exams.dart';
import 'group_chat.dart';
export 'group_chat.dart';
export 'exams.dart';
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

  /// Answer every open request on one topic at once. Returns how many.
  Future<int> replyToTopic({required String? officeId, required String topic, required String message, RequestStatus? status});

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

  // ---- study group invites and chat ----
  /// Ask to join an invite-only group (the owner approves).
  Future<void> requestToJoinGroup(String groupId, String? message);
  /// Groups I have asked to join and am waiting on.
  Future<Set<String>> myPendingGroupRequests();
  /// Owner: who is waiting to join.
  Future<List<GroupJoinRequest>> groupJoinRequests(String groupId);
  Future<void> decideGroupRequest(String requestId, {required bool approve});
  Future<void> setGroupPrivacy(String groupId, String privacy);
  Future<List<GroupMember>> groupMembers(String groupId);
  /// Latest messages, oldest first. Members only.
  Future<List<GroupMessage>> groupMessages(String groupId);
  /// New and changed messages as they happen.
  Stream<GroupMessage> groupMessageChanges(String groupId);
  Future<void> sendGroupMessage(String groupId, String body, {String? replyTo, List<String> mentions, bool mentionAll});
  Future<void> deleteGroupMessage(String messageId);
  Future<void> pinGroupMessage(String messageId, {required bool pin});

  /// WhatsApp-style reaction on a chat message: adds, switches, or removes
  /// (same emoji again). Returns the message's reactions afterwards.
  Future<Map<String, String>> reactToMessage(String messageId, String emoji);
  /// Names of members typing right now (private channel, members only).
  Stream<Set<String>> typingIn(String groupId);
  void sendTyping(String groupId);

  /// Replace a wrong announcement with a public "Retracted: reason" notice (author or super admin).
  Future<void> retractAnnouncement(String id, String reason);

  // ---- exams (real dates) ----
  /// Official papers for my units + my own entries, soonest first.
  Future<List<ExamEntry>> myExams();
  Future<void> addMyExam(ExamEntry e);
  Future<void> deleteMyExam(String id);
  /// Every official paper (for the Examinations office's list).
  Future<List<ExamEntry>> examPapers();
  /// Examinations office handlers and the super admin.
  Future<bool> canManageExams();
  Future<void> saveExamPaper(ExamEntry e);
  Future<void> deleteExamPaper(String id);

  /// News, events, offices, tutors, surveys… (see community_repository.dart)
  CommunityApi get community;
}


/// Sign-up worked, but the account only opens after the person taps the
/// link (or types the code) in the confirmation email.
class EmailConfirmationNeeded implements Exception {
  const EmailConfirmationNeeded();
  @override
  String toString() => 'Check your email to confirm your account.';
}
