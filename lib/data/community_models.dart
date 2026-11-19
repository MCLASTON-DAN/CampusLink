// Models for the community side of CampusLink: who speaks for whom, news,
// comments, campuses, lost & found, surveys and tutors.
// Every class has fromMap/toMap so it works for Supabase rows and for the
// local JSON store used in demo mode.

DateTime _dt(dynamic v) =>
    v == null ? DateTime.now() : (v is DateTime ? v : DateTime.parse(v.toString()));
DateTime? _dtn(dynamic v) => v == null ? null : _dt(v);
List<String> _strs(dynamic v) =>
    v == null ? const [] : List<String>.from((v as List).map((e) => e.toString()));

/// Badge colour that goes with an office: red = administration, green = guild.
String? badgeForKind(String? kind) => switch (kind) {
      'administration' => 'red',
      'guild' => 'green',
      _ => null,
    };

/// What each posting right means, in plain words (shown when appointing).
const kScopeLabels = <String, String>{
  'news': 'News and clarifications',
  'notices': 'Notices and official records',
  'events': 'Events',
  'meeting_links': 'Meeting links',
  'surveys': 'Surveys',
  'lost_found': 'Lost & found',
  'manage_members': 'Appoint office members',
};

class Publisher {
  final String id;
  final String kind; // administration | guild | club
  final String name;
  const Publisher({required this.id, required this.kind, required this.name});

  String? get badge => badgeForKind(kind);

  factory Publisher.fromMap(Map<String, dynamic> m) =>
      Publisher(id: m['id'], kind: m['kind'] ?? 'guild', name: m['name'] ?? '');
  Map<String, dynamic> toMap() => {'id': id, 'kind': kind, 'name': name};
}

/// A person's right to speak for an office, for a limited time.
class Membership {
  final String id;
  final String publisherId;
  final String publisherName;
  final String publisherKind;
  final String userId;
  final String? userName;
  final String positionTitle;
  final List<String> scopes;
  final DateTime startsAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;

  const Membership({
    required this.id,
    required this.publisherId,
    required this.publisherName,
    required this.publisherKind,
    required this.userId,
    this.userName,
    required this.positionTitle,
    this.scopes = const ['news'],
    required this.startsAt,
    required this.expiresAt,
    this.revokedAt,
  });

  bool get isActive {
    final n = DateTime.now();
    return revokedAt == null && !n.isBefore(startsAt) && n.isBefore(expiresAt);
  }

  bool can(String scope) => isActive && scopes.contains(scope);
  String? get badge => badgeForKind(publisherKind);
  int get daysLeft => expiresAt.difference(DateTime.now()).inDays;

  factory Membership.fromMap(Map<String, dynamic> m) => Membership(
        id: m['id'],
        publisherId: m['publisher_id'],
        publisherName: m['publisher_name'] ?? '',
        publisherKind: m['publisher_kind'] ?? 'guild',
        userId: m['user_id'] ?? '',
        userName: m['user_name'],
        positionTitle: m['position_title'] ?? '',
        scopes: _strs(m['scopes']),
        startsAt: _dt(m['starts_at']),
        expiresAt: _dt(m['expires_at']),
        revokedAt: _dtn(m['revoked_at']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'publisher_id': publisherId,
        'publisher_name': publisherName,
        'publisher_kind': publisherKind,
        'user_id': userId,
        'user_name': userName,
        'position_title': positionTitle,
        'scopes': scopes,
        'starts_at': startsAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'revoked_at': revokedAt?.toIso8601String(),
      };
}

/// kind values: news, notice, official_record, meeting_link, clarification
class Post {
  final String id;
  final String publisherId;
  final String publisherName;
  final String publisherKind;
  final String authorId;
  final String authorName;
  final String authorPosition;
  final String kind;
  final String title;
  final String body;
  final String? videoUrl;
  final String? meetingUrl;
  final String? coverPath; // full picture address
  final String sourceNote;
  final String? correctsPostId;
  final String status;
  final DateTime publishedAt;
  final DateTime? editedAt;
  final DateTime? expiresAt;
  final int likes;
  final int comments;
  final bool likedByMe;

  const Post({
    required this.id,
    required this.publisherId,
    this.publisherName = '',
    this.publisherKind = 'guild',
    required this.authorId,
    this.authorName = '',
    this.authorPosition = '',
    this.kind = 'news',
    required this.title,
    required this.body,
    this.videoUrl,
    this.meetingUrl,
    this.coverPath,
    required this.sourceNote,
    this.correctsPostId,
    this.status = 'published',
    required this.publishedAt,
    this.editedAt,
    this.expiresAt,
    this.likes = 0,
    this.comments = 0,
    this.likedByMe = false,
  });

  String? get badge => badgeForKind(publisherKind);
  bool get isEdited => editedAt != null;

  /// "Minister of ICT · Guild Office"
  String get byline => authorPosition.isEmpty ? publisherName : '$authorPosition · $publisherName';

  static const kindLabels = <String, String>{
    'news': 'News',
    'clarification': 'Clarification',
    'notice': 'Notice',
    'official_record': 'Official record',
    'meeting_link': 'Meeting',
  };
  String get kindLabel => kindLabels[kind] ?? kind;

  Post copyWith({int? likes, int? comments, bool? likedByMe}) => Post(
        id: id,
        publisherId: publisherId,
        publisherName: publisherName,
        publisherKind: publisherKind,
        authorId: authorId,
        authorName: authorName,
        authorPosition: authorPosition,
        kind: kind,
        title: title,
        body: body,
        videoUrl: videoUrl,
        meetingUrl: meetingUrl,
        coverPath: coverPath,
        sourceNote: sourceNote,
        correctsPostId: correctsPostId,
        status: status,
        publishedAt: publishedAt,
        editedAt: editedAt,
        expiresAt: expiresAt,
        likes: likes ?? this.likes,
        comments: comments ?? this.comments,
        likedByMe: likedByMe ?? this.likedByMe,
      );

  factory Post.fromMap(Map<String, dynamic> m) => Post(
        id: m['id'],
        publisherId: m['publisher_id'] ?? '',
        publisherName: m['publisher_name'] ?? '',
        publisherKind: m['publisher_kind'] ?? 'guild',
        authorId: m['author_id'] ?? '',
        authorName: m['author_name'] ?? '',
        authorPosition: m['author_position'] ?? '',
        kind: m['kind'] ?? 'news',
        title: m['title'] ?? '',
        body: m['body'] ?? '',
        videoUrl: m['video_url'],
        meetingUrl: m['meeting_url'],
        coverPath: m['cover_path'],
        sourceNote: m['source_note'] ?? '',
        correctsPostId: m['corrects_post_id'],
        status: m['status'] ?? 'published',
        publishedAt: _dt(m['published_at']),
        editedAt: _dtn(m['edited_at']),
        expiresAt: _dtn(m['expires_at']),
        likes: (m['likes'] ?? 0) as int,
        comments: (m['comments'] ?? 0) as int,
        likedByMe: m['liked_by_me'] ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'publisher_id': publisherId,
        'publisher_name': publisherName,
        'publisher_kind': publisherKind,
        'author_id': authorId,
        'author_name': authorName,
        'author_position': authorPosition,
        'kind': kind,
        'title': title,
        'body': body,
        'video_url': videoUrl,
        'meeting_url': meetingUrl,
        'cover_path': coverPath,
        'source_note': sourceNote,
        'corrects_post_id': correctsPostId,
        'status': status,
        'published_at': publishedAt.toIso8601String(),
        'edited_at': editedAt?.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
      };
}

class Comment {
  final String id;
  final String targetType; // post | event
  final String targetId;
  final String authorId;
  final String authorName;
  final String? badge; // shown only while the author is in office / a verified tutor
  final String? officeTitle;
  final String body;
  final DateTime createdAt;

  const Comment({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.authorId,
    required this.authorName,
    this.badge,
    this.officeTitle,
    required this.body,
    required this.createdAt,
  });

  factory Comment.fromMap(Map<String, dynamic> m) => Comment(
        id: m['id'],
        targetType: m['target_type'],
        targetId: m['target_id'],
        authorId: m['author_id'] ?? '',
        authorName: m['author_name'] ?? '',
        badge: m['badge'],
        officeTitle: m['office_title'],
        body: m['body'] ?? '',
        createdAt: _dt(m['created_at']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'target_type': targetType,
        'target_id': targetId,
        'author_id': authorId,
        'author_name': authorName,
        'badge': badge,
        'office_title': officeTitle,
        'body': body,
        'created_at': createdAt.toIso8601String(),
      };
}

class EventSpeaker {
  final String id;
  final String name;
  final String? title; // e.g. "Dean, Faculty of Science"
  final String role; // guest | panelist | moderator | host
  final String? photoUrl;
  final String? bio;

  const EventSpeaker({
    required this.id,
    required this.name,
    this.title,
    this.role = 'guest',
    this.photoUrl,
    this.bio,
  });

  static const roleLabels = <String, String>{
    'guest': 'Guest speaker',
    'panelist': 'Panelist',
    'moderator': 'Moderator',
    'host': 'Host',
  };
  String get roleLabel => roleLabels[role] ?? role;

  factory EventSpeaker.fromMap(Map<String, dynamic> m) => EventSpeaker(
        id: m['id'] ?? '',
        name: m['name'] ?? '',
        title: m['title'],
        role: m['role'] ?? 'guest',
        photoUrl: m['photo_url'],
        bio: m['bio'],
      );

  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'title': title, 'role': role, 'photo_url': photoUrl, 'bio': bio};
}

class ModerationEntry {
  final String id;
  final String actorName;
  final String targetType;
  final String targetTitle;
  final String action; // remove | restore
  final String reason;
  final DateTime createdAt;

  const ModerationEntry({
    required this.id,
    this.actorName = '',
    required this.targetType,
    required this.targetTitle,
    required this.action,
    required this.reason,
    required this.createdAt,
  });

  factory ModerationEntry.fromMap(Map<String, dynamic> m) => ModerationEntry(
        id: m['id'],
        actorName: m['actor_name'] ?? '',
        targetType: m['target_type'] ?? '',
        targetTitle: m['target_title'] ?? '',
        action: m['action'] ?? 'remove',
        reason: m['reason'] ?? '',
        createdAt: _dt(m['created_at']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'actor_name': actorName,
        'target_type': targetType,
        'target_title': targetTitle,
        'action': action,
        'reason': reason,
        'created_at': createdAt.toIso8601String(),
      };
}

class Report {
  final String id;
  final String targetType;
  final String targetId;
  final String targetTitle;
  final String reason;
  final DateTime createdAt;

  const Report({
    required this.id,
    required this.targetType,
    required this.targetId,
    this.targetTitle = '',
    required this.reason,
    required this.createdAt,
  });

  factory Report.fromMap(Map<String, dynamic> m) => Report(
        id: m['id'],
        targetType: m['target_type'] ?? '',
        targetId: m['target_id'] ?? '',
        targetTitle: m['target_title'] ?? '',
        reason: m['reason'] ?? '',
        createdAt: _dt(m['created_at']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'target_type': targetType,
        'target_id': targetId,
        'target_title': targetTitle,
        'reason': reason,
        'created_at': createdAt.toIso8601String(),
      };
}

class Campus {
  final String id;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final String? notes;

  const Campus({required this.id, required this.name, this.address, this.lat, this.lng, this.notes});

  bool get hasLocation => lat != null && lng != null;

  factory Campus.fromMap(Map<String, dynamic> m) => Campus(
        id: m['id'],
        name: m['name'] ?? '',
        address: m['address'],
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        notes: m['notes'],
      );

  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'address': address, 'lat': lat, 'lng': lng, 'notes': notes};
}

class LostFoundItem {
  final String id;
  final String publisherId;
  final String title;
  final String description;
  final String? photoUrl;
  final String foundWhere;
  final String storedAt;
  final DateTime foundOn;
  final String status; // held | claimed | disposed
  final String? myClaimStatus; // pending | approved | rejected

  const LostFoundItem({
    required this.id,
    this.publisherId = '',
    required this.title,
    this.description = '',
    this.photoUrl,
    required this.foundWhere,
    required this.storedAt,
    required this.foundOn,
    this.status = 'held',
    this.myClaimStatus,
  });

  factory LostFoundItem.fromMap(Map<String, dynamic> m) => LostFoundItem(
        id: m['id'],
        publisherId: m['publisher_id'] ?? '',
        title: m['title'] ?? '',
        description: m['description'] ?? '',
        photoUrl: m['photo_url'],
        foundWhere: m['found_where'] ?? '',
        storedAt: m['stored_at'] ?? '',
        foundOn: _dt(m['found_on']),
        status: m['status'] ?? 'held',
        myClaimStatus: m['my_claim_status'],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'publisher_id': publisherId,
        'title': title,
        'description': description,
        'photo_url': photoUrl,
        'found_where': foundWhere,
        'stored_at': storedAt,
        'found_on': foundOn.toIso8601String(),
        'status': status,
        'my_claim_status': myClaimStatus,
      };
}

class LostFoundClaim {
  final String id;
  final String itemId;
  final String claimantId;
  final String claimantName;
  final String proof;
  final String status;
  final DateTime createdAt;

  const LostFoundClaim({
    required this.id,
    required this.itemId,
    required this.claimantId,
    this.claimantName = '',
    required this.proof,
    this.status = 'pending',
    required this.createdAt,
  });

  factory LostFoundClaim.fromMap(Map<String, dynamic> m) => LostFoundClaim(
        id: m['id'],
        itemId: m['item_id'],
        claimantId: m['claimant_id'] ?? '',
        claimantName: m['claimant_name'] ?? '',
        proof: m['proof'] ?? '',
        status: m['status'] ?? 'pending',
        createdAt: _dt(m['created_at']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'item_id': itemId,
        'claimant_id': claimantId,
        'claimant_name': claimantName,
        'proof': proof,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };
}

class SurveyQuestion {
  final String id;
  final int position;
  final String prompt;
  final String kind; // single | multi | scale | text
  final List<String> options;

  const SurveyQuestion({
    required this.id,
    this.position = 0,
    required this.prompt,
    this.kind = 'single',
    this.options = const [],
  });

  factory SurveyQuestion.fromMap(Map<String, dynamic> m) => SurveyQuestion(
        id: m['id'] ?? '',
        position: (m['position'] ?? 0) as int,
        prompt: m['prompt'] ?? '',
        kind: m['kind'] ?? 'single',
        options: _strs(m['options']),
      );

  Map<String, dynamic> toMap() =>
      {'id': id, 'position': position, 'prompt': prompt, 'kind': kind, 'options': options};
}

class Survey {
  final String id;
  final String publisherId;
  final String publisherName;
  final String publisherKind;
  final String title;
  final String purpose;
  final DateTime closesAt;
  final String status;
  final List<SurveyQuestion> questions;
  final bool takenByMe;
  final bool mine; // I may see the results

  const Survey({
    required this.id,
    this.publisherId = '',
    this.publisherName = '',
    this.publisherKind = 'guild',
    required this.title,
    required this.purpose,
    required this.closesAt,
    this.status = 'open',
    this.questions = const [],
    this.takenByMe = false,
    this.mine = false,
  });

  bool get isOpen => status == 'open' && DateTime.now().isBefore(closesAt);
  String? get badge => badgeForKind(publisherKind);

  Survey copyWith({bool? takenByMe, List<SurveyQuestion>? questions}) => Survey(
        id: id,
        publisherId: publisherId,
        publisherName: publisherName,
        publisherKind: publisherKind,
        title: title,
        purpose: purpose,
        closesAt: closesAt,
        status: status,
        questions: questions ?? this.questions,
        takenByMe: takenByMe ?? this.takenByMe,
        mine: mine,
      );

  factory Survey.fromMap(Map<String, dynamic> m) => Survey(
        id: m['id'],
        publisherId: m['publisher_id'] ?? '',
        publisherName: m['publisher_name'] ?? '',
        publisherKind: m['publisher_kind'] ?? 'guild',
        title: m['title'] ?? '',
        purpose: m['purpose'] ?? '',
        closesAt: _dt(m['closes_at']),
        status: m['status'] ?? 'open',
        questions: ((m['questions'] as List?) ?? const [])
            .map((e) => SurveyQuestion.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        takenByMe: m['taken_by_me'] ?? false,
        mine: m['mine'] ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'publisher_id': publisherId,
        'publisher_name': publisherName,
        'publisher_kind': publisherKind,
        'title': title,
        'purpose': purpose,
        'closes_at': closesAt.toIso8601String(),
        'status': status,
        'questions': questions.map((q) => q.toMap()).toList(),
        'taken_by_me': takenByMe,
        'mine': mine,
      };
}

class SurveyResultRow {
  final String questionId;
  final String answer;
  final int n;
  const SurveyResultRow({required this.questionId, required this.answer, required this.n});
}

class TutorModule {
  final String id;
  final String courseCode;
  final String? courseName;
  final String? grade;
  final int priceUgx; // per hour
  const TutorModule({
    required this.id,
    required this.courseCode,
    this.courseName,
    this.grade,
    required this.priceUgx,
  });

  factory TutorModule.fromMap(Map<String, dynamic> m) => TutorModule(
        id: m['id'] ?? '',
        courseCode: m['course_code'] ?? '',
        courseName: m['course_name'],
        grade: m['grade_achieved'],
        priceUgx: (m['price_ugx'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'course_code': courseCode,
        'course_name': courseName,
        'grade_achieved': grade,
        'price_ugx': priceUgx,
      };
}

/// A tutor as shown to students: who they are, what they teach, how they are rated.
class TutorCard {
  final String tutorId;
  final String name;
  final String? programme;
  final int? year;
  final bool verified; // blue tick, earned
  final String bio;
  final String? contact;
  final String availability;
  final List<TutorModule> modules;
  final double score; // fair (Bayesian) score, 0 if no data
  final int reviews;
  final int reviewers;

  const TutorCard({
    required this.tutorId,
    required this.name,
    this.programme,
    this.year,
    this.verified = false,
    this.bio = '',
    this.contact,
    this.availability = '',
    this.modules = const [],
    this.score = 0,
    this.reviews = 0,
    this.reviewers = 0,
  });
}

class TutorRequest {
  final String id;
  final String studentId;
  final String studentName;
  final String tutorId;
  final String tutorName;
  final String courseCode;
  final String message;
  final String status; // pending | accepted | declined | completed
  final DateTime createdAt;
  final bool reviewed;

  const TutorRequest({
    required this.id,
    required this.studentId,
    this.studentName = '',
    required this.tutorId,
    this.tutorName = '',
    required this.courseCode,
    this.message = '',
    this.status = 'pending',
    required this.createdAt,
    this.reviewed = false,
  });

  factory TutorRequest.fromMap(Map<String, dynamic> m) => TutorRequest(
        id: m['id'],
        studentId: m['student_id'] ?? '',
        studentName: m['student_name'] ?? '',
        tutorId: m['tutor_id'] ?? '',
        tutorName: m['tutor_name'] ?? '',
        courseCode: m['course_code'] ?? '',
        message: m['message'] ?? '',
        status: m['status'] ?? 'pending',
        createdAt: _dt(m['created_at']),
        reviewed: m['reviewed'] ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'student_id': studentId,
        'student_name': studentName,
        'tutor_id': tutorId,
        'tutor_name': tutorName,
        'course_code': courseCode,
        'message': message,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'reviewed': reviewed,
      };
}
