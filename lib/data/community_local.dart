import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'community_models.dart';
import 'community_repository.dart';
import 'models.dart';
import 'seed_data.dart';

/// Demo backend for the community features. Same rules as the database
/// (see supabase/migrations/0002), stored as JSON on the device.
class LocalCommunity implements CommunityApi {
  LocalCommunity(this._prefs, this._user) {
    _load();
  }

  final SharedPreferences _prefs;
  final Profile? Function() _user;
  static const _uuid = Uuid();
  static const _k = 'campuslink.community.v1';

  late Map<String, dynamic> _s; // the whole store

  // ---------------------------------------------------------------- store
  List<Map<String, dynamic>> _list(String key) =>
      ((_s[key] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e)).toList();
  void _put(String key, List<Map<String, dynamic>> v) => _s[key] = v;
  Future<void> _save() => _prefs.setString(_k, jsonEncode(_s));
  Future<T> _tick<T>(T v) => Future.delayed(const Duration(milliseconds: 100), () => v);

  Profile get _me {
    final u = _user();
    if (u == null) throw CommunityException('Please sign in first');
    return u;
  }

  void _load() {
    final raw = _prefs.getString(_k);
    if (raw != null) {
      _s = Map<String, dynamic>.from(jsonDecode(raw));
      if (_s['seeded'] == true) return;
    } else {
      _s = {};
    }
    final now = DateTime.now();
    final admin = {'id': 'pub-admin', 'kind': 'administration', 'name': 'Cavendish University Uganda Administration'};
    final guild = {'id': 'pub-guild', 'kind': 'guild', 'name': 'Cavendish University Guild Office'};
    final press = {'id': 'pub-press', 'kind': 'press', 'name': 'Cavendish Campus Newsroom'};
    _s['publishers'] = [admin, guild, press];
    _s['members'] = <Map<String, dynamic>>[];
    _s['comments'] = <Map<String, dynamic>>[];
    _s['likes'] = <String>[];
    _s['reports'] = <Map<String, dynamic>>[];
    _s['moderation'] = <Map<String, dynamic>>[];
    _s['campuses'] = <Map<String, dynamic>>[];
    _s['offices'] = <Map<String, dynamic>>[];
    _s['claims'] = <Map<String, dynamic>>[];
    _s['participation'] = <String>[];
    _s['answers'] = <Map<String, dynamic>>[];
    _s['tutorProfiles'] = <String, dynamic>{};
    _s['requests'] = <Map<String, dynamic>>[];
    _s['acceptances'] = <String>[];

    // Clearly-marked SAMPLE content so the demo is not empty. Not real news.
    _s['posts'] = [
      Post(
        id: 'sample-post-1',
        publisherId: 'pub-guild',
        publisherName: guild['name']!,
        publisherKind: 'guild',
        authorId: 'sample',
        authorName: 'Sample author',
        authorPosition: 'Minister of Information (sample)',
        kind: 'news',
        title: 'SAMPLE: this is how a news post looks',
        body: 'This is a sample post so you can see the layout. Real posts come only from verified office '
            'holders, each one shows who posted it, their position and where the information comes from.',
        sourceNote: 'Sample data. Not real news.',
        publishedAt: now.subtract(const Duration(hours: 3)),
      ).toMap(),
      Post(
        id: 'sample-post-2',
        publisherId: 'pub-admin',
        publisherName: admin['name']!,
        publisherKind: 'administration',
        authorId: 'sample',
        authorName: 'Sample author',
        authorPosition: 'Registrar (sample)',
        kind: 'clarification',
        title: 'SAMPLE: clarification that answers a rumour',
        body: 'When a rumour spreads, an official clarification can be posted here, with the source, so students '
            'can see what is actually true.',
        sourceNote: 'Sample data. Not a real announcement.',
        publishedAt: now.subtract(const Duration(days: 1)),
      ).toMap(),
    ];

    // Events: seed ones + mutable copies
    final evs = SeedData.events.map((e) => e.toMap()).toList();
    evs.first['major_status'] = 'requested';
    evs.first['major_reason'] = 'Sample: final of the university-wide innovation challenge, open to every faculty.';
    evs.first['publisher_id'] = 'pub-guild';
    evs.first['publisher_name'] = guild['name'];
    evs.first['publisher_kind'] = 'guild';
    _s['events'] = evs;

    _s['lostFound'] = [
      LostFoundItem(
        id: 'sample-lf-1',
        publisherId: 'pub-guild',
        title: 'SAMPLE: black umbrella',
        description: 'Sample item. Owners must prove it is theirs.',
        foundWhere: 'Near the main gate',
        storedAt: 'Guild Office',
        foundOn: now.subtract(const Duration(days: 2)),
      ).toMap(),
    ];

    final sq = [
      SurveyQuestion(id: 'q1', position: 1, prompt: 'How satisfied are you with the canteen?', kind: 'scale', options: ['1', '2', '3', '4', '5']).toMap(),
      SurveyQuestion(id: 'q2', position: 2, prompt: 'What should improve first?', kind: 'single', options: ['Prices', 'Variety', 'Queues', 'Cleanliness']).toMap(),
    ];
    _s['surveys'] = [
      Survey(
        id: 'sample-survey-1',
        publisherId: 'pub-guild',
        publisherName: guild['name']!,
        publisherKind: 'guild',
        title: 'SAMPLE: canteen satisfaction',
        purpose: 'A sample survey: it shows why we ask, one answer each, anonymous results.',
        closesAt: now.add(const Duration(days: 7)),
        questions: sq.map(SurveyQuestion.fromMap).toList(),
      ).toMap()
    ];
    final sampleAnswers = <Map<String, dynamic>>[];
    for (var i = 0; i < 7; i++) {
      sampleAnswers.add({'survey_id': 'sample-survey-1', 'question_id': 'q1', 'answer': ['3', '4', '4', '5', '2', '4', '3'][i]});
      sampleAnswers.add({'survey_id': 'sample-survey-1', 'question_id': 'q2', 'answer': ['Prices', 'Queues', 'Prices', 'Variety', 'Prices', 'Queues', 'Cleanliness'][i]});
    }
    _s['answers'] = sampleAnswers;
    _s['participation'] = [for (var i = 0; i < 7; i++) 'sample-$i|sample-survey-1'];

    // Sample tutor reviews (12 from 6 students for Amina => earns the blue tick).
    final reviews = <Map<String, dynamic>>[];
    for (var i = 0; i < 12; i++) {
      reviews.add({'tutor_id': 'u-tutor-1', 'course_code': 'STA2101', 'student_id': 'sample-s${i % 6}', 'rating': i % 4 == 0 ? 4 : 5});
    }
    for (var i = 0; i < 3; i++) {
      reviews.add({'tutor_id': 'u-tutor-2', 'course_code': 'CSC2102', 'student_id': 'sample-t$i', 'rating': 5});
    }
    _s['reviews'] = reviews;
    _s['tutorModules'] = [
      {'id': 'm1', 'tutor_id': 'u-tutor-1', 'course_code': 'STA2101', 'course_name': 'Statistics', 'grade_achieved': 'A', 'price_ugx': 15000},
      {'id': 'm2', 'tutor_id': 'u-tutor-1', 'course_code': 'BDA2207', 'course_name': 'Data Analysis', 'grade_achieved': 'A', 'price_ugx': 15000},
      {'id': 'm3', 'tutor_id': 'u-tutor-2', 'course_code': 'CSC2102', 'course_name': 'Databases', 'grade_achieved': 'B+', 'price_ugx': 10000},
      {'id': 'm4', 'tutor_id': 'u-tutor-3', 'course_code': 'WEB2201', 'course_name': 'Web Development', 'grade_achieved': 'A', 'price_ugx': 12000},
    ];
    _s['tutorProfiles']['u-tutor-1'] = {'bio': 'Third-year BDSAI. Patient with beginners (sample profile).', 'contact': null, 'availability': 'Weekday evenings'};
    _s['tutorProfiles']['u-tutor-2'] = {'bio': 'Fourth-year CS (sample profile).', 'contact': null, 'availability': 'Saturdays'};
    _s['tutorProfiles']['u-tutor-3'] = {'bio': 'Web and UI (sample profile).', 'contact': null, 'availability': 'Afternoons'};
    _s['seeded'] = true;
    _save();
  }

  /// Called by the demo sign-in so the e-mail picks a role for the demo:
  /// "super" -> super admin, "admin" -> administration, "guild" -> guild member,
  /// "president" -> guild president who can appoint others.
  Profile onSignIn(Profile p, String email) {
    final e = email.toLowerCase();
    var role = p.role;
    if (e.contains('super')) role = UserRole.superAdmin;
    final members = _list('members')..removeWhere((m) => m['user_id'] == p.id);
    final now = DateTime.now();
    void add(String pubId, String pubName, String kind, String title, List<String> scopes) {
      members.add(Membership(
        id: _uuid.v4(),
        publisherId: pubId,
        publisherName: pubName,
        publisherKind: kind,
        userId: p.id,
        userName: p.fullName,
        positionTitle: title,
        scopes: scopes,
        startsAt: now.subtract(const Duration(days: 1)),
        expiresAt: now.add(const Duration(days: 330)),
      ).toMap());
    }

    const all = ['news', 'notices', 'events', 'meeting_links', 'surveys', 'lost_found'];
    if (e.contains('admin')) {
      role = role == UserRole.superAdmin ? role : UserRole.admin;
      add('pub-admin', 'Cavendish University Uganda Administration', 'administration', 'Administrator (demo)', [...all, 'manage_members']);
    }
    if (e.contains('guild') || e.contains('president')) {
      add('pub-guild', 'Cavendish University Guild Office', 'guild',
          e.contains('president') ? 'Guild President (demo)' : 'Minister of ICT (demo)',
          [...all, if (e.contains('president')) 'manage_members']);
    }
    if (e.contains('press') || e.contains('news')) {
      add('pub-press', 'Cavendish Campus Newsroom', 'press', 'Campus reporter (demo)', ['news', 'events']);
    }
    _put('members', members);
    _save();
    final badge = role == UserRole.superAdmin || e.contains('admin')
        ? 'red'
        : e.contains('guild') || e.contains('president')
            ? 'green'
            : (e.contains('press') || e.contains('news'))
                ? 'purple'
                : null;
    return p.copyWith(role: role, badge: badge);
  }

  // ------------------------------------------------------------- identity
  @override
  Future<List<Membership>> myMemberships() => _tick(_list('members')
      .map(Membership.fromMap)
      .where((m) => m.userId == _me.id)
      .toList());

  @override
  Future<List<Publisher>> publishers() => _tick(_list('publishers').map(Publisher.fromMap).toList());

  @override
  Future<List<Membership>> membersOf(String publisherId) => _tick(_list('members')
      .map(Membership.fromMap)
      .where((m) => m.publisherId == publisherId)
      .toList());

  bool _can(String publisherId, String scope) {
    if (_me.isSuperAdmin) return true;
    return _list('members')
        .map(Membership.fromMap)
        .any((m) => m.userId == _me.id && m.publisherId == publisherId && m.can(scope));
  }

  Membership? _activeMembership(String publisherId) {
    for (final m in _list('members').map(Membership.fromMap)) {
      if (m.userId == _me.id && m.publisherId == publisherId && m.isActive) return m;
    }
    return null;
  }

  // Demo people to search for (on a real server this is everyone signed up).
  List<PersonHit> get _demoPeople => [
        for (final t in SeedData.tutors)
          PersonHit(
            id: t.id,
            fullName: t.fullName,
            username: t.fullName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '.'),
            programme: t.programme,
            year: t.yearOfStudy,
          ),
        PersonHit(id: 'local-ruth', fullName: 'Ruth Namuli', username: 'ruth.namuli', programme: 'BBA', year: 2),
        PersonHit(id: 'local-brian', fullName: 'Brian Okello', username: 'brian.okello', programme: 'BIT', year: 3),
        PersonHit(id: 'local-grace', fullName: 'Grace Achieng', username: 'grace.a', programme: 'BDSAI', year: 2),
      ];

  @override
  Future<List<PersonHit>> searchPeople(String query) async {
    final q = query.trim().toLowerCase().replaceAll('@', '');
    if (q.length < 2) return [];
    return _tick(_demoPeople
        .where((p) => (p.username ?? '').startsWith(q) || p.fullName.toLowerCase().contains(q))
        .take(10)
        .toList());
  }

  @override
  Future<void> renewTerm(String membershipId, DateTime newEnd) async {
    if (newEnd.isAfter(DateTime.now().add(const Duration(days: 366)))) {
      throw CommunityException('A term can last at most 12 months from today');
    }
    final members = _list('members');
    final i = members.indexWhere((m) => m['id'] == membershipId);
    if (i < 0) return;
    if (!_can(members[i]['publisher_id'], 'manage_members')) throw CommunityException('Not allowed');
    members[i]['expires_at'] = newEnd.toIso8601String();
    _put('members', members);
    await _save();
  }

  @override
  Future<List<Membership>> officeHistory() =>
      _tick(_list('members').map(Membership.fromMap).where((m) => m.revokedAt != null).toList().reversed.toList());

  @override
  Future<void> appointMember({
    required String publisherId,
    required String userId,
    required String positionTitle,
    required List<String> scopes,
    required DateTime expiresAt,
  }) async {
    if (!_can(publisherId, 'manage_members')) throw CommunityException('You cannot appoint members for this office');
    if (expiresAt.isAfter(DateTime.now().add(const Duration(days: 366)))) {
      throw CommunityException('A term can last at most 12 months');
    }
    if (positionTitle.trim().length < 3) throw CommunityException('Write the position, e.g. Minister of Welfare');
    final uid = userId;
    if (uid == _me.id) throw CommunityException('You cannot appoint yourself');
    final person = _demoPeople.where((p) => p.id == uid).firstOrNull;
    final pub = _list('publishers').firstWhere((p) => p['id'] == publisherId);
    final members = _list('members');
    members.add(Membership(
      id: _uuid.v4(),
      publisherId: publisherId,
      publisherName: pub['name'],
      publisherKind: pub['kind'],
      userId: uid,
      userName: person?.fullName ?? 'Student',
      username: person?.username,
      positionTitle: positionTitle.trim(),
      scopes: scopes,
      startsAt: DateTime.now(),
      expiresAt: expiresAt,
    ).toMap());
    _put('members', members);
    await _save();
  }

  @override
  Future<void> endTerm(String membershipId, {required String kind, required String reason}) async {
    final members = _list('members');
    final i = members.indexWhere((m) => m['id'] == membershipId);
    if (i < 0) return;
    if (!_can(members[i]['publisher_id'], 'manage_members')) throw CommunityException('Not allowed');
    if (kind == 'removed' && !_me.isSuperAdmin) {
      throw CommunityException('Only the super admin can remove someone for misconduct.');
    }
    if (kind == 'removed' && reason.trim().length < 20) {
      throw CommunityException('Explain why they were removed (at least 20 characters). It will be shown publicly.');
    }
    if (reason.trim().length < 3) throw CommunityException('Give a short reason for ending the term early.');
    members[i]['revoked_at'] = DateTime.now().toIso8601String();
    members[i]['end_kind'] = kind;
    members[i]['end_reason'] = reason.trim();
    _put('members', members);
    await _save();
  }

  // ------------------------------------------------------------------ news
  Post _withStats(Map<String, dynamic> m, String type) {
    final id = m['id'];
    final likes = (_s['likes'] as List).cast<String>();
    final base = likes.where((l) => l.endsWith('|$type|$id')).length;
    final comments = _list('comments').where((c) => c['target_type'] == type && c['target_id'] == id).length;
    return Post.fromMap({...m, 'likes': base, 'comments': comments, 'liked_by_me': likes.contains('${_me.id}|$type|$id')});
  }

  @override
  Future<List<Post>> posts({String? kind, int limit = 20, DateTime? before}) {
    final now = DateTime.now();
    final list = _list('posts')
        .where((m) => m['status'] == 'published')
        .map((m) => _withStats(m, 'post'))
        .where((p) => (p.expiresAt == null || p.expiresAt!.isAfter(now)) &&
            (kind == null || p.kind == kind) &&
            (before == null || p.publishedAt.isBefore(before)))
        .toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return _tick(list.take(limit).toList());
  }

  @override
  Future<Post?> post(String id) {
    final m = _list('posts').where((p) => p['id'] == id && p['status'] == 'published').toList();
    return _tick(m.isEmpty ? null : _withStats(m.first, 'post'));
  }

  static const _kindScope = {
    'news': 'news',
    'clarification': 'news',
    'notice': 'notices',
    'official_record': 'notices',
    'meeting_link': 'meeting_links',
  };

  @override
  Future<Post> createPost({
    required String publisherId,
    required String kind,
    required String title,
    required String body,
    required String sourceNote,
    String? videoUrl,
    String? meetingUrl,
    String? coverPath,
    DateTime? expiresAt,
    String? correctsPostId,
  }) async {
    final scope = _kindScope[kind];
    if (scope == null || !_can(publisherId, scope)) {
      throw CommunityException('You do not have the right to post this kind of item for this office');
    }
    if (title.trim().length < 5 || title.trim().length > 140) throw CommunityException('Title must be 5–140 characters');
    if (body.trim().length < 20) throw CommunityException('Write at least 20 characters');
    if (sourceNote.trim().length < 10) throw CommunityException('Say where this information comes from (10+ characters)');
    final yt = RegExp(r'^https://(www\.)?(youtube\.com/watch\?v=|youtu\.be/|youtube-nocookie\.com/embed/)', caseSensitive: false);
    if (videoUrl != null && videoUrl.isNotEmpty && !yt.hasMatch(videoUrl)) {
      throw CommunityException('Videos must be YouTube links (https://youtu.be/…)');
    }
    if (meetingUrl != null && meetingUrl.isNotEmpty && !meetingUrl.startsWith('https://')) {
      throw CommunityException('Meeting links must start with https://');
    }
    final recent = _list('posts')
        .where((p) => p['publisher_id'] == publisherId &&
            DateTime.parse(p['published_at']).isAfter(DateTime.now().subtract(const Duration(hours: 24))))
        .length;
    if (recent >= 10 && !_me.isSuperAdmin) {
      throw CommunityException('This office has reached its daily posting limit. Quality-check and try tomorrow.');
    }
    final pub = _list('publishers').firstWhere((p) => p['id'] == publisherId);
    final mem = _activeMembership(publisherId);
    final post = Post(
      id: _uuid.v4(),
      publisherId: publisherId,
      publisherName: pub['name'],
      publisherKind: pub['kind'],
      authorId: _me.id,
      authorName: _me.fullName,
      authorPosition: mem?.positionTitle ?? 'Platform team',
      kind: kind,
      title: title.trim(),
      body: body.trim(),
      videoUrl: (videoUrl?.isEmpty ?? true) ? null : videoUrl,
      meetingUrl: (meetingUrl?.isEmpty ?? true) ? null : meetingUrl,
      coverPath: (coverPath?.isEmpty ?? true) ? null : coverPath,
      sourceNote: sourceNote.trim(),
      correctsPostId: correctsPostId,
      publishedAt: DateTime.now(),
      expiresAt: expiresAt,
    );
    final posts = _list('posts')..insert(0, post.toMap());
    _put('posts', posts);
    await _save();
    return post;
  }

  // ------------------------------------------------- comments, likes, reports
  @override
  Future<List<Comment>> comments(String targetType, String targetId) {
    final members = _list('members').map(Membership.fromMap).toList();
    final list = _list('comments')
        .where((c) => c['target_type'] == targetType && c['target_id'] == targetId && c['status'] != 'removed')
        .map((c) {
      final m = members.where((x) => x.userId == c['author_id'] && x.isActive).toList();
      return Comment.fromMap({
        ...c,
        'badge': m.isEmpty ? null : m.first.badge,
        'office_title': m.isEmpty ? null : m.first.positionTitle,
      });
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return _tick(list);
  }

  @override
  Future<void> addComment(String targetType, String targetId, String body) async {
    final text = body.trim();
    if (text.isEmpty || text.length > 1000) throw CommunityException('Comments must be 1–1000 characters');
    final hourAgo = DateTime.now().subtract(const Duration(hours: 1));
    final mine = _list('comments')
        .where((c) => c['author_id'] == _me.id && DateTime.parse(c['created_at']).isAfter(hourAgo))
        .length;
    if (mine >= 30) throw CommunityException('Slow down: too many comments this hour');
    final list = _list('comments')
      ..add(Comment(
        id: _uuid.v4(),
        targetType: targetType,
        targetId: targetId,
        authorId: _me.id,
        authorName: _me.fullName,
        body: text,
        createdAt: DateTime.now(),
      ).toMap());
    _put('comments', list);
    await _save();
  }

  @override
  Future<void> deleteComment(String id) async {
    final list = _list('comments')..removeWhere((c) => c['id'] == id && c['author_id'] == _me.id);
    _put('comments', list);
    await _save();
  }

  @override
  Future<bool> toggleLike(String targetType, String targetId) async {
    final likes = (_s['likes'] as List).cast<String>().toList();
    final key = '${_me.id}|$targetType|$targetId';
    final liked = !likes.contains(key);
    liked ? likes.add(key) : likes.remove(key);
    _s['likes'] = likes;
    await _save();
    return liked;
  }

  @override
  Future<void> report(String targetType, String targetId, String reason) async {
    if (reason.trim().length < 10) throw CommunityException('Tell us briefly what is wrong (10+ characters)');
    final reports = _list('reports');
    if (reports.any((r) => r['reporter_id'] == _me.id && r['target_id'] == targetId)) {
      throw CommunityException('You already reported this');
    }
    String title = '';
    if (targetType == 'post') {
      final p = _list('posts').where((x) => x['id'] == targetId);
      if (p.isNotEmpty) title = p.first['title'];
    } else if (targetType == 'event') {
      final p = _list('events').where((x) => x['id'] == targetId);
      if (p.isNotEmpty) title = p.first['title'];
    } else {
      final p = _list('comments').where((x) => x['id'] == targetId);
      if (p.isNotEmpty) title = p.first['body'];
    }
    reports.add({
      'id': _uuid.v4(),
      'reporter_id': _me.id,
      'target_type': targetType,
      'target_id': targetId,
      'target_title': title,
      'reason': reason.trim(),
      'status': 'open',
      'created_at': DateTime.now().toIso8601String(),
    });
    _put('reports', reports);
    await _save();
  }

  @override
  Future<List<Report>> openReports() {
    if (!_me.isStaff) throw CommunityException('Not allowed');
    return _tick(_list('reports').where((r) => r['status'] == 'open').map(Report.fromMap).toList());
  }

  // ------------------------------------------------------------ moderation
  @override
  Future<void> moderate({
    required String action,
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    if (reason.trim().length < 20) {
      throw CommunityException('A clear reason (20+ characters) is required. It is shown publicly.');
    }
    String? title;
    if (targetType == 'comment') {
      if (!_me.isStaff) throw CommunityException('Not allowed');
      final list = _list('comments');
      final i = list.indexWhere((c) => c['id'] == targetId);
      if (i < 0) throw CommunityException('Nothing found to act on');
      title = list[i]['body'];
      list[i]['status'] = action == 'remove' ? 'removed' : 'visible';
      _put('comments', list);
    } else {
      if (!_me.isSuperAdmin) throw CommunityException('Only a super admin can act on official posts and events');
      final key = targetType == 'post' ? 'posts' : 'events';
      final list = _list(key);
      final i = list.indexWhere((c) => c['id'] == targetId);
      if (i < 0) throw CommunityException('Nothing found to act on');
      title = list[i]['title'];
      list[i]['status'] = action == 'remove' ? 'removed' : 'published';
      _put(key, list);
    }
    final log = _list('moderation')
      ..insert(
          0,
          ModerationEntry(
            id: _uuid.v4(),
            actorName: _me.fullName,
            targetType: targetType,
            targetTitle: title!.length > 80 ? title.substring(0, 80) : title,
            action: action,
            reason: reason.trim(),
            createdAt: DateTime.now(),
          ).toMap());
    _put('moderation', log);
    final reports = _list('reports');
    for (final r in reports) {
      if (r['target_id'] == targetId && r['status'] == 'open') r['status'] = 'actioned';
    }
    _put('reports', reports);
    await _save();
  }

  @override
  Future<List<ModerationEntry>> moderationLog() => _tick(_list('moderation').map(ModerationEntry.fromMap).toList());

  // ---------------------------------------------------------------- events
  CampusEvent _event(Map<String, dynamic> m) {
    final id = m['id'];
    final likes = (_s['likes'] as List).cast<String>();
    return CampusEvent.fromMap({
      ...m,
      'likes': likes.where((l) => l.endsWith('|event|$id')).length,
      'comments': _list('comments').where((c) => c['target_type'] == 'event' && c['target_id'] == id).length,
      'liked_by_me': likes.contains('${_me.id}|event|$id'),
    });
  }

  @override
  Future<CampusEvent?> event(String id) {
    final m = _list('events').where((e) => e['id'] == id).toList();
    return _tick(m.isEmpty ? null : _event(m.first));
  }

  @override
  Future<List<CampusEvent>> upcomingEvents() {
    final from = DateTime.now().subtract(const Duration(days: 1));
    final list = _list('events').map(_event).where((e) => e.startsAt.isAfter(from)).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return _tick(list);
  }

  @override
  Future<List<CampusEvent>> featuredEvents() {
    final now = DateTime.now();
    final list = _list('events').map(_event).where((e) => e.isFeaturedAt(now)).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return _tick(list.take(2).toList()); // never more than 2 on the home screen
  }

  @override
  Future<CampusEvent> createEvent(CampusEvent e) async {
    if (e.publisherId == null || !_can(e.publisherId!, 'events')) {
      throw CommunityException('You do not have the right to post events for this office');
    }
    if (e.title.trim().length < 5) throw CommunityException('Give the event a clear title');
    var major = e.majorStatus;
    if (major == 'requested') {
      if ((e.majorReason ?? '').trim().length < 30) {
        throw CommunityException('Explain why this event is major (30+ characters)');
      }
      final pending = _list('events')
          .where((x) => x['publisher_id'] == e.publisherId && x['major_status'] == 'requested')
          .length;
      if (pending >= 3) throw CommunityException('This office already has 3 major requests waiting for review');
    } else {
      major = 'none'; // organisers can never approve themselves
    }
    final pub = _list('publishers').firstWhere((p) => p['id'] == e.publisherId);
    final created = CampusEvent(
      id: _uuid.v4(),
      title: e.title.trim(),
      description: e.description,
      startsAt: e.startsAt,
      endsAt: e.endsAt,
      location: e.location,
      organiser: pub['name'],
      publisherId: e.publisherId,
      publisherName: pub['name'],
      publisherKind: pub['kind'],
      createdBy: _me.id,
      topic: e.topic,
      impact: e.impact,
      onlineUrl: e.onlineUrl,
      coverPath: e.coverPath,
      majorStatus: major,
      majorReason: e.majorReason,
      speakers: e.speakers.map((s) => EventSpeaker(id: _uuid.v4(), name: s.name, title: s.title, role: s.role, bio: s.bio)).toList(),
    );
    final list = _list('events')..add(created.toMap());
    _put('events', list);
    await _save();
    return created;
  }

  @override
  Future<void> setMajorStatus(String eventId, String status) async {
    if (!_me.isSuperAdmin) throw CommunityException('Only a platform super admin can approve a major event');
    if (status != 'approved' && status != 'rejected') throw CommunityException('Unknown status');
    final list = _list('events');
    final i = list.indexWhere((e) => e['id'] == eventId);
    if (i < 0) return;
    list[i]['major_status'] = status;
    _put('events', list);
    await _save();
  }

  @override
  Future<List<CampusEvent>> majorRequests() async {
    if (!_me.isSuperAdmin) throw CommunityException('Not allowed');
    return _tick(_list('events').where((e) => e['major_status'] == 'requested').map(_event).toList());
  }

  // ------------------------------------------------------ campuses & offices
  @override
  Future<List<Campus>> campuses() => _tick(_list('campuses').map(Campus.fromMap).toList());

  @override
  Future<void> saveCampus(Campus c) async {
    if (!_me.isStaff) throw CommunityException('Only staff can edit campuses');
    final list = _list('campuses');
    final i = list.indexWhere((x) => x['id'] == c.id);
    i < 0 ? list.add(c.toMap()) : list[i] = c.toMap();
    _put('campuses', list);
    await _save();
  }

  /// Office edits saved in demo mode (layered over the sample offices).
  List<HelpOffice> mergeOffices(List<HelpOffice> base) {
    final over = {for (final m in _list('offices')) m['id']: HelpOffice.fromMap(m)};
    return base.map((o) => over[o.id] ?? o).toList();
  }

  @override
  Future<void> saveOffice(HelpOffice o) async {
    if (!_me.isStaff) throw CommunityException('Only staff can edit offices');
    if ((o.source ?? '').trim().length < 5) {
      throw CommunityException('Say where this information comes from (a document or a person)');
    }
    final list = _list('offices')..removeWhere((x) => x['id'] == o.id);
    list.add(o.copyWith(lastVerifiedAt: DateTime.now()).toMap());
    _put('offices', list);
    await _save();
  }

  // ------------------------------------------------------------ lost & found
  @override
  Future<List<LostFoundItem>> lostFound() {
    final claims = _list('claims').where((c) => c['claimant_id'] == _me.id).toList();
    final list = _list('lostFound').map((m) {
      final mine = claims.where((c) => c['item_id'] == m['id']).toList();
      return LostFoundItem.fromMap({...m, 'my_claim_status': mine.isEmpty ? null : mine.first['status']});
    }).toList()
      ..sort((a, b) => b.foundOn.compareTo(a.foundOn));
    return _tick(list);
  }

  @override
  Future<void> addLostFound({
    required String publisherId,
    required String title,
    required String description,
    required String foundWhere,
    required String storedAt,
    String? photoUrl,
  }) async {
    if (!_can(publisherId, 'lost_found')) throw CommunityException('Only the office that holds items can post them');
    if (title.trim().length < 3) throw CommunityException('Give the item a title');
    final list = _list('lostFound')
      ..add(LostFoundItem(
        id: _uuid.v4(),
        publisherId: publisherId,
        title: title.trim(),
        description: description.trim(),
        photoUrl: photoUrl,
        foundWhere: foundWhere.trim(),
        storedAt: storedAt.trim(),
        foundOn: DateTime.now(),
      ).toMap());
    _put('lostFound', list);
    await _save();
  }

  @override
  Future<void> setLostFoundStatus(String itemId, String status) async {
    final list = _list('lostFound');
    final i = list.indexWhere((x) => x['id'] == itemId);
    if (i < 0) return;
    if (!_can(list[i]['publisher_id'], 'lost_found')) throw CommunityException('Not allowed');
    list[i]['status'] = status;
    _put('lostFound', list);
    await _save();
  }

  @override
  Future<void> claimItem(String itemId, String proof) async {
    if (proof.trim().length < 20) {
      throw CommunityException('Describe something only the owner would know (20+ characters)');
    }
    final claims = _list('claims');
    if (claims.any((c) => c['item_id'] == itemId && c['claimant_id'] == _me.id)) {
      throw CommunityException('You already sent a claim for this item');
    }
    claims.add(LostFoundClaim(
      id: _uuid.v4(),
      itemId: itemId,
      claimantId: _me.id,
      claimantName: _me.fullName,
      proof: proof.trim(),
      createdAt: DateTime.now(),
    ).toMap());
    _put('claims', claims);
    await _save();
  }

  @override
  Future<List<LostFoundClaim>> claimsFor(String itemId) {
    final item = _list('lostFound').firstWhere((x) => x['id'] == itemId);
    if (!_can(item['publisher_id'], 'lost_found')) throw CommunityException('Not allowed');
    return _tick(_list('claims').where((c) => c['item_id'] == itemId).map(LostFoundClaim.fromMap).toList());
  }

  @override
  Future<void> decideClaim(String claimId, {required bool approve}) async {
    final claims = _list('claims');
    final i = claims.indexWhere((c) => c['id'] == claimId);
    if (i < 0) return;
    claims[i]['status'] = approve ? 'approved' : 'rejected';
    _put('claims', claims);
    if (approve) await setLostFoundStatus(claims[i]['item_id'], 'claimed');
    await _save();
  }

  // ----------------------------------------------------------------- surveys
  @override
  Future<List<Survey>> surveys() {
    final taken = (_s['participation'] as List).cast<String>();
    final list = _list('surveys').map((m) {
      final s = Survey.fromMap(m);
      return Survey.fromMap({
        ...s.toMap(),
        'taken_by_me': taken.contains('${_me.id}|${s.id}'),
        'mine': _me.isSuperAdmin || _can(s.publisherId, 'surveys'),
      });
    }).toList();
    return _tick(list);
  }

  @override
  Future<Survey> createSurvey({
    required String publisherId,
    required String title,
    required String purpose,
    required DateTime closesAt,
    required List<SurveyQuestion> questions,
  }) async {
    if (!_can(publisherId, 'surveys')) throw CommunityException('You cannot run surveys for this office');
    if (purpose.trim().length < 30) throw CommunityException('Explain why you are asking (30+ characters)');
    if (questions.isEmpty) throw CommunityException('Add at least one question');
    if (questions.length > 15) throw CommunityException('At most 15 questions. Short surveys get honest answers.');
    final pub = _list('publishers').firstWhere((p) => p['id'] == publisherId);
    final s = Survey(
      id: _uuid.v4(),
      publisherId: publisherId,
      publisherName: pub['name'],
      publisherKind: pub['kind'],
      title: title.trim(),
      purpose: purpose.trim(),
      closesAt: closesAt,
      questions: [
        for (var i = 0; i < questions.length; i++)
          SurveyQuestion(id: _uuid.v4(), position: i + 1, prompt: questions[i].prompt, kind: questions[i].kind, options: questions[i].options)
      ],
    );
    final list = _list('surveys')..add(s.toMap());
    _put('surveys', list);
    await _save();
    return s;
  }

  @override
  Future<void> submitSurvey(String surveyId, Map<String, dynamic> answers) async {
    final survey = Survey.fromMap(_list('surveys').firstWhere((s) => s['id'] == surveyId));
    if (!survey.isOpen) throw CommunityException('This survey is not open');
    final taken = (_s['participation'] as List).cast<String>().toList();
    final key = '${_me.id}|$surveyId';
    if (taken.contains(key)) throw CommunityException('You already answered this survey');
    taken.add(key); // who took part is kept apart from what they said
    _s['participation'] = taken;
    final rows = _list('answers');
    answers.forEach((qid, v) {
      final values = v is List ? v : [v];
      for (final a in values) {
        if (a == null || a.toString().isEmpty) continue;
        rows.add({'survey_id': surveyId, 'question_id': qid, 'answer': a.toString()});
      }
    });
    _put('answers', rows);
    await _save();
  }

  @override
  Future<List<SurveyResultRow>> surveyResults(String surveyId) async {
    final survey = Survey.fromMap(_list('surveys').firstWhere((s) => s['id'] == surveyId));
    if (!(_me.isSuperAdmin || _can(survey.publisherId, 'surveys'))) throw CommunityException('Not allowed');
    final n = (_s['participation'] as List).where((k) => k.toString().endsWith('|$surveyId')).length;
    if (n < 5) throw CommunityException('Results unlock after 5 responses (so nobody can be singled out)');
    final counts = <String, int>{};
    for (final a in _list('answers').where((a) => a['survey_id'] == surveyId)) {
      final k = '${a['question_id']}\u0000${a['answer']}';
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return _tick(counts.entries.map((e) {
      final parts = e.key.split('\u0000');
      return SurveyResultRow(questionId: parts[0], answer: parts[1], n: e.value);
    }).toList());
  }

  // ------------------------------------------------------------------ tutors
  /// Same maths as the database: Bayesian average anchored at 4.0.
  ({double score, int reviews, int reviewers}) _score(String tutorId) {
    final all = _list('reviews');
    final sumAll = all.fold<num>(0, (a, r) => a + (r['rating'] as num));
    final c = (sumAll + 4.0 * 50) / (all.length + 50);
    final mine = all.where((r) => r['tutor_id'] == tutorId).toList();
    final s = mine.fold<num>(0, (a, r) => a + (r['rating'] as num));
    final score = (c * 5 + s) / (5 + mine.length);
    final reviewers = mine.map((r) => r['student_id']).toSet().length;
    return (score: (score * 100).round() / 100, reviews: mine.length, reviewers: reviewers);
  }

  /// Blue tick rule: 10+ reviews from 5+ students and score 4.2+.
  bool _verified(String tutorId) {
    final s = _score(tutorId);
    return s.reviews >= 10 && s.reviewers >= 5 && s.score >= 4.2;
  }

  TutorCard _card(String id, String name, String? programme, int? year) {
    final p = Map<String, dynamic>.from((_s['tutorProfiles'] as Map)[id] ?? {});
    final sc = _score(id);
    return TutorCard(
      tutorId: id,
      name: name,
      programme: programme,
      year: year,
      verified: _verified(id),
      bio: p['bio'] ?? '',
      contact: p['contact'],
      availability: p['availability'] ?? '',
      modules: _list('tutorModules').where((m) => m['tutor_id'] == id).map(TutorModule.fromMap).toList(),
      score: sc.reviews == 0 ? 0 : sc.score,
      reviews: sc.reviews,
      reviewers: sc.reviewers,
    );
  }

  @override
  Future<List<TutorCard>> tutorCards() {
    final cards = <TutorCard>[
      for (final t in SeedData.tutors) _card(t.id, t.fullName, t.programme, t.yearOfStudy),
    ];
    final me = _user();
    if (me != null && me.isTutor && (_s['tutorProfiles'] as Map).containsKey(me.id)) {
      cards.add(_card(me.id, me.fullName, me.programme, me.yearOfStudy));
    }
    cards.sort((a, b) => b.score.compareTo(a.score));
    return _tick(cards);
  }

  @override
  Future<TutorCard?> myTutorCard() {
    final me = _me;
    if (!(_s['tutorProfiles'] as Map).containsKey(me.id)) return _tick(null);
    return _tick(_card(me.id, me.fullName, me.programme, me.yearOfStudy));
  }

  @override
  Future<void> saveMyTutorProfile({
    required String bio,
    String? contact,
    required String availability,
    required List<TutorModule> modules,
  }) async {
    final me = _me;
    (_s['tutorProfiles'] as Map)[me.id] = {'bio': bio.trim(), 'contact': contact, 'availability': availability.trim()};
    final all = _list('tutorModules')..removeWhere((m) => m['tutor_id'] == me.id);
    for (final m in modules) {
      if (m.priceUgx < 0 || m.priceUgx > 500000) throw CommunityException('Price must be between 0 and 500,000 UGX per hour');
      all.add({...m.toMap(), 'id': _uuid.v4(), 'tutor_id': me.id});
    }
    _put('tutorModules', all);
    await _save();
  }

  @override
  Future<void> requestTutor({required String tutorId, required String courseCode, required String message}) async {
    if (tutorId == _me.id) throw CommunityException('You cannot book yourself');
    final tutor = SeedData.tutors.where((t) => t.id == tutorId).toList();
    final reqs = _list('requests')
      ..add(TutorRequest(
        id: _uuid.v4(),
        studentId: _me.id,
        studentName: _me.fullName,
        tutorId: tutorId,
        tutorName: tutor.isEmpty ? 'Tutor' : tutor.first.fullName,
        courseCode: courseCode,
        message: message.trim(),
        createdAt: DateTime.now(),
      ).toMap());
    _put('requests', reqs);
    await _save();
  }

  @override
  Future<List<TutorRequest>> myTutorRequests() {
    final reviews = _list('reviews');
    final list = _list('requests')
        .where((r) => r['student_id'] == _me.id || r['tutor_id'] == _me.id)
        .map((r) => TutorRequest.fromMap({...r, 'reviewed': reviews.any((v) => v['request_id'] == r['id'])}))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _tick(list);
  }

  Future<void> _transition(String id, String to, {required bool asTutor}) async {
    final reqs = _list('requests');
    final i = reqs.indexWhere((r) => r['id'] == id);
    if (i < 0) return;
    final r = reqs[i];
    final okTutor = asTutor && r['tutor_id'] == _me.id && r['status'] == 'pending' && (to == 'accepted' || to == 'declined');
    final okStudent = !asTutor && r['student_id'] == _me.id && r['status'] == 'accepted' && to == 'completed';
    if (!okTutor && !okStudent) throw CommunityException('That change is not allowed');
    r['status'] = to;
    _put('requests', reqs);
    await _save();
  }

  @override
  Future<void> answerTutorRequest(String id, {required bool accept}) =>
      _transition(id, accept ? 'accepted' : 'declined', asTutor: true);

  /// Only the STUDENT can say the lesson happened.
  @override
  Future<void> confirmLesson(String id) => _transition(id, 'completed', asTutor: false);

  @override
  Future<void> reviewTutor({required String requestId, required int rating, String? comment}) async {
    if (rating < 1 || rating > 5) throw CommunityException('Rating is 1 to 5');
    final r = _list('requests').firstWhere((x) => x['id'] == requestId, orElse: () => {});
    if (r.isEmpty || r['student_id'] != _me.id || r['status'] != 'completed') {
      throw CommunityException('You can review a tutor only after a lesson you confirmed');
    }
    final reviews = _list('reviews');
    if (reviews.any((v) => v['request_id'] == requestId)) throw CommunityException('You already reviewed this lesson');
    reviews.add({
      'request_id': requestId,
      'tutor_id': r['tutor_id'],
      'course_code': r['course_code'],
      'student_id': _me.id,
      'rating': rating,
      'comment': comment,
    });
    _put('reviews', reviews);
    await _save();
  }

  // ---------------------------------------------------------------- pictures
  @override
  Future<String> uploadImage(Uint8List bytes, {required String extension}) async {
    if (bytes.length > 1024 * 1024) throw CommunityException('Pictures must be under 1 MB');
    // Demo mode keeps pictures on the device as a data link (small ones only).
    if (bytes.length > 200 * 1024) {
      throw CommunityException('In demo mode pictures must be under 200 KB. The live app allows 1 MB.');
    }
    final mime = extension.toLowerCase() == 'png' ? 'image/png' : (extension.toLowerCase() == 'webp' ? 'image/webp' : 'image/jpeg');
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  // ---------------------------------------------------------------- policies
  @override
  Future<bool> hasAccepted(String policy, String version) =>
      _tick((_s['acceptances'] as List).contains('${_me.id}|$policy|$version'));

  @override
  Future<void> accept(String policy, String version) async {
    final a = (_s['acceptances'] as List).cast<String>().toList();
    final key = '${_me.id}|$policy|$version';
    if (!a.contains(key)) a.add(key);
    _s['acceptances'] = a;
    await _save();
  }

  // ---------------------------------------------------------------- views
  @override
  Future<void> recordView(String postId) async {
    final v = Map<String, dynamic>.from(_s['views'] as Map? ?? {});
    final who = List<String>.from(v[postId] ?? const []);
    if (!who.contains(_me.id)) who.add(_me.id);
    v[postId] = who;
    _s['views'] = v;
    await _save();
  }

  @override
  Future<int?> viewCount(String postId) async {
    final post = _list('posts').where((p) => p['id'] == postId).firstOrNull;
    final mine = post != null &&
        (post['author_id'] == _me.id ||
            _list('members').any((m) => m['user_id'] == _me.id && m['publisher_id'] == post['publisher_id']));
    if (!mine && !_me.isStaff) return null;
    return _tick(((_s['views'] as Map? ?? {})[postId] as List? ?? const []).length);
  }

  // ---------------------------------------------------------------- avatar
  @override
  Future<String> uploadAvatar(Uint8List bytes) async {
    if (bytes.length > 200 * 1024) throw CommunityException('In demo mode photos must be under 200 KB.');
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }

  // ---------------------------------------------------------------- tutor trust
  @override
  Future<void> reportTutor({required String tutorId, required String reason, required String details}) async {
    if (details.trim().length < 10) throw CommunityException('Please explain in at least 10 characters.');
    final r = _list('tutorReports');
    if (r.any((x) => x['tutor_id'] == tutorId && x['reporter_id'] == _me.id && x['status'] == 'open')) {
      throw CommunityException('You already have an open report about this tutor.');
    }
    r.add({'tutor_id': tutorId, 'reporter_id': _me.id, 'reason': reason, 'details': details, 'status': 'open'});
    _put('tutorReports', r);
    await _save();
  }

  @override
  Future<List<TutorReportRow>> tutorReportSummary() async {
    final r = _list('tutorReports');
    final out = <TutorReportRow>[];
    final byTutor = <String, List<Map<String, dynamic>>>{};
    for (final x in r) {
      byTutor.putIfAbsent(x['tutor_id'], () => []).add(x);
    }
    byTutor.forEach((tid, rows) {
      final name = SeedData.tutors.where((t) => t.id == tid).map((t) => t.fullName).firstOrNull ?? 'Tutor';
      final reasons = <String, int>{};
      for (final x in rows) {
        reasons[x['reason']] = (reasons[x['reason']] ?? 0) + 1;
      }
      reasons.forEach((reason, n) => out.add(TutorReportRow(
            tutorId: tid,
            tutorName: name,
            reason: reason,
            n: n,
            pct: 100 * n / rows.length,
            total: rows.length,
            reporters: rows.map((x) => x['reporter_id']).toSet().length,
            open: rows.where((x) => x['status'] == 'open').length,
          )));
    });
    return _tick(out);
  }

  @override
  Future<void> closeTutorReports(String tutorId, {required bool upheld}) async {
    final r = _list('tutorReports');
    for (final x in r) {
      if (x['tutor_id'] == tutorId && x['status'] == 'open') x['status'] = upheld ? 'upheld' : 'dismissed';
    }
    _put('tutorReports', r);
    await _save();
  }

  // ---------------------------------------------------------------- course units
  @override
  Future<List<String>> myTeachingUnits() => _tick(_list('lecturers')
      .where((l) => l['lecturer_id'] == _me.id)
      .map((l) => l['course_code'] as String)
      .toList());

  @override
  Future<List<CourseNotice>> courseNotices() =>
      _tick(_list('courseNotices').map(CourseNotice.fromMap).toList().reversed.toList());

  @override
  Future<void> sendCourseNotice({
    required List<String> courseCodes,
    required String title,
    required String body,
    String? linkUrl,
    String priority = 'normal',
  }) async {
    final mine = await myTeachingUnits();
    final codes = courseCodes.map((c) => c.toUpperCase().replaceAll(RegExp(r'\s+'), '')).toSet().toList();
    if (!_me.isStaff && codes.any((c) => !mine.contains(c))) {
      throw CommunityException('You can only send notices to units you are assigned to teach.');
    }
    final n = CourseNotice(
      id: _uuid.v4(),
      lecturerId: _me.id,
      lecturerName: _me.fullName,
      courseCodes: codes,
      title: title.trim(),
      body: body.trim(),
      linkUrl: (linkUrl ?? '').trim().isEmpty ? null : linkUrl,
      priority: priority,
      createdAt: DateTime.now(),
    );
    _put('courseNotices', [..._list('courseNotices'), n.toMap()]);
    await _save();
    _notify(AppNotification(
        id: _uuid.v4(),
        kind: 'course',
        title: '${codes.join(', ')}: ${n.title}',
        body: n.body,
        link: '/courses',
        priority: priority,
        createdAt: DateTime.now()));
  }

  @override
  Future<List<CourseLecturer>> courseLecturers() => _tick(_list('lecturers')
      .map((l) => CourseLecturer(courseCode: l['course_code'], lecturerId: l['lecturer_id'], name: l['name'] ?? ''))
      .toList());

  @override
  Future<void> assignLecturer({required String userId, required String courseCode}) async {
    if (!_me.isStaff) throw CommunityException('Only staff can assign lecturers.');
    final code = courseCode.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final name = userId == _me.id ? _me.fullName : (_demoPeople.where((p) => p.id == userId).firstOrNull?.fullName ?? '');
    final l = _list('lecturers')..removeWhere((x) => x['course_code'] == code && x['lecturer_id'] == userId);
    l.add({'course_code': code, 'lecturer_id': userId, 'name': name});
    _put('lecturers', l);
    await _save();
  }

  @override
  Future<void> removeLecturer({required String courseCode, required String lecturerId}) async {
    _put('lecturers',
        _list('lecturers')..removeWhere((x) => x['course_code'] == courseCode && x['lecturer_id'] == lecturerId));
    await _save();
  }

  // ---------------------------------------------------------------- notifications
  final _noteCtrl = StreamController<AppNotification>.broadcast();

  void _notify(AppNotification n) {
    _put('notifications', [..._list('notifications'), n.toMap()..['read_at'] = null]);
    _save();
    _noteCtrl.add(n);
  }

  @override
  Future<List<AppNotification>> notifications() =>
      _tick(_list('notifications').map(AppNotification.fromMap).toList().reversed.toList());

  @override
  Stream<AppNotification> newNotifications() => _noteCtrl.stream;

  @override
  Future<void> markNotificationsRead() async {
    final l = _list('notifications');
    for (final n in l) {
      n['read_at'] ??= DateTime.now().toIso8601String();
    }
    _put('notifications', l);
    await _save();
  }

  @override
  Future<List<PostInsight>> postInsights({int days = 90}) async {
    final out = <PostInsight>[];
    for (final p in _list('posts')) {
      final n = await viewCount(p['id']);
      if (n == null) continue;
      out.add(PostInsight(
        postId: p['id'],
        title: p['title'] ?? '',
        publisherName: p['publisher_name'] ?? '',
        publishedAt: DateTime.tryParse('${p['published_at']}') ?? DateTime.now(),
        views: n,
        views24h: n,
        views7d: n,
        comments: _list('comments').where((c) => c['target_id'] == p['id']).length,
        likes: _list('reactions').where((r) => r['target_id'] == p['id']).length,
      ));
    }
    out.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return _tick(out);
  }

  @override
  Future<void> closeReport(String reportId, {required bool actioned}) async {
    if (!_me.isStaff) throw CommunityException('Only staff can close reports.');
    final r = _list('reports');
    for (final x in r) {
      if (x['id'] == reportId) x['status'] = actioned ? 'actioned' : 'dismissed';
    }
    _put('reports', r);
    await _save();
  }

  // ------------------------------------------------------------ dashboard
  @override
  Future<void> touchActivity() async {
    final days = Map<String, dynamic>.from(_s['activity'] as Map? ?? {});
    final today = DateTime.now().toIso8601String().substring(0, 10);
    days[today] = {...List<String>.from(days[today] ?? const []), _me.id}.toList();
    _s['activity'] = days;
    await _save();
  }

  @override
  Future<AdminOverview> adminOverview() async {
    if (!_me.isStaff) throw CommunityException('Only staff can see the dashboard');
    final days = Map<String, dynamic>.from(_s['activity'] as Map? ?? {});
    final now = DateTime.now();
    final series = [
      for (var i = 13; i >= 0; i--)
        () {
          final d = now.subtract(Duration(days: i)).toIso8601String().substring(0, 10);
          return {'day': d, 'n': (days[d] as List? ?? const []).length};
        }(),
    ];
    final insights = await postInsights(days: 7);
    return _tick(AdminOverview({
      'users_total': 1,
      'users_new_7d': 1,
      'active_today': series.last['n'],
      'active_7d': {
        for (var i = 0; i < 7; i++) ...List<String>.from(days[now.subtract(Duration(days: i)).toIso8601String().substring(0, 10)] ?? const []),
      }.length,
      'daily_active': series,
      'posts_7d': insights.length,
      'views_7d': insights.fold<int>(0, (a, b) => a + b.views),
      'top_posts': [for (final p in insights.take(5)) {'id': p.postId, 'title': p.title, 'views': p.views}],
      'open_reports': _list('reports').where((r) => r['status'] == 'open').length,
      'open_tutor_reports': _list('tutorReports').where((r) => r['status'] == 'open').length,
      'major_requests': _list('events').where((e) => e['major_status'] == 'requested').length,
      'pending_claims': _list('claims').where((c) => c['status'] == 'pending').length,
      'open_help': 0,
      'terms_ending_14d': _list('members').map(Membership.fromMap).where((m) => m.isActive && m.daysLeft <= 14).length,
      'upcoming_events': _list('events').where((e) => DateTime.parse(e['starts_at']).isAfter(now)).length,
    }));
  }

  // ------------------------------------------------------------ RSVP
  @override
  Future<Rsvp?> myRsvp(String eventId) async {
    final r = _list('rsvps').where((x) => x['event_id'] == eventId && x['user_id'] == _me.id);
    return _tick(r.isEmpty ? null : Rsvp.fromMap(r.first));
  }

  @override
  Future<Rsvp> rsvp(String eventId) async {
    final existing = await myRsvp(eventId);
    if (existing != null) return existing;
    final code = _uuid.v4().replaceAll('-', '').substring(0, 6).toUpperCase();
    final row = {'event_id': eventId, 'user_id': _me.id, 'name': _me.fullName, 'code': code, 'checked_in_at': null};
    _put('rsvps', [..._list('rsvps'), row]);
    await _save();
    return Rsvp.fromMap(row);
  }

  @override
  Future<void> cancelRsvp(String eventId) async {
    _put('rsvps', _list('rsvps')..removeWhere((x) => x['event_id'] == eventId && x['user_id'] == _me.id && x['checked_in_at'] == null));
    await _save();
  }

  @override
  Future<Map<String, (int, int)>> rsvpCounts(List<String> eventIds) async {
    final out = <String, (int, int)>{};
    for (final id in eventIds) {
      final r = _list('rsvps').where((x) => x['event_id'] == id).toList();
      if (r.isNotEmpty) out[id] = (r.length, r.where((x) => x['checked_in_at'] != null).length);
    }
    return _tick(out);
  }

  @override
  Future<String> checkIn(String eventId, String code) async {
    final ev = _list('events').where((e) => e['id'] == eventId).firstOrNull;
    if (ev == null || !_can(ev['publisher_id'], 'events')) {
      throw CommunityException('Only the organising office can check people in');
    }
    final r = _list('rsvps');
    final i = r.indexWhere((x) => x['event_id'] == eventId && x['code'] == code.trim().toUpperCase());
    if (i < 0) throw CommunityException('Code not found for this event. Ask them to tap "I\'m going" first.');
    if (r[i]['checked_in_at'] != null) return '${r[i]['name']} was already checked in';
    r[i]['checked_in_at'] = DateTime.now().toIso8601String();
    _put('rsvps', r);
    await _save();
    return '${r[i]['name']} checked in';
  }

  // ------------------------------------------------------------ polls
  @override
  Future<List<PostQuestion>> postQuestions(String postId) async {
    final qs = _list('postQuestions').where((q) => q['post_id'] == postId).toList();
    final answers = _list('postAnswers');
    final post = _list('posts').where((p) => p['id'] == postId).firstOrNull;
    final isAuthor = post?['author_id'] == _me.id;
    return _tick([
      for (final q in qs)
        () {
          final mine = answers.where((a) => a['question_id'] == q['id'] && a['user_id'] == _me.id).firstOrNull;
          final show = mine != null || isAuthor;
          final opts = List<String>.from(q['options']);
          final all = answers.where((a) => a['question_id'] == q['id']).toList();
          return PostQuestion(
            id: q['id'],
            kind: q['kind'],
            prompt: q['prompt'],
            options: opts,
            myAnswer: mine?['option_index'],
            correctIndex: show ? q['correct_index'] : null,
            counts: show ? [for (var i = 0; i < opts.length; i++) all.where((a) => a['option_index'] == i).length] : null,
            total: all.length,
          );
        }(),
    ]);
  }

  @override
  Future<void> answerQuestion(String questionId, int option) async {
    final a = _list('postAnswers');
    if (a.any((x) => x['question_id'] == questionId && x['user_id'] == _me.id)) {
      throw CommunityException('You already answered this one');
    }
    a.add({'question_id': questionId, 'user_id': _me.id, 'option_index': option});
    _put('postAnswers', a);
    await _save();
  }

  @override
  Future<void> addPostQuestions(String postId, List<PostQuestion> questions) async {
    final post = _list('posts').where((p) => p['id'] == postId).firstOrNull;
    if (post == null || post['author_id'] != _me.id) throw CommunityException('Only the author can add questions');
    _put('postQuestions', [
      ..._list('postQuestions'),
      for (final q in questions)
        {
          'id': _uuid.v4(),
          'post_id': postId,
          'kind': q.kind,
          'prompt': q.prompt.trim(),
          'options': q.options,
          'correct_index': q.isQuiz ? q.correctIndex : null,
        }
    ]);
    await _save();
  }
}
