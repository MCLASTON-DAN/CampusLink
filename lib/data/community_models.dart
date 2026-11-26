import 'dart:math' as math;

// Models for the community side of CampusLink: who speaks for whom, news,
// comments, campuses, lost & found, surveys and tutors.
// Every class has fromMap/toMap so it works for Supabase rows and for the
// local JSON store used in demo mode.

DateTime _dt(dynamic v) =>
    v == null ? DateTime.now() : (v is DateTime ? v : DateTime.parse(v.toString()));
DateTime? _dtn(dynamic v) => v == null ? null : _dt(v);
List<String> _strs(dynamic v) =>
    v == null ? const [] : List<String>.from((v as List).map((e) => e.toString()));

/// Badge colour that goes with an office: red = administration, green = guild,
/// purple = newsroom. Anything unknown gets no badge (never a wrong one).
String? badgeForKind(String? kind) => switch (kind) {
      'administration' => 'red',
      'guild' => 'green',
      'press' => 'purple',
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
      Publisher(id: m['id'], kind: m['kind'] ?? 'unknown', name: m['name'] ?? '');
  Map<String, dynamic> toMap() => {'id': id, 'kind': kind, 'name': name};
}

/// A person's right to speak for an office, for a limited time.
class Membership {
  final String id;
  final String publisherId;
  final String publisherName;
  /// Office kind (administration, guild, press). Null when unknown: no badge.
  final String? publisherKind;
  final String userId;
  final String? userName;
  final String positionTitle;
  final List<String> scopes;
  final DateTime startsAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;
  final String? username;
  final String? endKind; // null | early | removed
  final String? endReason;

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
    this.username,
    this.endKind,
    this.endReason,
  });

  /// 'active' | 'ended' (reached end date) | 'early' | 'removed'
  String get state {
    if (revokedAt != null) return endKind == 'removed' ? 'removed' : 'early';
    return DateTime.now().isBefore(expiresAt) ? 'active' : 'ended';
  }

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
        publisherKind: m['publisher_kind'] as String?,
        userId: m['user_id'] ?? '',
        userName: m['user_name'],
        positionTitle: m['position_title'] ?? '',
        scopes: _strs(m['scopes']),
        startsAt: _dt(m['starts_at']),
        expiresAt: _dt(m['expires_at']),
        revokedAt: _dtn(m['revoked_at']),
        username: m['username'],
        endKind: m['end_kind'],
        endReason: m['end_reason'],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'username': username,
        'end_kind': endKind,
        'end_reason': endReason,
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
  /// Office kind (administration, guild, press). Null when unknown: no badge.
  final String? publisherKind;
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

  /// Set when the post was retracted; [retractReason] is shown to everyone.
  final DateTime? retractedAt;
  final String? retractReason;
  bool get isRetracted => retractedAt != null;
  final DateTime? expiresAt;
  final int likes;
  final int comments;
  final bool likedByMe;

  const Post({
    required this.id,
    required this.publisherId,
    this.publisherName = '',
    this.publisherKind,
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
    this.retractedAt,
    this.retractReason,
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
        retractedAt: retractedAt,
        retractReason: retractReason,
        expiresAt: expiresAt,
        likes: likes ?? this.likes,
        comments: comments ?? this.comments,
        likedByMe: likedByMe ?? this.likedByMe,
      );

  factory Post.fromMap(Map<String, dynamic> m) => Post(
        id: m['id'],
        publisherId: m['publisher_id'] ?? '',
        publisherName: m['publisher_name'] ?? '',
        publisherKind: m['publisher_kind'] as String?,
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
        retractedAt: _dtn(m['retracted_at']),
        retractReason: m['retract_reason'],
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
        'retracted_at': retractedAt?.toIso8601String(),
        'retract_reason': retractReason,
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
  final String? parentId; // set on replies (one level deep)

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
    this.parentId,
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
        parentId: m['parent_id'],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'parent_id': parentId,
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
  /// Office kind (administration, guild, press). Null when unknown: no badge.
  final String? publisherKind;
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
    this.publisherKind,
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
        publisherKind: m['publisher_kind'] as String?,
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
  /// A reviewer saw the results slip for this unit and grade.
  final bool gradeChecked;
  const TutorModule({
    required this.id,
    required this.courseCode,
    this.courseName,
    this.grade,
    required this.priceUgx,
    this.gradeChecked = false,
  });

  factory TutorModule.fromMap(Map<String, dynamic> m) => TutorModule(
        id: m['id'] ?? '',
        courseCode: m['course_code'] ?? '',
        courseName: m['course_name'],
        grade: m['grade_achieved'],
        priceUgx: (m['price_ugx'] ?? 0) as int,
        gradeChecked: m['grade_checked'] == true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'course_code': courseCode,
        'course_name': courseName,
        'grade_achieved': grade,
        'price_ugx': priceUgx,
        'grade_checked': gradeChecked,
      };
}

/// Same rule as the database's norm_code(): no spaces, capitals.
String normCode(String c) => c.toUpperCase().replaceAll(RegExp(r'\s+'), '');

class TutorCard {
  final String tutorId;
  final String name;
  final String? username;
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
    this.username,
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
    this.lessons = 0,
    this.paused = false,
    this.upheld = 0,
    this.outcomeReports = 0,
    this.outcomeBands,
    this.outcomeConfidence = 0,
    this.rateUgx,
    this.rateUnit = 'hour',
    this.negotiable = false,
    this.firstSessionFree = false,
    this.mode = 'both',
    this.hasContact = false,
    this.hasWhatsapp = false,
  });

  /// General price (0022). Null = not set, 0 = free. A unit's own price wins.
  final int? rateUgx;
  final String rateUnit; // hour | session | week | month
  final bool negotiable;
  final bool firstSessionFree;
  final String mode; // in_person | online | both

  /// The tutor saved a phone or email (the number itself stays private).
  final bool hasContact;
  final bool hasWhatsapp;

  /// Lessons the tutor has actually taught (students confirmed them).
  final int lessons;
  /// Hidden from the list while 3+ students have open reports.
  final bool paused;

  /// Reports staff upheld against this tutor.
  final int upheld;

  /// Students who reported their grade band after lessons.
  final int outcomeReports;

  /// Counts per band [<50, 50-59, 60-69, 70-79, 80+]. Null until 5+ reports,
  /// so a tiny sample never looks like a big result.
  final List<int>? outcomeBands;

  /// Cautious share of students at 60+ (Wilson lower bound). 1 of 1 ≈ 0.21.
  final double outcomeConfidence;

  /// Units whose grade a reviewer checked.
  List<TutorModule> get checkedModules => modules.where((m) => m.gradeChecked).toList();

  /// The 4 levels. Same rules as the database (0014):
  /// 1 New: grades typed in only. Found by search, never suggested.
  /// 2 Grade-checked: a results slip was checked. Suggested for those units.
  /// 3 Experienced: + 10 lessons, rating 4.0+ from 3+ reviews, AND results:
  ///   5+ students reported and the cautious 60+ share is at least 0.35.
  /// 4 Expert: the blue tick (set by the database: 30 lessons, 4.3+, 5+
  ///   reviewers, no upheld reports, 10+ results with 60+ confidence 0.5+).
  int get levelNo {
    if (verified) return 4;
    if (checkedModules.isEmpty) return 1;
    if (lessons >= 10 && reviews >= 3 && score >= 4.0 && upheld == 0 && outcomeReports >= 5 && outcomeConfidence >= 0.35) {
      return 3;
    }
    return 2;
  }

  String get level => const ['New', 'Grade-checked', 'Experienced', 'Expert'][levelNo - 1];

  /// Shown in the platform's suggestions (not just search).
  bool get suggested => levelNo >= 2 && !paused;
}

const outcomeBandLabels = ['Below 50', '50–59', '60–69', '70–79', '80+'];

/// The semester a date falls in, e.g. 2026-S2 (July–December).
String semesterOf(DateTime d) => '${d.year}-S${d.month <= 6 ? 1 : 2}';

/// Cautious share of "good" out of n (Wilson lower bound, 95%). Same as the database.
double outcomeConfidence(int good, int n) {
  if (n == 0) return 0;
  final p = good / n;
  const z = 1.96;
  final centre = p + z * z / (2 * n);
  final spread = z * math.sqrt((p * (1 - p) + z * z / (4 * n)) / n);
  return (centre - spread) / (1 + z * z / n);
}

/// A tutor's results slip waiting for, or past, a check.
class GradeProof {
  GradeProof({
    required this.id,
    required this.tutorId,
    this.tutorName = '',
    required this.courseCode,
    required this.grade,
    required this.filePath,
    required this.status,
    this.reason,
    required this.createdAt,
  });
  final String id, tutorId, tutorName, courseCode, grade, filePath, status;
  final String? reason;
  final DateTime createdAt;
  bool get pending => status == 'pending';
  /// Waiting longer than this shows up as overdue for staff.
  bool get overdue => pending && DateTime.now().difference(createdAt).inDays >= 3;
  factory GradeProof.fromMap(Map<String, dynamic> m, {String name = ''}) => GradeProof(
        id: m['id'],
        tutorId: m['tutor_id'],
        tutorName: name,
        courseCode: m['course_code'] ?? '',
        grade: m['grade_claimed'] ?? '',
        filePath: m['file_path'] ?? '',
        status: m['status'] ?? 'pending',
        reason: m['reason'],
        createdAt: DateTime.parse(m['created_at'].toString()),
      );
  Map<String, dynamic> toMap() => {
        'id': id,
        'tutor_id': tutorId,
        'course_code': courseCode,
        'grade_claimed': grade,
        'file_path': filePath,
        'status': status,
        'reason': reason,
        'created_at': createdAt.toIso8601String(),
      };
}

const tutorReportReasons = {
  'no_show': 'Did not show up / unavailable',
  'unprofessional': 'Unprofessional behaviour',
  'poor_teaching': 'Poor or wrong teaching',
  'overcharging': 'Overcharging or payment problems',
  'harassment': 'Harassment or made me unsafe',
  'other': 'Something else',
};

class TutorReportRow {
  TutorReportRow({
    required this.tutorId,
    required this.tutorName,
    required this.reason,
    required this.n,
    required this.pct,
    required this.total,
    required this.reporters,
    required this.open,
  });
  final String tutorId, tutorName, reason;
  final int n, total, reporters, open;
  final double pct;
  factory TutorReportRow.fromMap(Map<String, dynamic> m) => TutorReportRow(
        tutorId: m['tutor_id'],
        tutorName: m['tutor_name'] ?? '',
        reason: m['reason'],
        n: (m['n'] as num).toInt(),
        pct: (m['pct'] as num).toDouble(),
        total: (m['total'] as num).toInt(),
        reporters: (m['reporters'] as num).toInt(),
        open: (m['open_reports'] as num).toInt(),
      );
}

class CourseNotice {
  CourseNotice({
    required this.id,
    required this.lecturerId,
    required this.lecturerName,
    required this.courseCodes,
    required this.title,
    required this.body,
    this.linkUrl,
    this.priority = 'normal',
    required this.createdAt,
  });
  final String id, lecturerId, lecturerName, title, body, priority;
  final List<String> courseCodes;
  final String? linkUrl;
  final DateTime createdAt;
  factory CourseNotice.fromMap(Map<String, dynamic> m) => CourseNotice(
        id: m['id'],
        lecturerId: m['lecturer_id'],
        lecturerName: m['lecturer_name'] ?? '',
        courseCodes: List<String>.from(m['course_codes'] ?? const []),
        title: m['title'],
        body: m['body'],
        linkUrl: m['link_url'],
        priority: m['priority'] ?? 'normal',
        createdAt: DateTime.parse(m['created_at'].toString()),
      );
  Map<String, dynamic> toMap() => {
        'id': id,
        'lecturer_id': lecturerId,
        'lecturer_name': lecturerName,
        'course_codes': courseCodes,
        'title': title,
        'body': body,
        'link_url': linkUrl,
        'priority': priority,
        'created_at': createdAt.toIso8601String(),
      };
}

/// How a post is doing. Only the posting office and admins can see this.
class PostInsight {
  PostInsight({
    required this.postId,
    required this.title,
    required this.publisherName,
    required this.publishedAt,
    required this.views,
    required this.views24h,
    required this.views7d,
    required this.comments,
    required this.likes,
  });
  final String postId, title, publisherName;
  final DateTime publishedAt;
  final int views, views24h, views7d, comments, likes;
  factory PostInsight.fromMap(Map<String, dynamic> m) {
    int n(String k) => ((m[k] ?? 0) as num).toInt();
    return PostInsight(
      postId: m['post_id'],
      title: m['title'] ?? '',
      publisherName: m['publisher_name'] ?? '',
      publishedAt: DateTime.parse(m['published_at'].toString()),
      views: n('views'),
      views24h: n('views_24h'),
      views7d: n('views_7d'),
      comments: n('comments'),
      likes: n('likes'),
    );
  }
}

/// The admin dashboard numbers.
class AdminOverview {
  AdminOverview(this.m);
  final Map<String, dynamic> m;
  int n(String k) => ((m[k] ?? 0) as num).toInt();
  List<(DateTime, int)> get dailyActive => [
        for (final d in (m['daily_active'] as List? ?? const []))
          (DateTime.parse('${d['day']}'), ((d['n'] ?? 0) as num).toInt()),
      ];
  List<(String, String, int)> get topPosts => [
        for (final p in (m['top_posts'] as List? ?? const []))
          ('${p['id']}', '${p['title']}', ((p['views'] ?? 0) as num).toInt()),
      ];
}

class Rsvp {
  Rsvp({required this.eventId, required this.code, this.checkedInAt});
  final String eventId;
  /// Private 6-character code, shown as a QR at the door.
  final String code;
  final DateTime? checkedInAt;
  factory Rsvp.fromMap(Map<String, dynamic> m) => Rsvp(
        eventId: m['event_id'],
        code: m['code'],
        checkedInAt: m['checked_in_at'] == null ? null : DateTime.parse('${m['checked_in_at']}'),
      );
}

/// A poll or quiz question inside a news post.
class PostQuestion {
  PostQuestion({
    this.id = '',
    required this.kind,
    required this.prompt,
    required this.options,
    this.correctIndex,
    this.myAnswer,
    this.counts,
    this.total = 0,
  });
  final String id;
  final String kind; // poll | quiz
  final String prompt;
  final List<String> options;
  /// Quiz only. Hidden (null) until you have answered.
  final int? correctIndex;
  final int? myAnswer;
  /// Votes per option. Hidden (null) until you have answered.
  final List<int>? counts;
  final int total;
  bool get isQuiz => kind == 'quiz';
  bool get answered => myAnswer != null;

  /// The same rules the database enforces. Null means it is fine.
  String? get problem {
    final p = prompt.trim();
    final opts = options.map((o) => o.trim()).toList();
    if (p.length < 3 || p.length > 200) return 'Each question needs 3 to 200 letters.';
    if (opts.length < 2 || opts.length > 6) return 'Give 2 to 6 answer choices.';
    if (opts.any((o) => o.isEmpty)) return 'Fill in every answer choice, or remove the empty one.';
    if (opts.toSet().length != opts.length) return 'Two answer choices are the same.';
    if (isQuiz && (correctIndex == null || correctIndex! < 0 || correctIndex! >= opts.length)) {
      return 'Pick the right answer for each quiz question.';
    }
    return null;
  }
  factory PostQuestion.fromMap(Map<String, dynamic> m) => PostQuestion(
        id: m['id'],
        kind: m['kind'],
        prompt: m['prompt'],
        options: List<String>.from(m['options'] ?? const []),
        correctIndex: m['correct_index'],
        myAnswer: m['my_answer'],
        counts: m['counts'] == null ? null : List<int>.from((m['counts'] as List).map((e) => (e as num).toInt())),
        total: ((m['total'] ?? 0) as num).toInt(),
      );
}

/// A person found by username or name, for appointing.
class PersonHit {
  PersonHit({
    required this.id,
    required this.fullName,
    this.username,
    this.programme,
    this.year,
    this.avatar,
    this.badge,
    this.officeTitle,
  });
  final String id, fullName;
  final String? username, programme, avatar, badge, officeTitle;
  final int? year;
  factory PersonHit.fromMap(Map<String, dynamic> m) => PersonHit(
        id: m['id'],
        fullName: m['full_name'] ?? '',
        username: m['username'],
        programme: m['programme'],
        year: m['year_of_study'],
        avatar: m['avatar_path'],
        badge: m['badge'],
        officeTitle: m['office_title'],
      );
}

class CourseLecturer {
  CourseLecturer({required this.courseCode, required this.lecturerId, required this.name});
  final String courseCode, lecturerId, name;
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    this.body = '',
    this.link,
    this.priority = 'normal',
    required this.createdAt,
    this.read = false,
  });
  final String id, kind, title, body, priority;
  final String? link;
  final DateTime createdAt;
  final bool read;
  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'],
        kind: m['kind'] ?? 'official',
        title: m['title'] ?? '',
        body: m['body'] ?? '',
        link: m['link'],
        priority: m['priority'] ?? 'normal',
        createdAt: DateTime.parse(m['created_at'].toString()),
        read: m['read_at'] != null,
      );
  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind,
        'title': title,
        'body': body,
        'link': link,
        'priority': priority,
        'created_at': createdAt.toIso8601String(),
        'read_at': read ? DateTime.now().toIso8601String() : null,
      };
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
