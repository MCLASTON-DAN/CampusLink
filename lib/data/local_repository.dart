import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'community_local.dart';
import 'access.dart';
import 'models.dart';
import 'repository.dart';
import 'seed_data.dart';

/// Demo / offline backend. Everything lives in SharedPreferences as JSON, so
/// the app works with zero setup (and on GitHub Pages) and data survives reload.
class LocalRepository implements CampusRepository {
  LocalRepository(this._prefs) {
    _load();
    community = LocalCommunity(_prefs, () => _user);
  }

  @override
  late final LocalCommunity community;

  final SharedPreferences _prefs;
  static const _uuid = Uuid();
  static const _k = 'campuslink.store.v1';

  final _userCtrl = StreamController<Profile?>.broadcast();
  Profile? _user;

  // In-memory tables
  late List<Announcement> _announcements;
  late List<HelpRequest> _requests;
  late List<RequestUpdate> _updates;
  late List<StudyGroup> _groups;
  late List<PulsePoll> _polls;
  late List<TimetableEntry> _timetable;
  BuddyPair? _buddy;
  final List<Map<String, dynamic>> _feedback = [];

  void _load() {
    final raw = _prefs.getString(_k);
    if (raw == null) {
      _announcements = List.of(SeedData.announcements);
      _requests = [];
      _updates = [];
      _groups = List.of(SeedData.studyGroups);
      _polls = List.of(SeedData.polls);
      _timetable = List.of(SeedData.timetable);
      return;
    }
    final m = jsonDecode(raw) as Map<String, dynamic>;
    List<T> read<T>(String key, T Function(Map<String, dynamic>) f) =>
        (m[key] as List? ?? const []).map((e) => f(Map<String, dynamic>.from(e))).toList();
    _user = m['user'] == null ? null : Profile.fromMap(Map<String, dynamic>.from(m['user']));
    _announcements = read('announcements', Announcement.fromMap);
    _requests = read('requests', HelpRequest.fromMap);
    _updates = read('updates', RequestUpdate.fromMap);
    _groups = read('groups', StudyGroup.fromMap);
    _polls = read('polls', PulsePoll.fromMap);
    _timetable = read('timetable', TimetableEntry.fromMap);
    _buddy = m['buddy'] == null ? null : BuddyPair.fromMap(Map<String, dynamic>.from(m['buddy']));
    if (_announcements.isEmpty) _announcements = List.of(SeedData.announcements);
    if (_polls.isEmpty) _polls = List.of(SeedData.polls);
  }

  Future<void> _save() async {
    await _prefs.setString(
      _k,
      jsonEncode({
        'user': _user?.toMap(),
        'announcements': _announcements.map((e) => e.toMap()).toList(),
        'requests': _requests.map((e) => e.toMap()).toList(),
        'updates': _updates.map((e) => e.toMap()).toList(),
        'groups': _groups.map((e) => e.toMap()).toList(),
        'polls': _polls.map((e) => e.toMap()).toList(),
        'timetable': _timetable.map((e) => e.toMap()).toList(),
        'buddy': _buddy?.toMap(),
      }),
    );
  }

  Future<T> _tick<T>(T value) =>
      Future.delayed(const Duration(milliseconds: 120), () => value);

  // ---- auth ----
  @override
  Stream<Profile?> get currentUser async* {
    yield _user;
    yield* _userCtrl.stream;
  }

  @override
  Profile? get currentUserSync => _user;

  void _setUser(Profile? p) {
    _user = p;
    _userCtrl.add(p);
    _save();
  }

  @override
  Future<Profile> signIn({required String email, required String password}) async {
    // Demo: any email works. A staff address switches on staff tools.
    final isStaff = email.toLowerCase().contains('staff') || email.toLowerCase().contains('admin');
    final p = Profile(
      id: 'local-${email.toLowerCase()}',
      fullName: _user?.fullName.isNotEmpty == true ? _user!.fullName : email.split('@').first,
      studentNumber: _user?.studentNumber,
      programme: _user?.programme ?? 'BDSAI',
      yearOfStudy: _user?.yearOfStudy ?? 2,
      faculty: 'FST',
      role: isStaff ? UserRole.staff : UserRole.student,
      username: _user?.username ?? email.split('@').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._]'), '.'),
    );
    final withRole = community.onSignIn(p, email);
    _setUser(withRole);
    return _tick(withRole);
  }

  @override
  Future<Profile> signUp({
    required String email,
    required String password,
    required String fullName,
    String? studentNumber,
    String? programme,
    int? yearOfStudy,
  }) async {
    final p = Profile(
      id: 'local-${email.toLowerCase()}',
      fullName: fullName,
      studentNumber: studentNumber,
      programme: programme,
      yearOfStudy: yearOfStudy,
      faculty: 'FST',
      username: fullName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '.'),
    );
    _setUser(p);
    return _tick(p);
  }

  @override
  Future<void> signOut() async => _setUser(null);

  @override
  Future<void> signInWithGoogle() async =>
      throw Exception('Google sign-in works only when the app is connected to the live database.');

  @override
  Future<Profile> updateProfile(Profile p) async {
    _setUser(p);
    return _tick(p);
  }

  // ---- announcements ----
  @override
  Future<List<Announcement>> announcements() {
    final list = List.of(_announcements)
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    return _tick(list);
  }

  @override
  Future<void> postAnnouncement(Announcement a) async {
    _announcements.insert(0, a);
    await _save();
  }

  // ---- offices ----
  @override
  Future<List<HelpOffice>> offices() => _tick(community.mergeOffices(SeedData.offices));

  // ---- requests ----
  @override
  Future<List<HelpRequest>> myRequests() {
    // Same rule as the database (0016), via access.dart.
    final mine = _handled();
    final list = _requests
        .where((r) => canSeeRequest(me: _user, r: r, myOffices: mine, confidential: _confidential(r.officeId)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return _tick(list);
  }

  // Demo office handlers: office id -> user ids.
  final _officeStaff = <String, Set<String>>{};
  Set<String> _handled() => {for (final e in _officeStaff.entries) if (e.value.contains(_user?.id)) e.key};
  bool _confidential(String? officeId) =>
      officeId != null && (community.mergeOffices(SeedData.offices).where((o) => o.id == officeId).firstOrNull?.confidential ?? false);

  @override
  Future<int> replyToTopic({required String? officeId, required String topic, required String message, RequestStatus? status}) async {
    if (!canHandleRequest(me: _user, officeId: officeId, myOffices: _handled(), confidential: _confidential(officeId))) {
      throw Exception('You do not handle this office.');
    }
    var n = 0;
    for (var i = 0; i < _requests.length; i++) {
      final r = _requests[i];
      if (r.officeId != officeId || r.topic != topic) continue;
      if (r.status != RequestStatus.open && r.status != RequestStatus.inProgress) continue;
      _requests[i] = r.copyWith(status: status ?? r.status, updatedAt: DateTime.now());
      _updates.add(RequestUpdate(
          id: _uuid.v4(), requestId: r.id, authorId: _user?.id, message: message.trim(), newStatus: status?.db, createdAt: DateTime.now()));
      n++;
    }
    return n;
  }

  @override
  Future<Set<String>> myHandledOffices() => _tick(_handled());

  @override
  Future<List<({String id, String name})>> officeHandlers(String officeId) => _tick([
        for (final id in _officeStaff[officeId] ?? const <String>{})
          (id: id, name: id.replaceFirst('local-', '').split('@').first)
      ]);

  @override
  Future<void> setOfficeHandler(String officeId, String userId, {required bool add}) async {
    if (_user?.isSuperAdmin != true) throw Exception('Only the super admin chooses who handles an office.');
    final set = _officeStaff.putIfAbsent(officeId, () => <String>{});
    add ? set.add(userId) : set.remove(userId);
  }

  @override
  Future<void> reloadMe() async {}

  @override
  Future<List<RequestUpdate>> requestUpdates(String requestId) =>
      _tick(_updates.where((u) => u.requestId == requestId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));

  @override
  Future<void> moveRequest(String requestId, String? officeId, String officeName) async {
    final i = _requests.indexWhere((x) => x.id == requestId);
    if (i < 0) return;
    final o = _requests[i];
    final asOffice = canHandleRequest(me: _user, officeId: o.officeId, myOffices: _handled(), confidential: _confidential(o.officeId));
    final asStudent = o.studentId == _user?.id && (o.status == RequestStatus.open || o.status == RequestStatus.inProgress);
    if (!asOffice && !asStudent) throw Exception('You cannot move this request.');
    _requests[i] = HelpRequest(
        id: o.id, studentId: o.studentId, officeId: officeId, title: o.title, description: o.description,
        priority: o.priority, status: o.status, createdAt: o.createdAt, updatedAt: DateTime.now());
    _updates.add(RequestUpdate(
        id: _uuid.v4(), requestId: requestId, authorId: _user?.id, message: 'Sent to $officeName.', createdAt: DateTime.now()));
  }


  @override
  Future<HelpRequest> createRequest(HelpRequest r) async {
    // Same id sent twice (double tap, retry) = the same complaint, not a new one.
    final existing = _requests.where((x) => x.id == r.id).firstOrNull;
    if (existing != null) return existing;
    _requests.add(r);
    _updates.add(RequestUpdate(
      id: _uuid.v4(),
      requestId: r.id,
      authorId: r.studentId,
      message: 'Request submitted.',
      newStatus: 'open',
      createdAt: r.createdAt,
    ));
    // Demo magic: auto-acknowledge after a moment so students see status change.
    Future.delayed(const Duration(seconds: 4), () {
      final i = _requests.indexWhere((x) => x.id == r.id);
      if (i < 0 || _requests[i].status != RequestStatus.open) return;
      _requests[i] = _requests[i].copyWith(status: RequestStatus.inProgress, updatedAt: DateTime.now());
      _updates.add(RequestUpdate(
        id: _uuid.v4(),
        requestId: r.id,
        message: 'Your request has been received and assigned to an officer.',
        newStatus: 'in_progress',
        createdAt: DateTime.now(),
      ));
      _save();
    });
    await _save();
    return r;
  }

  @override
  Future<void> addRequestUpdate(RequestUpdate u, {RequestStatus? newStatus}) async {
    _updates.add(u);
    if (newStatus != null) {
      final i = _requests.indexWhere((x) => x.id == u.requestId);
      if (i >= 0) _requests[i] = _requests[i].copyWith(status: newStatus, updatedAt: DateTime.now());
    }
    await _save();
  }

  // ---- study ----
  @override
  Future<List<Profile>> tutors() => _tick(SeedData.tutors);

  @override
  Future<List<StudyGroup>> studyGroups() => _tick(List.of(_groups));

  @override
  Future<StudyGroup> createStudyGroup(StudyGroup g) async {
    _groups.insert(0, g);
    await _save();
    return g;
  }

  @override
  Future<void> toggleGroupMembership(String groupId, bool join) async {
    final uid = _user?.id;
    if (uid == null) return;
    final i = _groups.indexWhere((g) => g.id == groupId);
    if (i < 0) return;
    final members = List.of(_groups[i].memberIds);
    if (join && _groups[i].inviteOnly && _groups[i].ownerId != uid) {
      throw Exception('This group is invite-only. Ask to join instead.');
    }
    if (join && !members.contains(uid) && members.length >= _groups[i].maxMembers) throw Exception('This group is full.');
    join ? (members.contains(uid) ? null : members.add(uid)) : members.remove(uid);
    _groups[i] = _groups[i].copyWith(memberIds: members);
    await _save();
  }

  // ---- pulse ----
  @override
  Future<List<PulsePoll>> polls() => _tick(List.of(_polls));

  @override
  Future<void> vote(String pollId, int optionIndex) async {
    final i = _polls.indexWhere((p) => p.id == pollId);
    if (i < 0 || _polls[i].myVote != null) return;
    final counts = List.of(_polls[i].counts);
    counts[optionIndex] += 1;
    _polls[i] = _polls[i].copyWith(counts: counts, myVote: optionIndex);
    await _save();
  }

  // ---- buddy ----
  @override
  Future<BuddyPair?> myBuddyPair() => _tick(_buddy);

  @override
  Future<BuddyPair> requestBuddy() async {
    final mentor = SeedData.tutors.firstWhere((t) => t.isBuddyMentor);
    _buddy = BuddyPair(
      id: _uuid.v4(),
      menteeId: _user?.id ?? 'anon',
      mentorId: mentor.id,
      status: 'matched',
      createdAt: DateTime.now(),
    );
    await _save();
    return _buddy!;
  }

  @override
  Future<List<Profile>> mentors() => _tick(SeedData.tutors.where((t) => t.isBuddyMentor).toList());

  // ---- engagement ----
  @override
  Future<void> submitFeedback({required String topic, required String message, String? sentiment}) async {
    _feedback.add({'topic': topic, 'message': message, 'sentiment': sentiment});
    await _tick(null);
  }

  @override
  Future<List<CampusEvent>> events() => community.upcomingEvents();

  @override
  Future<List<Club>> clubs() => _tick(SeedData.clubs);

  // ---- timetable ----
  @override
  Future<List<TimetableEntry>> timetable() => _tick(List.of(_timetable)
    ..sort((a, b) => a.dayOfWeek != b.dayOfWeek
        ? a.dayOfWeek.compareTo(b.dayOfWeek)
        : a.startTime.compareTo(b.startTime)));

  @override
  Future<void> replaceTimetable(List<TimetableEntry> entries) async {
    _timetable = List.of(entries);
    await _save();
  }

  @override
  Future<void> addTimetableEntry(TimetableEntry e) async {
    _timetable.add(e);
    await _save();
  }

  @override
  Future<void> deleteTimetableEntry(String id) async {
    _timetable.removeWhere((e) => e.id == id);
    await _save();
  }

  // ---- exams (demo) ----
  final _papers = <ExamEntry>[];
  final _mine = <ExamEntry>[];

  @override
  Future<List<ExamEntry>> myExams() => _tick(mergeMyExams(
      official: _papers, mine: _mine, myUnits: {for (final t in _timetable) t.courseCode}));

  @override
  Future<void> addMyExam(ExamEntry e) async => _mine.add(e);

  @override
  Future<void> deleteMyExam(String id) async => _mine.removeWhere((e) => e.id == id);

  @override
  Future<List<ExamEntry>> examPapers() => _tick([..._papers]..sort((a, b) => a.startsAt.compareTo(b.startsAt)));

  @override
  Future<bool> canManageExams() async => _user?.isSuperAdmin ?? false;

  @override
  Future<void> saveExamPaper(ExamEntry e) async {
    if (!(_user?.isSuperAdmin ?? false)) throw Exception('Only the Examinations office can change official papers.');
    _papers
      ..removeWhere((x) => x.id == e.id)
      ..add(ExamEntry.fromMap(e.toMap(), official: true));
  }

  @override
  Future<void> deleteExamPaper(String id) async => _papers.removeWhere((e) => e.id == id);

  // ---- study group invites and chat (demo, in memory) ----
  final _joinAsks = <GroupJoinRequest>[];
  final _msgs = <GroupMessage>[];
  final _msgCtrl = StreamController<GroupMessage>.broadcast();
  StudyGroup? _group(String id) => _groups.where((g) => g.id == id).firstOrNull;
  bool _member(String groupId) => _group(groupId)?.memberIds.contains(_user?.id) ?? false;

  @override
  Future<void> requestToJoinGroup(String groupId, String? message) async {
    if (_member(groupId)) return;
    if (_joinAsks.any((r) => r.groupId == groupId && r.userId == _user?.id)) return;
    _joinAsks.add(GroupJoinRequest(id: _uuid.v4(), groupId: groupId, userId: _user!.id, userName: _user!.fullName, message: message));
  }

  @override
  Future<Set<String>> myPendingGroupRequests() async => {for (final r in _joinAsks) if (r.userId == _user?.id) r.groupId};

  @override
  Future<List<GroupJoinRequest>> groupJoinRequests(String groupId) async =>
      _group(groupId)?.ownerId == _user?.id ? _joinAsks.where((r) => r.groupId == groupId).toList() : [];

  @override
  Future<void> decideGroupRequest(String requestId, {required bool approve}) async {
    final r = _joinAsks.where((x) => x.id == requestId).firstOrNull;
    if (r == null) throw Exception('That request was already handled.');
    final i = _groups.indexWhere((g) => g.id == r.groupId);
    if (_groups[i].ownerId != _user?.id) throw Exception('Only the group owner decides.');
    if (approve) _groups[i] = _groups[i].copyWith(memberIds: [..._groups[i].memberIds, r.userId]);
    _joinAsks.remove(r);
  }

  @override
  Future<void> setGroupPrivacy(String groupId, String privacy) async {
    final i = _groups.indexWhere((g) => g.id == groupId);
    if (i < 0 || _groups[i].ownerId != _user?.id) throw Exception('Only the group owner can change this.');
    _groups[i] = StudyGroup.fromMap({..._groups[i].toMap(), 'privacy': privacy});
  }

  @override
  Future<List<GroupMember>> groupMembers(String groupId) async => [
        for (final id in _group(groupId)?.memberIds ?? const <String>[])
          (id: id, name: id == _user?.id ? _user!.fullName : id.replaceFirst('local-', '').split('@').first, username: null)
      ];

  @override
  Future<List<GroupMessage>> groupMessages(String groupId) async {
    if (!_member(groupId)) throw Exception('Only members can read this chat.');
    return _msgs.where((m) => m.groupId == groupId).toList();
  }

  @override
  Stream<GroupMessage> groupMessageChanges(String groupId) => _msgCtrl.stream.where((m) => m.groupId == groupId);

  @override
  Future<void> sendGroupMessage(String groupId, String body, {String? replyTo, List<String> mentions = const [], bool mentionAll = false}) async {
    if (!_member(groupId)) throw Exception('Only members can write here.');
    final m = GroupMessage(
        id: _uuid.v4(), groupId: groupId, authorId: _user!.id, authorName: _user!.fullName, body: body.trim(),
        replyTo: replyTo, mentions: mentions, mentionAll: mentionAll, createdAt: DateTime.now());
    _msgs.add(m);
    _msgCtrl.add(m);
  }

  void _replace(String id, GroupMessage Function(GroupMessage) f) {
    final i = _msgs.indexWhere((m) => m.id == id);
    if (i < 0) return;
    _msgs[i] = f(_msgs[i]);
    _msgCtrl.add(_msgs[i]);
  }

  @override
  Future<void> deleteGroupMessage(String messageId) async => _replace(messageId, (m) {
        if (m.authorId != _user?.id) throw Exception('You can only delete your own messages.');
        return m.copyWith(deleted: true, reactions: const {});
      });

  @override
  Future<void> pinGroupMessage(String messageId, {required bool pin}) async {
    final m = _msgs.where((x) => x.id == messageId).firstOrNull;
    if (m == null) return;
    if (_group(m.groupId)?.ownerId != _user?.id) throw Exception('Only the group owner pins messages.');
    if (pin && _msgs.where((x) => x.groupId == m.groupId && x.pinned).length >= 3) throw Exception('Up to 3 pinned messages. Unpin one first.');
    _replace(messageId, (x) => x.copyWith(pinned: pin));
  }

  @override
  Future<Map<String, String>> reactToMessage(String messageId, String emoji) async {
    final m = _msgs.where((x) => x.id == messageId).firstOrNull;
    if (m == null || m.deleted) throw Exception('That message is gone.');
    if (!_member(m.groupId)) throw Exception('Only members can react.');
    final me = _user!.id;
    final next = Map<String, String>.of(m.reactions);
    next[me] == emoji ? next.remove(me) : next[me] = emoji;
    _replace(messageId, (x) => x.copyWith(reactions: next));
    return next;
  }

  @override
  Stream<Set<String>> typingIn(String groupId) => const Stream.empty();

  @override
  void sendTyping(String groupId) {}

  @override
  Future<void> retractAnnouncement(String id, String reason) async {
    if (reason.trim().length < 10) throw Exception('Say what was wrong (at least 10 letters).');
    if (!(_user?.isSuperAdmin ?? false)) throw Exception('Only the author or the super admin can retract this.');
  }
}
