import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'community_models.dart';
import 'community_repository.dart';
import 'models.dart';
import 'write_once.dart';

/// Live backend for the community features. Table, view and function names
/// match supabase/migrations/0002_* and 0003_*. Security is enforced by the
/// database (Row Level Security), this class only asks nicely.
class SupabaseCommunity implements CommunityApi {
  SupabaseCommunity(this._client, this._me);

  final SupabaseClient _client;
  final Profile? Function() _me;
  static const _uuid = Uuid();

  String get _uid => _client.auth.currentUser?.id ?? '';
  List<Publisher>? _publishers;

  // ------------------------------------------------------------- helpers
  /// Turns database errors into short messages a student can act on.
  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      final m = e.message;
      if (m.contains('row-level security') || m.contains('permission denied')) {
        throw CommunityException('You do not have permission to do that.');
      }
      if (m.contains('duplicate key')) throw CommunityException('That already exists.');
      throw CommunityException(m);
    } on StorageException catch (e) {
      throw CommunityException(
          e.message.contains('size') || e.message.contains('large') ? 'That file is too big.' : 'Could not upload the file: ${e.message}');
    } on CommunityException {
      rethrow;
    } catch (e) {
      // No signal, timeouts, server unreachable: never leave a button spinning.
      final t = '$e'.toLowerCase();
      if (t.contains('socket') ||
          t.contains('network') ||
          t.contains('failed host') ||
          t.contains('clientexception') ||
          t.contains('timeout') ||
          t.contains('connection')) {
        throw CommunityException('No internet connection. Check your data or Wi-Fi and try again.');
      }
      throw CommunityException('Something went wrong. Please try again.');
    }
  }

  String? _pubsFor; // which signed-in person the office list was loaded for

  /// Offices by id. Reloaded when the person changes, and whenever a post
  /// names an office we have not seen (e.g. one created after the app opened).
  Future<Map<String, Publisher>> _pubs([Iterable<String> need = const []]) async {
    final stale = _publishers == null || _publishers!.isEmpty || _pubsFor != _uid || need.any((id) => !_publishers!.any((p) => p.id == id));
    if (stale) {
      _publishers = (await _client.from('publishers').select()).map(Publisher.fromMap).toList();
      _pubsFor = _uid;
    }
    return {for (final p in _publishers!) p.id: p};
  }

  /// id -> {full_name, office_title, badge} from the safe public view.
  Future<Map<String, Map<String, dynamic>>> _people(Iterable<String> ids) async {
    final list = ids.where((e) => e.isNotEmpty).toSet().toList();
    if (list.isEmpty) return {};
    final rows =
        await _client.from('public_profiles').select('id, full_name, username, office_title, office_name, badge').inFilter('id', list);
    return {for (final r in rows) r['id'] as String: Map<String, dynamic>.from(r)};
  }

  String _publicUrl(String? path) => path == null || path.isEmpty ? '' : _client.storage.from('campus-media').getPublicUrl(path);

  Future<Map<String, Map<String, int>>> _stats(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return {};
    final rows = await _client.from('content_stats').select().inFilter('target_id', list);
    return {
      for (final r in rows) r['target_id'] as String: {'likes': (r['likes'] as num).toInt(), 'comments': (r['comments'] as num).toInt()}
    };
  }

  Future<Set<String>> _myLikes(String type, Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty || _uid.isEmpty) return {};
    final rows =
        await _client.from('reactions').select('target_id').eq('user_id', _uid).eq('target_type', type).inFilter('target_id', list);
    return rows.map((r) => r['target_id'] as String).toSet();
  }

  /// Every post and event row comes with its own office attached by the
  /// database, so the app never has to look it up or guess.
  static const _office = 'office:publishers!publisher_id(id, kind, name)';
  static const _postSelect = '*, $_office';

  /// Office name and kind for a row: from the row itself. Never guessed.
  static (String?, String?) _officeOf(Map<String, dynamic> r) {
    final o = r['office'];
    if (o is Map) return (o['kind'] as String?, o['name'] as String?);
    return (null, null);
  }

  Future<List<Post>> _postsFrom(List<Map<String, dynamic>> rows) async {
    final people = await _people(rows.map((r) => r['author_id'] as String));
    final stats = await _stats(rows.map((r) => r['id'] as String));
    final liked = await _myLikes('post', rows.map((r) => r['id'] as String));
    return rows.map((r) {
      final (kind, name) = _officeOf(r);
      final id = r['id'] as String;
      return Post.fromMap({
        ...r,
        'publisher_name': name ?? '',
        'publisher_kind': kind,
        'author_name': people[r['author_id']]?['full_name'] ?? '',
        'likes': stats[id]?['likes'] ?? 0,
        'comments': stats[id]?['comments'] ?? 0,
        'liked_by_me': liked.contains(id),
      });
    }).toList();
  }

  Future<List<CampusEvent>> _eventsFrom(List<Map<String, dynamic>> rows) async {
    final stats = await _stats(rows.map((r) => r['id'] as String));
    final liked = await _myLikes('event', rows.map((r) => r['id'] as String));
    return rows.map((r) {
      final (kind, name) = _officeOf(r);
      final id = r['id'] as String;
      final speakers = ((r['event_speakers'] as List?) ?? const [])
          .map((s) => {...Map<String, dynamic>.from(s), 'photo_url': _publicUrl(s['photo_path'])})
          .toList()
        ..sort((a, b) => ((a['position'] ?? 0) as int).compareTo((b['position'] ?? 0) as int));
      return CampusEvent.fromMap({
        ...r,
        'publisher_name': name ?? (r['organiser'] ?? ''),
        'publisher_kind': kind,
        'speakers': speakers,
        'likes': stats[id]?['likes'] ?? 0,
        'comments': stats[id]?['comments'] ?? 0,
        'liked_by_me': liked.contains(id),
      });
    }).toList();
  }

  // ------------------------------------------------------------ identity
  @override
  Future<List<Membership>> myMemberships() => _guard(() async {
        final pubs = await _pubs();
        final rows = await _client.from('publisher_members').select().eq('user_id', _uid);
        return rows
            .map((r) => Membership.fromMap({
                  ...r,
                  'publisher_name': pubs[r['publisher_id']]?.name ?? '',
                  'publisher_kind': pubs[r['publisher_id']]?.kind ?? 'unknown',
                }))
            .toList();
      });

  @override
  Future<List<Publisher>> publishers() => _guard(() async => (await _pubs()).values.toList());

  @override
  Future<List<Membership>> membersOf(String publisherId) => _guard(() async {
        final pubs = await _pubs();
        final rows = await _client.from('publisher_members').select().eq('publisher_id', publisherId).order('expires_at', ascending: false);
        final people = await _people(rows.map((r) => r['user_id'] as String));
        return rows
            .map((r) => Membership.fromMap({
                  ...r,
                  'publisher_name': pubs[r['publisher_id']]?.name ?? '',
                  'publisher_kind': pubs[r['publisher_id']]?.kind ?? 'unknown',
                  'user_name': people[r['user_id']]?['full_name'],
                  'username': people[r['user_id']]?['username'],
                }))
            .toList();
      });

  @override
  Future<List<PersonHit>> searchPeople(String query) => _guard(() async {
        if (query.trim().replaceAll('@', '').length < 2) return <PersonHit>[];
        final rows = await _client.rpc('search_people', params: {'p_query': query}) as List;
        return rows.map((r) => PersonHit.fromMap(Map<String, dynamic>.from(r))).toList();
      });

  @override
  Future<void> appointMember({
    required String publisherId,
    required String userId,
    required String positionTitle,
    required List<String> scopes,
    required DateTime expiresAt,
  }) =>
      writeOnce.run(
          'appoint|$publisherId|$userId',
          () => _guard(() async {
                if (userId == _uid) throw CommunityException('You cannot appoint yourself.');
                await _client.from('publisher_members').insert({
                  'publisher_id': publisherId,
                  'user_id': userId,
                  'position_title': positionTitle.trim(),
                  'scopes': scopes,
                  'expires_at': expiresAt.toUtc().toIso8601String(),
                  'appointed_by': _uid,
                });
              }));

  @override
  Future<void> endTerm(String membershipId, {required String kind, required String reason}) => writeOnce.run(
      'endTerm|$membershipId',
      () => _guard(() => _client.from('publisher_members').update({
            'revoked_at': DateTime.now().toUtc().toIso8601String(),
            'end_kind': kind,
            'end_reason': reason.trim(),
          }).eq('id', membershipId)));

  @override
  Future<void> renewTerm(String membershipId, DateTime newEnd) => writeOnce.run(
      'renewTerm|$membershipId|$newEnd',
      () =>
          _guard(() => _client.from('publisher_members').update({'expires_at': newEnd.toUtc().toIso8601String()}).eq('id', membershipId)));

  @override
  Future<List<Membership>> officeHistory() => _guard(() async {
        final pubs = await _pubs();
        final rows =
            await _client.from('publisher_members').select().not('revoked_at', 'is', null).order('revoked_at', ascending: false).limit(100);
        final people = await _people(rows.map((r) => r['user_id'] as String));
        return rows
            .map((r) => Membership.fromMap({
                  ...r,
                  'publisher_name': pubs[r['publisher_id']]?.name ?? '',
                  'publisher_kind': pubs[r['publisher_id']]?.kind ?? 'unknown',
                  'user_name': people[r['user_id']]?['full_name'],
                  'username': people[r['user_id']]?['username'],
                }))
            .toList();
      });

  // ---------------------------------------------------------------- news
  @override
  Future<List<Post>> posts({String? kind, int limit = 20, DateTime? before}) => _guard(() async {
        var q = _client.from('posts').select(_postSelect).eq('status', 'published');
        if (kind != null) q = q.eq('kind', kind);
        if (before != null) q = q.lt('published_at', before.toUtc().toIso8601String());
        final rows = await q.order('published_at', ascending: false).limit(limit);
        return _postsFrom(List<Map<String, dynamic>>.from(rows));
      });

  @override
  Future<Post?> post(String id) => _guard(() async {
        final row = await _client.from('posts').select(_postSelect).eq('id', id).maybeSingle();
        if (row == null) return null;
        return (await _postsFrom([Map<String, dynamic>.from(row)])).first;
      });

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
  }) =>
      writeOnce.run(
          'post|$publisherId|$title|$body',
          () => _guard(() async {
                final row = await _client
                    .from('posts')
                    .insert({
                      'publisher_id': publisherId,
                      'author_id': _uid,
                      'kind': kind,
                      'title': title.trim(),
                      'body': body.trim(),
                      'source_note': sourceNote.trim(),
                      if (videoUrl != null && videoUrl.isNotEmpty) 'video_url': videoUrl,
                      if (meetingUrl != null && meetingUrl.isNotEmpty) 'meeting_url': meetingUrl,
                      if (coverPath != null && coverPath.isNotEmpty) 'cover_path': coverPath,
                      if (expiresAt != null) 'expires_at': expiresAt.toUtc().toIso8601String(),
                      if (correctsPostId != null) 'corrects_post_id': correctsPostId,
                    })
                    .select(_postSelect)
                    .single();
                return (await _postsFrom([Map<String, dynamic>.from(row)])).first;
              }));

  // ------------------------------------------------ comments, likes, reports
  @override
  Future<List<Comment>> comments(String targetType, String targetId) => _guard(() async {
        final rows = await _client
            .from('comments')
            .select()
            .eq('target_type', targetType)
            .eq('target_id', targetId)
            .eq('status', 'visible')
            .order('created_at')
            .limit(200);
        final people = await _people(rows.map((r) => r['author_id'] as String));
        return rows
            .map((r) => Comment.fromMap({
                  ...r,
                  'author_name': people[r['author_id']]?['full_name'] ?? 'Student',
                  'badge': people[r['author_id']]?['badge'],
                  'office_title': people[r['author_id']]?['office_title'],
                }))
            .toList();
      });

  @override
  Future<void> addComment(String targetType, String targetId, String body, {String? parentId}) =>
      writeOnce.run('comment|$targetType|$targetId|$parentId|$body', () => _guard(() => _client.from('comments').insert({
            'target_type': targetType,
            'target_id': targetId,
            'body': body.trim(),
            if (parentId != null) 'parent_id': parentId,
          })));

  @override
  Future<void> deleteComment(String id) =>
      writeOnce.run('deleteComment|$id', () => _guard(() => _client.from('comments').delete().eq('id', id).eq('author_id', _uid)));

  @override
  Future<Map<String, (int, bool)>> likeCounts(String targetType, List<String> ids) => ids.isEmpty
      ? Future.value(const {})
      : _guard(() async {
          final rows = await _client.rpc('like_counts', params: {'p_type': targetType, 'p_ids': ids}) as List;
          return {
            for (final r in rows.cast<Map>()) '${r['target_id']}': ((r['likes'] as num).toInt(), r['liked'] == true),
          };
        });

  @override
  Future<List<Liker>> likers(String targetType, String targetId) => _guard(() async {
        final rows = await _client.rpc('likers', params: {'p_type': targetType, 'p_id': targetId}) as List;
        return [for (final r in rows) Liker.fromMap(Map<String, dynamic>.from(r as Map))];
      });

  @override
  Future<bool> toggleLike(String targetType, String targetId) => writeOnce.run(
      'like|$targetType|$targetId',
      () => _guard(() async {
            final existing = await _client
                .from('reactions')
                .select('target_id')
                .eq('user_id', _uid)
                .eq('target_type', targetType)
                .eq('target_id', targetId)
                .maybeSingle();
            if (existing != null) {
              await _client.from('reactions').delete().eq('user_id', _uid).eq('target_type', targetType).eq('target_id', targetId);
              return false;
            }
            await _client.from('reactions').insert({'target_type': targetType, 'target_id': targetId});
            return true;
          }),
      toggle: true);

  @override
  Future<void> report(String targetType, String targetId, String reason) => writeOnce.run('report|$targetType|$targetId|$reason',
      () => _guard(() => _client.from('reports').insert({'target_type': targetType, 'target_id': targetId, 'reason': reason.trim()})));

  @override
  Future<List<Report>> openReports() => _guard(() async {
        final rows = await _client.from('reports').select().eq('status', 'open').order('created_at');
        return rows.map(Report.fromMap).toList();
      });

  // ---------------------------------------------------------- moderation
  @override
  Future<void> moderate({
    required String action,
    required String targetType,
    required String targetId,
    required String reason,
  }) =>
      writeOnce.run(
          'moderate|$action|$targetType|$targetId',
          () => _guard(
              () => _client.rpc('moderate', params: {'p_action': action, 'p_type': targetType, 'p_id': targetId, 'p_reason': reason})));

  @override
  Future<List<ModerationEntry>> moderationLog() => _guard(() async {
        final rows = await _client.from('moderation_actions').select().order('created_at', ascending: false).limit(100);
        final people = await _people(rows.map((r) => r['actor_id'] as String));
        return rows.map((r) => ModerationEntry.fromMap({...r, 'actor_name': people[r['actor_id']]?['full_name'] ?? ''})).toList();
      });

  // -------------------------------------------------------------- events
  static const _eventSelect = '*, event_speakers(*), $_office';

  @override
  Future<CampusEvent?> event(String id) => _guard(() async {
        final row = await _client.from('events').select(_eventSelect).eq('id', id).maybeSingle();
        if (row == null) return null;
        return (await _eventsFrom([Map<String, dynamic>.from(row)])).first;
      });

  @override
  Future<List<CampusEvent>> upcomingEvents() => _guard(() async {
        final rows = await _client
            .from('events')
            .select(_eventSelect)
            .eq('status', 'published')
            .gte('starts_at', DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String())
            .order('starts_at')
            .limit(100);
        return _eventsFrom(List<Map<String, dynamic>>.from(rows));
      });

  @override
  Future<List<CampusEvent>> featuredEvents() => _guard(() async {
        final rows = await _client.from('featured_events').select();
        final ids = rows.map((r) => r['id'] as String).toList();
        if (ids.isEmpty) return <CampusEvent>[];
        final full = await _client.from('events').select(_eventSelect).inFilter('id', ids).order('starts_at');
        return _eventsFrom(List<Map<String, dynamic>>.from(full));
      });

  @override
  Future<CampusEvent> createEvent(CampusEvent e) => writeOnce.run(
      'event|${e.publisherId}|${e.title}|${e.startsAt.toIso8601String()}',
      () => _guard(() async {
            final pubs = await _pubs();
            final row = await _client
                .from('events')
                .insert({
                  'title': e.title.trim(),
                  'description': e.description,
                  'starts_at': e.startsAt.toUtc().toIso8601String(),
                  if (e.endsAt != null) 'ends_at': e.endsAt!.toUtc().toIso8601String(),
                  'location': e.location,
                  'organiser': pubs[e.publisherId]?.name,
                  'publisher_id': e.publisherId,
                  'created_by': _uid,
                  'topic': e.topic,
                  'impact': e.impact,
                  if (e.onlineUrl != null && e.onlineUrl!.isNotEmpty) 'online_url': e.onlineUrl,
                  if (e.coverPath != null && e.coverPath!.isNotEmpty) 'cover_path': e.coverPath,
                  'major_status': e.majorStatus == 'requested' ? 'requested' : 'none',
                  if (e.majorStatus == 'requested') 'major_reason': e.majorReason,
                })
                .select('id')
                .single();
            final id = row['id'] as String;
            if (e.speakers.isNotEmpty) {
              await _client.from('event_speakers').insert([
                for (var i = 0; i < e.speakers.length; i++)
                  {
                    'event_id': id,
                    'name': e.speakers[i].name,
                    'title': e.speakers[i].title,
                    'role': e.speakers[i].role,
                    'bio': e.speakers[i].bio,
                    'position': i,
                  }
              ]);
            }
            return (await event(id))!;
          }));

  @override
  Future<void> setMajorStatus(String eventId, String status) => writeOnce.run(
      'major|$eventId|$status',
      () => _guard(() => _client.from('events').update({
            'major_status': status,
            'major_reviewed_by': _uid,
            'major_reviewed_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', eventId)));

  @override
  Future<List<CampusEvent>> majorRequests() => _guard(() async {
        final rows = await _client.from('events').select(_eventSelect).eq('major_status', 'requested').order('starts_at');
        return _eventsFrom(List<Map<String, dynamic>>.from(rows));
      });

  // ------------------------------------------------------ campuses & offices
  @override
  Future<List<Campus>> campuses() => _guard(() async {
        final rows = await _client.from('campuses').select().order('name');
        return rows.map(Campus.fromMap).toList();
      });

  @override
  Future<void> saveCampus(Campus c) => _guard(() => _client.from('campuses').upsert({
        if (c.id.isNotEmpty && !c.id.startsWith('new-')) 'id': c.id,
        'name': c.name,
        'address': c.address,
        'lat': c.lat,
        'lng': c.lng,
        'notes': c.notes,
      }));

  @override
  Future<void> saveOffice(HelpOffice o) => _guard(() => _client.from('help_offices').update({
        'description': o.description,
        'location': o.location,
        'open_hours': o.openHours,
        if (o.topics.isNotEmpty) 'topics': o.topics,
        'what_we_do': o.whatWeDo,
        'what_we_dont': o.whatWeDont,
        'bring': o.bring,
        'hours': o.hours,
        'directions': o.directions,
        'source': o.source,
        'campus_id': o.campusId,
        'lat': o.lat,
        'lng': o.lng,
        // Only the super admin may change this; the database enforces it too.
        if (_me()?.isSuperAdmin ?? false) 'confidential': o.confidential,
      }).eq('id', o.id));

  // ------------------------------------------------------------ lost & found
  @override
  Future<List<LostFoundItem>> lostFound() => _guard(() async {
        final rows = await _client.from('lost_found_items').select().order('created_at', ascending: false).limit(100);
        final mine = await _client.from('lost_found_claims').select('item_id, status').eq('claimant_id', _uid);
        final status = {for (final c in mine) c['item_id'] as String: c['status'] as String};
        return rows
            .map((r) => LostFoundItem.fromMap({
                  ...r,
                  'photo_url': r['photo_path'],
                  'my_claim_status': status[r['id']],
                }))
            .toList();
      });

  @override
  Future<void> addLostFound({
    required String publisherId,
    required String title,
    required String description,
    required String foundWhere,
    required String storedAt,
    String? photoUrl,
  }) =>
      writeOnce.run(
          'lostFound|$publisherId|$title|$description',
          () => _guard(() => _client.from('lost_found_items').insert({
                'publisher_id': publisherId,
                'title': title.trim(),
                'description': description.trim(),
                'found_where': foundWhere.trim(),
                'stored_at': storedAt.trim(),
                'photo_path': photoUrl,
              })));

  @override
  Future<void> setLostFoundStatus(String itemId, String status) => writeOnce.run(
      'lostFoundStatus|$itemId|$status', () => _guard(() => _client.from('lost_found_items').update({'status': status}).eq('id', itemId)));

  @override
  Future<void> claimItem(String itemId, String proof) => writeOnce.run(
      'claim|$itemId', () => _guard(() => _client.from('lost_found_claims').insert({'item_id': itemId, 'proof': proof.trim()})));

  @override
  Future<List<LostFoundClaim>> claimsFor(String itemId) => _guard(() async {
        final rows = await _client.from('lost_found_claims').select().eq('item_id', itemId).order('created_at');
        final people = await _people(rows.map((r) => r['claimant_id'] as String));
        return rows.map((r) => LostFoundClaim.fromMap({...r, 'claimant_name': people[r['claimant_id']]?['full_name'] ?? ''})).toList();
      });

  @override
  Future<void> decideClaim(String claimId, {required bool approve}) => writeOnce.run(
      'decideClaim|$claimId',
      () => _guard(() async {
            final claim = await _client
                .from('lost_found_claims')
                .update({'status': approve ? 'approved' : 'rejected', 'handled_by': _uid})
                .eq('id', claimId)
                .select('item_id')
                .single();
            if (approve) await setLostFoundStatus(claim['item_id'] as String, 'claimed');
          }));

  // ------------------------------------------------------------- surveys
  @override
  Future<List<Survey>> surveys() => _guard(() async {
        final pubs = await _pubs();
        final rows = await _client
            .from('surveys')
            .select('*, survey_questions(*)')
            .inFilter('status', ['open', 'closed']).order('closes_at', ascending: false);
        final done = await _client.from('survey_participation').select('survey_id').eq('user_id', _uid);
        final taken = done.map((r) => r['survey_id'] as String).toSet();
        final me = _me();
        return rows.map((r) {
          final qs = ((r['survey_questions'] as List?) ?? const []).toList()
            ..sort((a, b) => ((a['position'] ?? 0) as int).compareTo((b['position'] ?? 0) as int));
          return Survey.fromMap({
            ...r,
            'publisher_name': pubs[r['publisher_id']]?.name ?? '',
            'publisher_kind': pubs[r['publisher_id']]?.kind ?? 'unknown',
            'questions': qs,
            'taken_by_me': taken.contains(r['id']),
            'mine': r['created_by'] == _uid || (me?.isSuperAdmin ?? false),
          });
        }).toList();
      });

  @override
  Future<Survey> createSurvey({
    required String publisherId,
    required String title,
    required String purpose,
    required DateTime closesAt,
    required List<SurveyQuestion> questions,
  }) =>
      writeOnce.run(
          'survey|$publisherId|$title',
          () => _guard(() async {
                if (questions.isEmpty) throw CommunityException('Add at least one question');
                // Created as a draft, questions added, then opened (the database only
                // accepts questions on drafts so nobody can change a live survey).
                final row = await _client
                    .from('surveys')
                    .insert({
                      'publisher_id': publisherId,
                      'title': title.trim(),
                      'purpose': purpose.trim(),
                      'closes_at': closesAt.toUtc().toIso8601String(),
                      'status': 'draft',
                    })
                    .select('id')
                    .single();
                final id = row['id'] as String;
                for (var i = 0; i < questions.length; i++) {
                  await _client.from('survey_questions').insert({
                    'survey_id': id,
                    'position': i + 1,
                    'prompt': questions[i].prompt,
                    'kind': questions[i].kind,
                    'options': questions[i].options,
                  });
                }
                await _client.from('surveys').update({'status': 'open'}).eq('id', id);
                return (await surveys()).firstWhere((s) => s.id == id);
              }));

  @override
  Future<void> submitSurvey(String surveyId, Map<String, dynamic> answers) => writeOnce.run(
      'surveyAnswer|$surveyId', () => _guard(() => _client.rpc('submit_survey', params: {'p_survey': surveyId, 'p_answers': answers})));

  @override
  Future<List<SurveyResultRow>> surveyResults(String surveyId) => _guard(() async {
        final rows = await _client.rpc('survey_results', params: {'p_survey': surveyId}) as List;
        return rows
            .map((r) => SurveyResultRow(questionId: r['question_id'] as String, answer: r['answer'] as String, n: (r['n'] as num).toInt()))
            .toList();
      });

  // -------------------------------------------------------------- tutors
  @override
  Future<List<TutorCard>> tutorCards() => _guard(() async {
        final people = await _client
            .from('public_profiles')
            .select('id, full_name, username, programme, year_of_study, tutor_verified')
            .eq('is_tutor', true);
        // Tutors under review (3+ open reports) are hidden until staff decide.
        // New tutors are included: the screen shows them only to people who
        // search for them; suggestions show level 2 and up.
        return (await _cards(List<Map<String, dynamic>>.from(people))).where((c) => !c.paused).toList();
      });

  Future<List<TutorCard>> _cards(List<Map<String, dynamic>> people) async {
    final ids = people.map((p) => p['id'] as String).toList();
    if (ids.isEmpty) return [];
    final profiles = await _client.from('tutor_profiles').select().inFilter('tutor_id', ids);
    final modules = await _client.from('tutor_modules').select().inFilter('tutor_id', ids).eq('is_active', true);
    final scores = await _client.from('tutor_scores').select().inFilter('tutor_id', ids);
    List stats;
    try {
      stats = await _client.rpc('tutor_trust') as List; // has upheld reports (0014)
    } on PostgrestException {
      stats = await _client.rpc('tutor_stats') as List; // database not updated yet
    }
    var outcomes = const <dynamic>[];
    try {
      outcomes = await _client.rpc('tutor_outcome_bands') as List; // 0018
    } on PostgrestException {/* database not updated yet: no results shown */}
    final outById = {for (final o in outcomes) o['tutor_id']: o};
    // Which tutors have contact details (icons only, never the numbers).
    var hints = const <dynamic>[];
    try {
      hints = await _client.rpc('tutor_contact_summary', params: {'p_tutors': ids}) as List;
    } on PostgrestException {/* database not updated yet */}
    final hById = {for (final h in hints) h['tutor_id'] as String: h};
    final stById = {for (final s in stats) s['tutor_id'] as String: s};
    final pById = {for (final p in profiles) p['tutor_id'] as String: p};
    final sById = {for (final s in scores) s['tutor_id'] as String: s};
    final cards = people.map((p) {
      final id = p['id'] as String;
      final pr = pById[id];
      final sc = sById[id];
      return TutorCard(
        tutorId: id,
        name: p['full_name'] ?? '',
        username: p['username'],
        programme: p['programme'],
        year: p['year_of_study'],
        verified: p['tutor_verified'] ?? false,
        bio: pr?['bio'] ?? '',
        // The old public WhatsApp field is no longer shown: numbers are private now.
        contact: null,
        rateUgx: (pr?['rate_ugx'] as num?)?.toInt(),
        rateUnit: '${pr?['rate_unit'] ?? 'hour'}',
        negotiable: pr?['price_negotiable'] == true,
        firstSessionFree: pr?['first_session_free'] == true,
        mode: '${pr?['teaching_mode'] ?? 'both'}',
        hasContact: hById[id]?['has_phone'] == true || hById[id]?['has_email'] == true,
        hasWhatsapp: hById[id]?['has_whatsapp'] == true,
        availability: pr?['availability'] ?? '',
        modules: modules.where((m) => m['tutor_id'] == id).map(TutorModule.fromMap).toList(),
        score: ((sc?['score'] ?? 0) as num).toDouble(),
        reviews: ((sc?['reviews'] ?? 0) as num).toInt(),
        reviewers: ((sc?['reviewers'] ?? 0) as num).toInt(),
        lessons: ((stById[id]?['lessons'] ?? 0) as num).toInt(),
        paused: stById[id]?['paused'] == true,
        upheld: ((stById[id]?['upheld'] ?? 0) as num).toInt(),
        outcomeReports: ((outById[id]?['reports'] ?? 0) as num).toInt(),
        outcomeBands: (outById[id]?['bands'] as List?)?.map((e) => (e as num).toInt()).toList(),
        outcomeConfidence: ((outById[id]?['confidence'] ?? 0) as num).toDouble(),
      );
    }).toList()
      // Higher level first, then the fair score.
      ..sort((a, b) => a.levelNo != b.levelNo ? b.levelNo.compareTo(a.levelNo) : b.score.compareTo(a.score));
    return cards;
  }

  @override
  Future<TutorCard?> myTutorCard() => _guard(() async {
        final p = await _client
            .from('public_profiles')
            .select('id, full_name, username, programme, year_of_study, tutor_verified')
            .eq('id', _uid)
            .maybeSingle();
        if (p == null) return null;
        final cards = await _cards([Map<String, dynamic>.from(p)]);
        return cards.isEmpty ? null : cards.first;
      });

  @override
  Future<void> saveMyTutorProfile({
    required String bio,
    String? contact,
    required String availability,
    required List<TutorModule> modules,
  }) =>
      _guard(() async {
        await _client.from('profiles').update({'is_tutor': true}).eq('id', _uid);
        await _client.from('tutor_profiles').upsert({
          'tutor_id': _uid,
          'bio': bio.trim(),
          // Phone and email live in the private tutor_contacts table now
          // (Me → Price and contact). Clear any number left in the old public field.
          'contact_whatsapp': null,
          'availability': availability.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
        // Update units in place (a checked grade stays checked unless its grade
        // changes), add new ones, THEN remove dropped ones. A failure half-way
        // never wipes a tutor's units or their checks.
        final codes = {for (final m in modules) normCode(m.courseCode)};
        if (modules.isNotEmpty) {
          await _client.from('tutor_modules').upsert([
            for (final m in modules)
              {
                'tutor_id': _uid,
                'course_code': normCode(m.courseCode),
                'course_name': m.courseName,
                'grade_achieved': m.grade?.trim(),
                'price_ugx': m.priceUgx,
                'is_active': true,
              }
          ], onConflict: 'tutor_id,course_code');
        }
        final existing = await _client.from('tutor_modules').select('id, course_code').eq('tutor_id', _uid);
        final drop = [
          for (final r in existing)
            if (!codes.contains(r['course_code'] as String)) r['id'] as String
        ];
        if (drop.isNotEmpty) await _client.from('tutor_modules').delete().inFilter('id', drop);
      });

  @override
  Future<void> requestTutor({required String tutorId, required String courseCode, required String message}) => writeOnce.run(
      'tutorRequest|$tutorId|$courseCode|$message',
      () =>
          _guard(() => _client.from('tutor_requests').insert({'tutor_id': tutorId, 'course_code': courseCode, 'message': message.trim()})));

  @override
  Future<List<TutorRequest>> myTutorRequests() => _guard(() async {
        final rows = await _client.from('tutor_requests').select().order('created_at', ascending: false);
        final people = await _people([
          ...rows.map((r) => r['student_id'] as String),
          ...rows.map((r) => r['tutor_id'] as String),
        ]);
        final reviewed =
            (await _client.from('tutor_reviews').select('request_id').eq('student_id', _uid)).map((r) => r['request_id'] as String).toSet();
        return rows
            .map((r) => TutorRequest.fromMap({
                  ...r,
                  'student_name': people[r['student_id']]?['full_name'] ?? '',
                  'tutor_name': people[r['tutor_id']]?['full_name'] ?? '',
                  'reviewed': reviewed.contains(r['id']),
                }))
            .toList();
      });

  @override
  Future<void> answerTutorRequest(String id, {required bool accept}) => writeOnce.run('tutorAnswer|$id',
      () => _guard(() => _client.from('tutor_requests').update({'status': accept ? 'accepted' : 'declined'}).eq('id', id)));

  @override
  Future<void> confirmLesson(String id) =>
      writeOnce.run('confirmLesson|$id', () => _guard(() => _client.from('tutor_requests').update({'status': 'completed'}).eq('id', id)));

  @override
  Future<void> reviewTutor({required String requestId, required int rating, String? comment}) => writeOnce.run(
      'tutorReview|$requestId',
      () => _guard(() async {
            final r = await _client.from('tutor_requests').select('tutor_id, course_code').eq('id', requestId).single();
            await _client.from('tutor_reviews').insert({
              'request_id': requestId,
              'tutor_id': r['tutor_id'],
              'course_code': r['course_code'],
              'rating': rating,
              if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
            });
          }));

  // ------------------------------------------------------------- pictures
  /// Every upload gets a new random name and is never changed afterwards, so
  /// phones and browsers may keep pictures for a year instead of re-checking
  /// with the server (in Ireland) every hour.
  static const _oneYear = '31536000';

  @override
  Future<String> uploadImage(Uint8List bytes, {required String extension}) => _guard(() async {
        if (bytes.length > 1024 * 1024) throw CommunityException('Pictures must be under 1 MB');
        final ext = extension.toLowerCase().replaceAll('.', '');
        final mime = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
        final path = '$_uid/${_uuid.v4()}.${ext == 'jpg' ? 'jpeg' : ext}';
        try {
          await _client.storage.from('campus-media').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime, upsert: false, cacheControl: _oneYear));
        } on StorageException catch (e) {
          throw CommunityException(
              e.message.contains('security') || e.statusCode == '403' ? 'Only office holders can upload pictures.' : e.message);
        }
        return _client.storage.from('campus-media').getPublicUrl(path);
      });

  // ------------------------------------------------------------- policies
  @override
  Future<bool> hasAccepted(String policy, String version) => _guard(() async {
        final r = await _client
            .from('policy_acceptances')
            .select('policy')
            .eq('user_id', _uid)
            .eq('policy', policy)
            .eq('version', version)
            .maybeSingle();
        return r != null;
      });

  @override
  Future<void> accept(String policy, String version) =>
      _guard(() => _client.from('policy_acceptances').upsert({'user_id': _uid, 'policy': policy, 'version': version}));

  // ------------------------------------------------------------- post views
  @override
  Future<void> recordView(String postId) async {
    try {
      await _client.rpc('record_post_view', params: {'p_post': postId});
    } catch (_) {/* counting must never break reading */}
  }

  @override
  Future<int?> viewCount(String postId) => _guard(() async {
        final n = await _client.rpc('post_view_count', params: {'p_post': postId});
        return n == null ? null : (n as num).toInt();
      });

  // ------------------------------------------------------------- avatar
  @override
  Future<String> uploadAvatar(Uint8List bytes) => _guard(() async {
        if (bytes.length > 300 * 1024) throw CommunityException('Profile photos must be under 300 KB');
        final path = '$_uid/${_uuid.v4()}.jpeg';
        await _client.storage
            .from('avatars')
            .uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false, cacheControl: _oneYear));
        return _client.storage.from('avatars').getPublicUrl(path);
      });

  // ------------------------------------------------------------- tutor trust
  @override
  Future<void> reportTutor({required String tutorId, required String reason, required String details}) => writeOnce.run(
      'tutorReport|$tutorId|$reason',
      () => _guard(() async {
            try {
              await _client.from('tutor_reports').insert({'tutor_id': tutorId, 'reason': reason, 'details': details.trim()});
            } on PostgrestException catch (e) {
              if (e.code == '42501') {
                throw CommunityException('You can only report a tutor you have had a lesson with.');
              }
              if (e.code == '23505') throw CommunityException('You already have an open report about this tutor.');
              rethrow;
            }
          }));

  @override
  Future<List<TutorReportRow>> tutorReportSummary() => _guard(() async {
        final rows = await _client.rpc('tutor_report_summary') as List;
        return rows.map((r) => TutorReportRow.fromMap(Map<String, dynamic>.from(r))).toList();
      });

  @override
  Future<void> closeTutorReports(String tutorId, {required bool upheld}) => writeOnce.run(
      'closeTutorReports|$tutorId',
      () => _guard(() => _client
          .from('tutor_reports')
          .update({
            'status': upheld ? 'upheld' : 'dismissed',
            'handled_by': _uid,
            'handled_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('tutor_id', tutorId)
          .eq('status', 'open')));

  // ------------------------------------------------------------- course units
  @override
  Future<List<String>> myTeachingUnits() => _guard(() async {
        final rows = await _client.from('course_lecturers').select('course_code').eq('lecturer_id', _uid);
        return rows.map((r) => r['course_code'] as String).toList()..sort();
      });

  @override
  Future<List<CourseNotice>> courseNotices() => _guard(() async {
        final rows = await _client.from('course_notices').select().order('created_at', ascending: false).limit(100);
        final ids = rows.map((r) => r['lecturer_id'] as String).toSet().toList();
        final names = ids.isEmpty ? <dynamic>[] : await _client.from('public_profiles').select('id, full_name').inFilter('id', ids);
        final byId = {for (final n in names) n['id'] as String: n['full_name'] as String? ?? ''};
        return rows.map((r) => CourseNotice.fromMap({...r, 'lecturer_name': byId[r['lecturer_id']] ?? ''})).toList();
      });

  @override
  Future<void> sendCourseNotice({
    required List<String> courseCodes,
    required String title,
    required String body,
    String? linkUrl,
    String priority = 'normal',
  }) =>
      writeOnce.run(
          'courseNotice|${courseCodes.join(',')}|$title|$body',
          () => _guard(() async {
                try {
                  await _client.from('course_notices').insert({
                    'course_codes': courseCodes,
                    'title': title.trim(),
                    'body': body.trim(),
                    'link_url': (linkUrl ?? '').trim().isEmpty ? null : linkUrl!.trim(),
                    'priority': priority,
                  });
                } on PostgrestException catch (e) {
                  if (e.code == '42501') {
                    throw CommunityException('You can only send notices to units you are assigned to teach.');
                  }
                  rethrow;
                }
              }));

  @override
  Future<List<CourseLecturer>> courseLecturers() => _guard(() async {
        final rows = await _client.from('course_lecturers').select().order('course_code');
        final ids = rows.map((r) => r['lecturer_id'] as String).toSet().toList();
        final names = ids.isEmpty ? <dynamic>[] : await _client.from('public_profiles').select('id, full_name').inFilter('id', ids);
        final byId = {for (final n in names) n['id'] as String: n['full_name'] as String? ?? ''};
        return rows
            .map((r) => CourseLecturer(courseCode: r['course_code'], lecturerId: r['lecturer_id'], name: byId[r['lecturer_id']] ?? ''))
            .toList();
      });

  @override
  Future<void> assignLecturer({required String userId, required String courseCode}) => writeOnce.run(
      'assignLecturer|$userId|$courseCode',
      () => _guard(() => _client.from('course_lecturers').upsert(
          {'course_code': courseCode.toUpperCase().replaceAll(RegExp(r'\s+'), ''), 'lecturer_id': userId},
          ignoreDuplicates: true)));

  @override
  Future<void> removeLecturer({required String courseCode, required String lecturerId}) =>
      _guard(() => _client.from('course_lecturers').delete().eq('course_code', courseCode).eq('lecturer_id', lecturerId));

  // ------------------------------------------------------------- notifications
  @override
  Future<List<AppNotification>> notifications() => _guard(() async {
        final rows = await _client.from('notifications').select().eq('user_id', _uid).order('created_at', ascending: false).limit(60);
        return rows.map(AppNotification.fromMap).toList();
      });

  @override
  Stream<AppNotification> newNotifications() {
    final ctrl = StreamController<AppNotification>();
    RealtimeChannel? ch;
    ctrl.onListen = () {
      ch = _client
          .channel('notes-$_uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: _uid),
            callback: (p) => ctrl.add(AppNotification.fromMap(p.newRecord)),
          )
          .subscribe();
    };
    ctrl.onCancel = () async {
      if (ch != null) await _client.removeChannel(ch!);
    };
    return ctrl.stream;
  }

  @override
  Future<void> markNotificationsRead() => _guard(() => _client
      .from('notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('user_id', _uid)
      .isFilter('read_at', null));

  @override
  Future<List<PostInsight>> postInsights({int days = 90}) => _guard(() async {
        final rows = await _client.rpc('post_insights', params: {'p_days': days}) as List;
        return rows.map((r) => PostInsight.fromMap(Map<String, dynamic>.from(r))).toList();
      });

  @override
  Future<void> closeReport(String reportId, {required bool actioned}) => writeOnce.run(
      'closeReport|$reportId',
      () => _guard(() => _client.from('reports').update({
            'status': actioned ? 'actioned' : 'dismissed',
            'handled_by': _uid,
            'handled_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', reportId)));

  // ------------------------------------------------------------ dashboard
  @override
  Future<void> touchActivity() async {
    try {
      await _client.rpc('touch_activity');
    } catch (_) {/* counting must never get in the way */}
  }

  @override
  Future<AdminOverview> adminOverview() => _guard(() async {
        final m = await _client.rpc('admin_overview');
        return AdminOverview(Map<String, dynamic>.from(m as Map));
      });

  // ------------------------------------------------------------ RSVP
  @override
  Future<Rsvp?> myRsvp(String eventId) => _guard(() async {
        final r = await _client.from('event_rsvps').select().eq('event_id', eventId).eq('user_id', _uid).maybeSingle();
        return r == null ? null : Rsvp.fromMap(r);
      });

  @override
  Future<Rsvp> rsvp(String eventId) => writeOnce.run(
      'rsvp|$eventId',
      () => _guard(() async {
            final r = await _client.from('event_rsvps').insert({'event_id': eventId}).select().single();
            return Rsvp.fromMap(r);
          }));

  @override
  Future<void> cancelRsvp(String eventId) => writeOnce.run(
      'cancelRsvp|$eventId', () => _guard(() => _client.from('event_rsvps').delete().eq('event_id', eventId).eq('user_id', _uid)),
      toggle: true);

  @override
  Future<Map<String, (int, int)>> rsvpCounts(List<String> eventIds) => _guard(() async {
        if (eventIds.isEmpty) return <String, (int, int)>{};
        final rows = await _client.rpc('event_rsvp_counts', params: {'p_events': eventIds}) as List;
        return {
          for (final r in rows) r['event_id'] as String: ((r['going'] as num).toInt(), (r['checked_in'] as num).toInt()),
        };
      });

  @override
  Future<String> checkIn(String eventId, String code) => writeOnce.run('checkIn|$eventId|${code.toUpperCase()}',
      () => _guard(() async => '${await _client.rpc('event_check_in', params: {'p_event': eventId, 'p_code': code})}'));

  // ------------------------------------------------------------ polls
  @override
  Future<List<PostQuestion>> postQuestions(String postId) => _guard(() async {
        final rows = await _client.rpc('post_questions_for', params: {'p_post': postId}) as List;
        return rows.map((r) => PostQuestion.fromMap(Map<String, dynamic>.from(r))).toList();
      });

  @override
  Future<void> answerQuestion(String questionId, int option) => writeOnce.run('answer|$questionId',
      () => _guard(() => _client.rpc('answer_post_question', params: {'p_question': questionId, 'p_option': option})));

  // ---------------------------------------------------------- edits and retractions
  @override
  Future<void> updatePost(String id, {required String title, required String body}) => writeOnce.run('editPost|$id|$title|$body',
      () => _guard(() => _client.from('posts').update({'title': title.trim(), 'body': body.trim()}).eq('id', id)));

  @override
  Future<void> retractPost(String id, String reason) =>
      writeOnce.run('retractPost|$id', () => _guard(() => _client.rpc('retract_post', params: {'p_post': id, 'p_reason': reason})));

  @override
  Future<void> updateEvent(CampusEvent e) => writeOnce.run(
      'editEvent|${e.id}|${e.title}|${e.startsAt}|${e.location}|${e.description}',
      () => _guard(() => _client.from('events').update({
            'title': e.title.trim(),
            'description': e.description.trim(),
            'starts_at': e.startsAt.toUtc().toIso8601String(),
            'ends_at': e.endsAt?.toUtc().toIso8601String(),
            'location': e.location,
            'online_url': e.onlineUrl,
          }).eq('id', e.id)));

  @override
  Future<void> cancelEvent(String id, String reason) =>
      writeOnce.run('cancelEvent|$id', () => _guard(() => _client.rpc('cancel_event', params: {'p_event': id, 'p_reason': reason})));

  // ---------------------------------------------------------- tutor results
  @override
  Future<Map<String, int>> myOutcomes() => _guard(() async {
        final rows = await _client.from('tutor_outcomes').select('tutor_id, course_code, band')
            .eq('student_id', _uid).eq('semester', semesterOf(DateTime.now()));
        return {for (final r in rows) '${r['tutor_id']}|${r['course_code']}': (r['band'] as num).toInt()};
      });

  @override
  Future<void> reportOutcome({required String tutorId, required String courseCode, required int band}) =>
      writeOnce.run('outcome|$tutorId|$courseCode|$band', () => _guard(() => _client.from('tutor_outcomes').upsert({
            'student_id': _uid,
            'tutor_id': tutorId,
            'course_code': normCode(courseCode),
            'semester': semesterOf(DateTime.now()),
            'band': band,
          }, onConflict: 'student_id,tutor_id,course_code,semester')));

  @override
  Future<void> askProgress(String requestId) =>
      writeOnce.run('askProgress|$requestId', () => _guard(() => _client.rpc('ask_student_progress', params: {'p_request': requestId})));

  @override
  Future<DateTime?> semesterEnd() => _guard(() async {
        final r = await _client.from('app_settings').select('value').eq('key', 'semester_end').maybeSingle();
        return r == null ? null : DateTime.tryParse(r['value'] as String);
      });

  @override
  Future<void> setSemesterEnd(DateTime d) => _guard(() => _client.from('app_settings').upsert(
      {'key': 'semester_end', 'value': d.toIso8601String().substring(0, 10), 'updated_at': DateTime.now().toUtc().toIso8601String()}));

  // ---------------------------------------------------------- grade checks
  @override
  Future<List<GradeProof>> myGradeProofs() => _guard(() async {
        final rows = await _client.from('tutor_grade_proofs').select().eq('tutor_id', _uid).order('created_at', ascending: false);
        return [for (final r in rows) GradeProof.fromMap(r)];
      });

  @override
  Future<void> sendGradeProof({required String courseCode, required String grade, required Uint8List bytes, required String extension}) =>
      writeOnce.run(
          'gradeProof|${normCode(courseCode)}|${bytes.length}',
          () => _guard(() async {
                if (bytes.length > 5 * 1024 * 1024) throw CommunityException('The file must be under 5 MB.');
                final ext = extension.toLowerCase().replaceAll('.', '');
                final mime = switch (ext) {
                  'pdf' => 'application/pdf',
                  'png' => 'image/png',
                  'webp' => 'image/webp',
                  'jpg' || 'jpeg' => 'image/jpeg',
                  _ => throw CommunityException('Send a photo (JPG/PNG) or a PDF of your results.'),
                };
                final code = normCode(courseCode);
                final path = '$_uid/$code/${_uuid.v4()}.${ext == 'jpg' ? 'jpeg' : ext}';
                await _client.storage.from('grade-proofs').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
                try {
                  await _client.from('tutor_grade_proofs').insert({'course_code': code, 'grade_claimed': grade.trim(), 'file_path': path});
                } catch (e) {
                  // Don't leave a private file lying around if the record failed.
                  await _client.storage.from('grade-proofs').remove([path]).catchError((_) => <FileObject>[]);
                  if (e is PostgrestException && e.code == '23505') {
                    throw CommunityException('You already sent a slip for $code. Wait for it to be checked.');
                  }
                  rethrow;
                }
              }));

  @override
  Future<List<GradeProof>> gradeProofQueue() => _guard(() async {
        final rows = await _client.from('tutor_grade_proofs').select().eq('status', 'pending').neq('tutor_id', _uid).order('created_at');
        final people = await _people([for (final r in rows) r['tutor_id'] as String]);
        return [for (final r in rows) GradeProof.fromMap(r, name: people[r['tutor_id']]?['full_name'] ?? '')];
      });

  @override
  Future<String> gradeProofLink(String filePath) => _guard(() => _client.storage.from('grade-proofs').createSignedUrl(filePath, 600));

  @override
  Future<void> reviewGradeProof(String proofId, {required bool approve, String? reason}) => writeOnce.run(
      'reviewGradeProof|$proofId',
      () => _guard(() async {
            final path =
                await _client.rpc('review_grade_proof', params: {'p_proof': proofId, 'p_approve': approve, 'p_reason': reason}) as String?;
            // We don't keep results slips after the decision.
            if (path != null) {
              await _client.storage.from('grade-proofs').remove([path]).catchError((_) => <FileObject>[]);
            }
          }));

  @override
  Future<void> addPostQuestions(String postId, List<PostQuestion> questions) => writeOnce.run(
      'postQuestions|$postId',
      () => _guard(() async {
            if (questions.isEmpty) return;
            if (questions.length > 5) throw CommunityException('At most 5 questions per post');
            final bad = questions.map((q) => q.problem).whereType<String>().firstOrNull;
            if (bad != null) throw CommunityException(bad);
            await _client.from('post_questions').insert([
              for (var i = 0; i < questions.length; i++)
                {
                  'post_id': postId,
                  'position': i,
                  'kind': questions[i].kind,
                  'prompt': questions[i].prompt.trim(),
                  'options': questions[i].options.map((o) => o.trim()).toList(),
                  'correct_index': questions[i].isQuiz ? questions[i].correctIndex : null,
                }
            ]);
          }));
}
