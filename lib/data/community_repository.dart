import 'dart:typed_data';

import 'community_models.dart';
import 'models.dart';

/// A message that is safe and useful to show to the person.
class CommunityException implements Exception {
  CommunityException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The community side of CampusLink. Two implementations:
/// LocalCommunity (demo) and SupabaseCommunity (live).
abstract class CommunityApi {
  // =====================================================================
  // Community platform
  // =====================================================================

  // ---- who speaks for whom ----
  /// My offices, including ended terms (UI shows only active ones).
  Future<List<Membership>> myMemberships();
  Future<List<Publisher>> publishers();
  /// Office members (president/admin view). Includes ended terms.
  Future<List<Membership>> membersOf(String publisherId);
  /// Appoint someone to an office for a limited term, found by student number.
  Future<void> appointMember({
    required String publisherId,
    required String studentNumber,
    required String positionTitle,
    required List<String> scopes,
    required DateTime expiresAt,
  });
  Future<void> endTerm(String membershipId);

  // ---- news ----
  Future<List<Post>> posts({String? kind, int limit = 20, DateTime? before});
  Future<Post?> post(String id);
  Future<Post> createPost({
    required String publisherId,
    required String kind,
    required String title,
    required String body,
    required String sourceNote,
    String? videoUrl,
    String? meetingUrl,
    DateTime? expiresAt,
    String? correctsPostId,
  });

  // ---- comments, likes, reports ----
  Future<List<Comment>> comments(String targetType, String targetId);
  Future<void> addComment(String targetType, String targetId, String body);
  Future<void> deleteComment(String id);
  /// Returns true when the item is now liked.
  Future<bool> toggleLike(String targetType, String targetId);
  Future<void> report(String targetType, String targetId, String reason);
  Future<List<Report>> openReports();

  // ---- moderation (public log) ----
  /// action: remove | restore. Needs a reason (20+ characters).
  Future<void> moderate({
    required String action,
    required String targetType,
    required String targetId,
    required String reason,
  });
  Future<List<ModerationEntry>> moderationLog();

  // ---- events ----
  Future<CampusEvent?> event(String id);
  Future<List<CampusEvent>> featuredEvents();
  Future<CampusEvent> createEvent(CampusEvent e);
  /// Super admin only: approved | rejected.
  Future<void> setMajorStatus(String eventId, String status);
  Future<List<CampusEvent>> majorRequests();

  // ---- campuses and offices ----
  Future<List<Campus>> campuses();
  Future<void> saveCampus(Campus c);
  Future<void> saveOffice(HelpOffice o);

  // ---- lost & found ----
  Future<List<LostFoundItem>> lostFound();
  Future<void> addLostFound({
    required String publisherId,
    required String title,
    required String description,
    required String foundWhere,
    required String storedAt,
    String? photoUrl,
  });
  Future<void> setLostFoundStatus(String itemId, String status);
  Future<void> claimItem(String itemId, String proof);
  Future<List<LostFoundClaim>> claimsFor(String itemId);
  Future<void> decideClaim(String claimId, {required bool approve});

  // ---- surveys ----
  Future<List<Survey>> surveys();
  Future<Survey> createSurvey({
    required String publisherId,
    required String title,
    required String purpose,
    required DateTime closesAt,
    required List<SurveyQuestion> questions,
  });
  /// answers: questionId -> String (single/scale/text) or `List<String>` (multi).
  Future<void> submitSurvey(String surveyId, Map<String, dynamic> answers);
  /// Throws until 5 people have answered.
  Future<List<SurveyResultRow>> surveyResults(String surveyId);

  // ---- tutors ----
  Future<List<TutorCard>> tutorCards();
  Future<TutorCard?> myTutorCard();
  Future<void> saveMyTutorProfile({
    required String bio,
    String? contact,
    required String availability,
    required List<TutorModule> modules,
  });
  Future<void> requestTutor({required String tutorId, required String courseCode, required String message});
  Future<List<TutorRequest>> myTutorRequests();
  Future<void> answerTutorRequest(String id, {required bool accept});
  Future<void> confirmLesson(String id);
  Future<void> reviewTutor({required String requestId, required int rating, String? comment});

  // ---- pictures ----
  /// Uploads a small image (max 1 MB, JPEG/PNG/WebP) and returns its public link.
  Future<String> uploadImage(Uint8List bytes, {required String extension});

  // ---- policies ----
  Future<bool> hasAccepted(String policy, String version);
  Future<void> accept(String policy, String version);
}
