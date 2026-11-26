import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';

import 'community_repository.dart';
import 'community_supabase.dart';
import 'models.dart';
import 'offline_cache.dart';
import 'repository.dart';
import 'write_once.dart';

/// Live backend. Table/column names match supabase/migrations/0001_*.sql.
class SupabaseRepository implements CampusRepository {
  SupabaseRepository(this._client, {OfflineCache? cache}) : _cache = cache {
    community = SupabaseCommunity(_client, () => _user);
    _client.auth.onAuthStateChange.listen((s) {
      // Token refreshes don't change who is signed in: skip the extra reload.
      if (s.event == AuthChangeEvent.tokenRefreshed && _user != null) return;
      _refreshProfile();
    });
    ready = _firstLoad();
  }

  /// Finishes once we know who is signed in, so the app never flashes the
  /// sign-in page for someone who is already signed in (or just came back
  /// from Google).
  late final Future<void> ready;

  Future<void> _firstLoad() async {
    final fromGoogle = Uri.base.queryParameters.containsKey('code') || Uri.base.fragment.contains('access_token');
    if (fromGoogle && _client.auth.currentSession == null) {
      try {
        await _client.auth.onAuthStateChange.firstWhere((s) => s.session != null).timeout(const Duration(seconds: 8));
      } catch (_) {/* sign-in failed or slow: show the sign-in page */}
    }
    // Seen this person before on this device? Open straight away with the
    // saved profile and refresh it quietly. Otherwise wait (up to 8 s).
    final u = _client.auth.currentUser;
    final saved = u == null ? null : _cache?.load(u.id, 'profile');
    if (u != null && saved != null && saved.$1.isNotEmpty) {
      _user = Profile.fromMap(saved.$1.first);
      _userCtrl.add(_user);
      unawaited(_refreshProfile());
      return;
    }
    try {
      await _refreshProfile().timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  final SupabaseClient _client;
  final OfflineCache? _cache;
  @override
  late final CommunityApi community;
  final _userCtrl = StreamController<Profile?>.broadcast();
  Profile? _user;

  String get _uid => _client.auth.currentUser?.id ?? '';

  /// Every profile column others may read. Student number is left out on purpose.
  static const profileColumns = 'id, full_name, programme, year_of_study, faculty, role, is_tutor, tutor_subjects, '
      'is_buddy_mentor, created_at, tutor_verified, tutor_verified_at, avatar_path, status_text, status_until, '
      'username, username_changed_at';

  Future<String?> _myStudentNumber() async {
    try {
      final r = await _client.rpc('my_private_profile');
      return (r as Map?)?['student_number'] as String?;
    } on PostgrestException {
      // Database not updated to 0023 yet: read it the old way (own row only).
      final r = await _client.from('profiles').select('student_number').eq('id', _uid).maybeSingle();
      return r?['student_number'] as String?;
    }
  }

  /// Start-up fires several sign-in events at once; they share one load
  /// instead of fetching the same profile three times.
  Future<void>? _profileLoading;
  Future<void> _refreshProfile() => _profileLoading ??= _loadProfile().whenComplete(() => _profileLoading = null);

  Future<void> _loadProfile() async {
    final u = _client.auth.currentUser;
    if (u == null) {
      _user = null;
      _userCtrl.add(null);
      return;
    }
    try {
      // Named columns, never select(*): the student number is private (0023)
      // and comes from my_private_profile(), which only returns your own.
      // The three parts load side by side: one wait for the server, not three.
      // Badge and office come from the public view (they are worked out, not stored).
      final parts = await Future.wait<Object?>([
        _client.from('profiles').select(profileColumns).eq('id', u.id).maybeSingle(),
        _myStudentNumber(),
        _client.from('public_profiles').select('badge, office_title, office_name').eq('id', u.id).maybeSingle(),
      ]);
      final row = parts[0] as Map<String, dynamic>?;
      if (row != null) row['student_number'] = parts[1] as String?;
      final pub = parts[2] as Map<String, dynamic>?;
      if (row == null) {
        _user = Profile(id: u.id, fullName: u.userMetadata?['full_name'] ?? u.email ?? '');
      } else {
        final merged = {...row, if (pub != null) ...pub};
        _user = Profile.fromMap(merged);
        await _cache?.save(u.id, 'profile', [Map<String, dynamic>.from(jsonDecode(jsonEncode(merged)) as Map)]);
      }
    } catch (_) {
      // Offline: stay signed in as who we last saw (name, photo, badge), not a blank student.
      final saved = _cache?.load(u.id, 'profile');
      _user ??= saved != null && saved.$1.isNotEmpty
          ? Profile.fromMap(saved.$1.first)
          : Profile(id: u.id, fullName: u.userMetadata?['full_name'] ?? u.email ?? '');
    }
    _userCtrl.add(_user);
  }

  // ---- auth ----
  @override
  Stream<Profile?> get currentUser async* {
    yield _user;
    yield* _userCtrl.stream;
  }

  @override
  Profile? get currentUserSync => _user;

  @override
  Future<Profile> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
    await _refreshProfile();
    return _user!;
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
    // The details travel with the sign-up and the database copies them into
    // the profile (0024). Writing the profile from here failed whenever email
    // confirmation was on, because nobody is signed in until they confirm.
    final res = await _client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      emailRedirectTo: kIsWeb ? '${Uri.base.origin}/' : AppConfig.webUrl,
      data: {
        'full_name': fullName,
        if (studentNumber != null) 'student_number': studentNumber,
        if (programme != null) 'programme': programme,
        if (yearOfStudy != null) 'year_of_study': yearOfStudy,
      },
    );
    if (res.session == null) throw const EmailConfirmationNeeded();
    await _refreshProfile();
    return _user ?? Profile(id: res.user?.id ?? '', fullName: fullName);
  }

  @override
  Future<void> signOut() async {
    _cache?.clear(); // a shared phone must not show your saved data to the next person
    await _client.auth.signOut();
  }

  @override
  Future<void> signInWithGoogle() async {
    final phone = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    if (!phone) {
      // Website: Google opens in this same tab and comes back to it.
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? '${Uri.base.origin}/' : 'ug.ac.cavendish.campuslink://login-callback',
        authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
        // Always show Google's account list, so students can pick their
        // school account instead of a personal Gmail that would be refused.
        queryParams: const {'prompt': 'select_account'},
      );
      return;
    }
    // Phones: open Google in a sign-in sheet that belongs to the app (Custom
    // Tab / Safari view), not the phone's browser. When Google sends us back,
    // the sheet closes, so no leftover browser tabs pile up.
    final res = await _client.auth.getOAuthSignInUrl(
      provider: OAuthProvider.google,
      redirectTo: 'ug.ac.cavendish.campuslink://login-callback',
      queryParams: const {'prompt': 'select_account'},
    );
    _closeSheetOnReturn ??= _client.auth.onAuthStateChange.listen((e) {
      if (e.event == AuthChangeEvent.signedIn) closeInAppWebView().catchError((_) {});
    });
    final ok = await launchUrl(Uri.parse(res.url), mode: LaunchMode.inAppBrowserView);
    if (!ok) await launchUrl(Uri.parse(res.url), mode: LaunchMode.externalApplication);
  }

  StreamSubscription<AuthState>? _closeSheetOnReturn;

  @override
  Future<Profile> updateProfile(Profile p) async {
    try {
      return await _updateProfile(p);
    } on PostgrestException catch (e) {
      // Database rules (username taken/reserved/too soon) come back as readable messages.
      throw Exception(e.message.replaceFirst(RegExp(r'^.*?: '), ''));
    }
  }

  Future<Profile> _updateProfile(Profile p) async {
    // Only the columns a student may edit. Role and the blue tick are protected
    // by the database, and badge/office fields are computed, not stored.
    await _client.from('profiles').update({
      'full_name': p.fullName,
      'student_number': p.studentNumber,
      'programme': p.programme,
      'year_of_study': p.yearOfStudy,
      'faculty': p.faculty,
      'is_tutor': p.isTutor,
      'tutor_subjects': p.tutorSubjects,
      'is_buddy_mentor': p.isBuddyMentor,
      'avatar_path': p.avatarPath,
      if (p.username != null && p.username != _user?.username) 'username': p.username!.trim().toLowerCase().replaceAll('@', ''),
      'status_text': p.statusText,
      'status_until': p.statusUntil?.toUtc().toIso8601String(),
    }).eq('id', p.id);
    await _refreshProfile();
    return _user!;
  }

  // ---- announcements ----
  @override
  Future<List<Announcement>> announcements() async {
    final rows = await _client.from('announcements').select().order('is_pinned', ascending: false).order('created_at', ascending: false);
    return rows.map(Announcement.fromMap).toList();
  }

  @override
  Future<void> postAnnouncement(Announcement a) => writeOnce.run(
      'announcement|${a.title}|${a.body}',
      () => _client.from('announcements').insert(a.toMap()
        ..remove('id')
        ..['author_id'] = _uid));

  // ---- offices ----
  @override
  Future<List<HelpOffice>> offices() async {
    final rows = await _client.from('help_offices').select().order('name');
    return rows.map(HelpOffice.fromMap).toList();
  }

  // ---- requests ----
  @override
  Future<List<HelpRequest>> myRequests() async {
    final rows = await _client.from('help_requests').select().order('updated_at', ascending: false);
    return rows.map(HelpRequest.fromMap).toList();
  }

  @override
  Future<List<RequestUpdate>> requestUpdates(String requestId) async {
    final rows = await _client.from('help_request_updates').select().eq('request_id', requestId).order('created_at');
    return rows.map(RequestUpdate.fromMap).toList();
  }

  @override
  Future<HelpRequest> createRequest(HelpRequest r) async {
    // The form makes one id and reuses it on every tap or retry. The database
    // refuses a second row with that id, so one complaint is always one row.
    // The first "Request submitted." line is added by the database itself
    // (trigger in 0013), in the same step, so nothing can be half-saved.
    Future<Map<String, dynamic>> insert(Map<String, dynamic> m) =>
        _client.from('help_requests').insert(m).select().single();
    final m = r.toMap()
      ..remove('created_at')
      ..remove('updated_at');
    try {
      try {
        return HelpRequest.fromMap(await insert(m));
      } on PostgrestException catch (e) {
        // Database not updated yet (no topic column): send it without the topic.
        if (e.code != 'PGRST204' || !m.containsKey('topic')) rethrow;
        return HelpRequest.fromMap(await insert(m..remove('topic')));
      }
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow; // 23505 = this id is already saved
      final row = await _client.from('help_requests').select().eq('id', r.id).single();
      return HelpRequest.fromMap(row);
    }
  }

  @override
  Future<void> moveRequest(String requestId, String? officeId, String officeName) => writeOnce.run(
      'moveRequest|$requestId|$officeId',
      // One database step that checks who may move it and logs the move.
      () => _client.rpc('move_help_request', params: {'p_request': requestId, 'p_office': officeId}));

  @override
  Future<int> replyToTopic({required String? officeId, required String topic, required String message, RequestStatus? status}) =>
      writeOnce.run('replyToTopic|$officeId|$topic|$message|${status?.name}', () async {
        final n = await _client.rpc('reply_to_topic',
            params: {'p_office': officeId, 'p_topic': topic, 'p_message': message, 'p_status': status?.db});
        return (n as num).toInt();
      });

  @override
  Future<Set<String>> myHandledOffices() async {
    if (_uid.isEmpty) return {};
    try {
      final rows = await _client.from('help_office_staff').select('office_id').eq('user_id', _uid);
      return {for (final r in rows) r['office_id'] as String};
    } on PostgrestException {
      return {}; // database not updated yet (0016)
    }
  }

  @override
  Future<List<({String id, String name})>> officeHandlers(String officeId) async {
    final rows = await _client.from('help_office_staff').select('user_id').eq('office_id', officeId);
    final ids = [for (final r in rows) r['user_id'] as String];
    if (ids.isEmpty) return [];
    final people = await _client.from('public_profiles').select('id, full_name').inFilter('id', ids);
    return [for (final p in people) (id: p['id'] as String, name: (p['full_name'] ?? '') as String)];
  }

  @override
  Future<void> setOfficeHandler(String officeId, String userId, {required bool add}) => writeOnce.run(
      'officeHandler|$officeId|$userId|$add',
      () => _client.rpc('set_office_handler', params: {'p_office': officeId, 'p_user': userId, 'p_add': add}));

  @override
  Future<void> reloadMe() => _refreshProfile();

  @override
  Future<void> addRequestUpdate(RequestUpdate u, {RequestStatus? newStatus}) =>
      writeOnce.run('requestUpdate|${u.requestId}|${u.message}|${newStatus?.name}', () async {
        // Status first: setting the same status twice changes nothing, so if
        // the line below fails and you retry, you never get the line twice.
        if (newStatus != null) {
          await _client.from('help_requests').update({
            'status': newStatus.db,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', u.requestId);
        }
        await _client.from('help_request_updates').insert({
          'request_id': u.requestId,
          'author_id': _uid,
          'message': u.message,
          'new_status': newStatus?.db,
        });
      });

  // ---- study ----
  @override
  Future<List<Profile>> tutors() async {
    final rows = await _client.from('profiles').select(profileColumns).eq('is_tutor', true);
    return rows.map(Profile.fromMap).toList();
  }

  @override
  Future<List<StudyGroup>> studyGroups() async {
    final rows = await _client.from('study_groups').select('*, study_group_members(user_id)');
    return rows.map((m) {
      final members = (m['study_group_members'] as List? ?? const []).map((e) => e['user_id'].toString()).toList();
      return StudyGroup.fromMap({...m, 'member_ids': members});
    }).toList();
  }

  @override
  Future<StudyGroup> createStudyGroup(StudyGroup g) => writeOnce.run('studyGroup|${g.name}|${g.courseCode}', () async {
        final row = await _client
            .from('study_groups')
            .insert(g.toMap()
              ..remove('id')
              ..remove('member_ids')
              ..['owner_id'] = _uid)
            .select()
            .single();
        await _client.from('study_group_members').insert({'group_id': row['id'], 'user_id': _uid});
        return StudyGroup.fromMap({
          ...row,
          'member_ids': [_uid]
        });
      });

  @override
  Future<void> toggleGroupMembership(String groupId, bool join) => writeOnce.run('groupJoin|$groupId|$join', () async {
        if (join) {
          await _client.from('study_group_members').upsert({'group_id': groupId, 'user_id': _uid});
        } else {
          await _client.from('study_group_members').delete().match({'group_id': groupId, 'user_id': _uid});
        }
      }, toggle: true);

  // ---- pulse ----
  String _voterHash(String pollId) => sha256.convert(utf8.encode('$_uid:$pollId')).toString();

  @override
  Future<List<PulsePoll>> polls() async {
    final polls = await _client.from('pulse_polls').select().eq('is_active', true);
    final votes = await _client.from('pulse_votes').select('poll_id, option_index, voter_hash');
    return polls.map((p) {
      final opts = List<String>.from(p['options']);
      final counts = List.filled(opts.length, 0);
      int? mine;
      final myHash = _voterHash(p['id']);
      for (final v in votes.where((v) => v['poll_id'] == p['id'])) {
        final idx = v['option_index'] as int;
        if (idx >= 0 && idx < counts.length) counts[idx]++;
        if (v['voter_hash'] == myHash) mine = idx;
      }
      return PulsePoll.fromMap({...p, 'counts': counts, 'my_vote': mine});
    }).toList();
  }

  @override
  Future<void> vote(String pollId, int optionIndex) => writeOnce.run(
      'pulseVote|$pollId',
      () => _client.from('pulse_votes').upsert({
            'poll_id': pollId,
            'voter_hash': _voterHash(pollId),
            'option_index': optionIndex,
          }));

  // ---- buddy ----
  @override
  Future<BuddyPair?> myBuddyPair() async {
    final row = await _client
        .from('buddy_pairs')
        .select()
        .or('mentee_id.eq.$_uid,mentor_id.eq.$_uid')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : BuddyPair.fromMap(row);
  }

  @override
  Future<BuddyPair> requestBuddy() => writeOnce.run('buddy', () async {
        // Simple matching: pick a mentor with the fewest active mentees.
        final mentorsRows = await _client.from('profiles').select('id').eq('is_buddy_mentor', true);
        final pairs = await _client.from('buddy_pairs').select('mentor_id').eq('status', 'matched');
        String? best;
        var bestLoad = 1 << 30;
        for (final m in mentorsRows) {
          final load = pairs.where((p) => p['mentor_id'] == m['id']).length;
          if (load < bestLoad) {
            bestLoad = load;
            best = m['id'];
          }
        }
        final row = await _client
            .from('buddy_pairs')
            .insert({
              'mentee_id': _uid,
              'mentor_id': best,
              'status': best == null ? 'waiting' : 'matched',
            })
            .select()
            .single();
        return BuddyPair.fromMap(row);
      });

  @override
  Future<List<Profile>> mentors() async {
    final rows = await _client.from('profiles').select(profileColumns).eq('is_buddy_mentor', true);
    return rows.map(Profile.fromMap).toList();
  }

  // ---- engagement ----
  @override
  Future<void> submitFeedback({required String topic, required String message, String? sentiment}) => writeOnce.run(
      'feedback|$topic|$message', () => _client.from('feedback').insert({'topic': topic, 'message': message, 'sentiment': sentiment}));

  @override
  Future<List<CampusEvent>> events() => community.upcomingEvents();

  @override
  Future<List<Club>> clubs() async {
    final rows = await _client.from('clubs').select().order('name');
    return rows.map(Club.fromMap).toList();
  }

  // ---- timetable ----
  @override
  Future<List<TimetableEntry>> timetable() async {
    final rows = await _client.from('timetable_entries').select().order('day_of_week').order('start_time');
    return rows.map(TimetableEntry.fromMap).toList();
  }

  @override
  Future<void> replaceTimetable(List<TimetableEntry> entries) async {
    // Save first, then remove what was dropped. If the network fails half-way
    // you get extra classes, never an empty timetable.
    if (entries.isNotEmpty) {
      await _client.from('timetable_entries').upsert(
            entries.map((e) => e.toMap()..['user_id'] = _uid).toList(),
            onConflict: 'id',
          );
    }
    final keep = entries.map((e) => e.id).toList();
    var del = _client.from('timetable_entries').delete().eq('user_id', _uid);
    if (keep.isNotEmpty) del = del.not('id', 'in', '(${keep.join(',')})');
    await del;
  }

  @override
  Future<void> addTimetableEntry(TimetableEntry e) => writeOnce.run('timetableAdd|${e.dayOfWeek}|${e.startTime}|${e.courseCode}',
      () => _client.from('timetable_entries').insert(e.toMap()..['user_id'] = _uid));

  @override
  Future<void> deleteTimetableEntry(String id) => _client.from('timetable_entries').delete().eq('id', id);

  // ---- exams ----
  @override
  Future<List<ExamEntry>> myExams() async {
    final units = {for (final t in await timetable()) t.courseCode};
    List<ExamEntry> official = [], mine = [];
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      official = [
        for (final r in await _client.from('exam_papers').select().gte('exam_date', today)) ExamEntry.fromMap(r, official: true)
      ];
      mine = [for (final r in await _client.from('my_exams').select().gte('exam_date', today)) ExamEntry.fromMap(r)];
    } on PostgrestException {/* database not updated yet */}
    return mergeMyExams(official: official, mine: mine, myUnits: units);
  }

  @override
  Future<void> addMyExam(ExamEntry e) => writeOnce.run('myExam|${e.courseCode}|${e.date}|${e.start}',
      () => _client.from('my_exams').insert(e.toMap()..['user_id'] = _uid));

  @override
  Future<void> deleteMyExam(String id) => _client.from('my_exams').delete().eq('id', id);

  @override
  Future<List<ExamEntry>> examPapers() async =>
      [for (final r in await _client.from('exam_papers').select().order('exam_date').order('start_time')) ExamEntry.fromMap(r, official: true)];

  @override
  Future<bool> canManageExams() async {
    try {
      return (await _client.rpc('can_manage_exams')) == true;
    } on PostgrestException {
      return false;
    }
  }

  @override
  Future<void> saveExamPaper(ExamEntry e) => writeOnce.run('examPaper|${e.id}|${e.date}|${e.start}|${e.room}', () async {
        try {
          await _client.from('exam_papers').upsert({...e.toMap(), 'course_code': e.courseCode.toUpperCase().replaceAll(RegExp(r'\s+'), ''), 'updated_at': DateTime.now().toUtc().toIso8601String()});
        } on PostgrestException catch (err) {
          throw Exception(err.code == '42501' ? 'Only the Examinations office can change official papers.' : err.message);
        }
      });

  @override
  Future<void> deleteExamPaper(String id) => _client.from('exam_papers').delete().eq('id', id);

  // ---- study group invites and chat ----
  Future<Map<String, Map<String, dynamic>>> _names(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return {};
    final rows = await _client.from('public_profiles').select('id, full_name, username').inFilter('id', list);
    return {for (final r in rows) r['id'] as String: r};
  }

  @override
  Future<void> requestToJoinGroup(String groupId, String? message) => writeOnce.run('joinAsk|$groupId', () async {
        try {
          await _client.from('study_group_requests').insert({'group_id': groupId, 'message': message});
        } on PostgrestException catch (e) {
          if (e.code == '23505') return; // already asked
          rethrow;
        }
      });

  @override
  Future<Set<String>> myPendingGroupRequests() async {
    try {
      final rows = await _client.from('study_group_requests').select('group_id').eq('user_id', _uid).eq('status', 'pending');
      return {for (final r in rows) r['group_id'] as String};
    } on PostgrestException {
      return {};
    }
  }

  @override
  Future<List<GroupJoinRequest>> groupJoinRequests(String groupId) async {
    final rows = await _client.from('study_group_requests').select().eq('group_id', groupId).eq('status', 'pending').order('created_at');
    final names = await _names([for (final r in rows) r['user_id'] as String]);
    return [
      for (final r in rows)
        GroupJoinRequest(
            id: r['id'], groupId: groupId, userId: r['user_id'], userName: names[r['user_id']]?['full_name'] ?? '', message: r['message'])
    ];
  }

  @override
  Future<void> decideGroupRequest(String requestId, {required bool approve}) => writeOnce.run('joinDecide|$requestId',
      () => _client.rpc('decide_group_request', params: {'p_request': requestId, 'p_approve': approve}));

  @override
  Future<void> setGroupPrivacy(String groupId, String privacy) =>
      _client.from('study_groups').update({'privacy': privacy}).eq('id', groupId);

  @override
  Future<List<GroupMember>> groupMembers(String groupId) async {
    final rows = await _client.from('study_group_members').select('user_id').eq('group_id', groupId);
    final names = await _names([for (final r in rows) r['user_id'] as String]);
    return [
      for (final r in rows)
        (id: r['user_id'] as String, name: (names[r['user_id']]?['full_name'] ?? '') as String, username: names[r['user_id']]?['username'] as String?)
    ];
  }

  @override
  Future<List<GroupMessage>> groupMessages(String groupId) async {
    final rows = await _client.from('study_group_messages').select().eq('group_id', groupId).order('created_at', ascending: false).limit(150);
    final names = await _names([for (final r in rows) r['author_id'] as String]);
    return [for (final r in rows.reversed) GroupMessage.fromMap(r, name: names[r['author_id']]?['full_name'] ?? '')];
  }

  @override
  Stream<GroupMessage> groupMessageChanges(String groupId) {
    final ctrl = StreamController<GroupMessage>();
    RealtimeChannel? ch;
    void add(Map<String, dynamic> row) async {
      final n = await _names([row['author_id'] as String]);
      if (!ctrl.isClosed) ctrl.add(GroupMessage.fromMap(row, name: n[row['author_id']]?['full_name'] ?? ''));
    }

    ctrl.onListen = () {
      ch = _client
          .channel('chat-$groupId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'study_group_messages',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'group_id', value: groupId),
            callback: (p) {
              if (p.newRecord.isNotEmpty) add(p.newRecord);
            },
          )
          .subscribe();
    };
    ctrl.onCancel = () async {
      if (ch != null) await _client.removeChannel(ch!);
    };
    return ctrl.stream;
  }

  @override
  Future<void> sendGroupMessage(String groupId, String body, {String? replyTo, List<String> mentions = const [], bool mentionAll = false}) =>
      writeOnce.run('groupMsg|$groupId|$body|$replyTo', () async {
        await _client.from('study_group_messages').insert({
          'group_id': groupId,
          'body': body.trim(),
          'reply_to': replyTo,
          'mentions': mentions,
          'mention_all': mentionAll,
        });
      });

  @override
  Future<void> deleteGroupMessage(String messageId) =>
      _client.from('study_group_messages').update({'deleted': true}).eq('id', messageId);

  @override
  Future<void> pinGroupMessage(String messageId, {required bool pin}) => writeOnce.run('pin|$messageId|$pin',
      () => _client.rpc('pin_group_message', params: {'p_message': messageId, 'p_pin': pin}), toggle: true);

  // Typing: a private channel only members may join (rules in 0020).
  final _typingChannels = <String, RealtimeChannel>{};

  RealtimeChannel _typingChannel(String groupId) => _typingChannels.putIfAbsent(
      groupId, () => _client.channel('group:$groupId', opts: const RealtimeChannelConfig(private: true)));

  @override
  Stream<Set<String>> typingIn(String groupId) {
    final ctrl = StreamController<Set<String>>();
    final seen = <String, DateTime>{};
    Timer? tick;
    void emit() {
      final now = DateTime.now();
      seen.removeWhere((_, t) => now.difference(t).inSeconds > 4);
      if (!ctrl.isClosed) ctrl.add(seen.keys.toSet());
    }

    ctrl.onListen = () {
      final ch = _typingChannel(groupId);
      ch.onBroadcast(
        event: 'typing',
        callback: (p) {
          final name = p['name']?.toString() ?? '';
          if (name.isEmpty || p['id'] == _uid) return;
          seen[name] = DateTime.now();
          emit();
        },
      ).subscribe();
      tick = Timer.periodic(const Duration(seconds: 2), (_) => emit());
    };
    ctrl.onCancel = () async {
      tick?.cancel();
      final ch = _typingChannels.remove(groupId);
      if (ch != null) await _client.removeChannel(ch);
    };
    return ctrl.stream;
  }

  DateTime _lastTyping = DateTime(2000);
  @override
  void sendTyping(String groupId) {
    // At most every 2 seconds, so typing doesn't flood the network.
    if (DateTime.now().difference(_lastTyping).inSeconds < 2) return;
    _lastTyping = DateTime.now();
    _typingChannels[groupId]?.sendBroadcastMessage(event: 'typing', payload: {'id': _uid, 'name': _user?.fullName.split(' ').first ?? ''});
  }

  @override
  Future<void> retractAnnouncement(String id, String reason) => writeOnce.run('retractAnn|$id',
      () => _client.rpc('retract_announcement', params: {'p_id': id, 'p_reason': reason}));
}
