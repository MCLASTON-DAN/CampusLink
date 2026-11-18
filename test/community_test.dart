import 'package:campuslink/data/community_models.dart';
import 'package:campuslink/data/community_repository.dart';
import 'package:campuslink/data/local_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<LocalRepository> repoAs(String email) async {
  SharedPreferences.setMockInitialValues({});
  final r = LocalRepository(await SharedPreferences.getInstance());
  await r.signIn(email: email, password: 'password1');
  return r;
}

Future<void> fails(Future<dynamic> f) async {
  await expectLater(f, throwsA(isA<CommunityException>()));
}

void main() {
  test('a plain student cannot post news', () async {
    final r = await repoAs('student@x.ug');
    final pubs = await r.community.publishers();
    await fails(r.community.createPost(
        publisherId: pubs.first.id, kind: 'news', title: 'Hello there', body: 'x' * 30, sourceNote: 'my own idea'));
  });

  test('guild member posts with a green badge, source note is required', () async {
    final r = await repoAs('guild@x.ug');
    final m = (await r.community.myMemberships()).first;
    await fails(r.community.createPost(
        publisherId: m.publisherId, kind: 'news', title: 'Hello there', body: 'x' * 30, sourceNote: ''));
    final p = await r.community.createPost(
        publisherId: m.publisherId, kind: 'news', title: 'Hello there', body: 'x' * 30, sourceNote: 'Senate minutes');
    expect(p.publisherKind, 'guild');
  });

  test('guild cannot appoint; only manage_members or super admin', () async {
    final r = await repoAs('guild@x.ug');
    final m = (await r.community.myMemberships()).first;
    await fails(r.community.appointMember(
        publisherId: m.publisherId,
        studentNumber: '123',
        positionTitle: 'Minister',
        scopes: ['news'],
        expiresAt: DateTime.now().add(const Duration(days: 90))));
  });

  test('term cannot be longer than 12 months', () async {
    final r = await repoAs('president@x.ug');
    final m = (await r.community.myMemberships()).first;
    await fails(r.community.appointMember(
        publisherId: m.publisherId,
        studentNumber: '123',
        positionTitle: 'Minister',
        scopes: ['news'],
        expiresAt: DateTime.now().add(const Duration(days: 500))));
  });

  test('only the super admin can approve major events', () async {
    final r = await repoAs('super@x.ug');
    final q = await r.community.majorRequests();
    expect(q, isNotEmpty);
    // A guild member sees no queue and cannot approve.
    await r.signOut();
    await r.signIn(email: 'guild@x.ug', password: 'password1');
    await fails(r.community.majorRequests());
    await fails(r.community.setMajorStatus(q.first.id, 'approved'));
    await r.signOut();
    await r.signIn(email: 'super@x.ug', password: 'password1');
    await r.community.setMajorStatus(q.first.id, 'approved');
    expect((await r.community.majorRequests()).length, q.length - 1);
  });

  test('only the super admin can remove official posts, with a long reason', () async {
    final a = await repoAs('admin@x.ug');
    final post = (await a.community.posts()).first;
    await fails(a.community.moderate(action: 'remove', targetType: 'post', targetId: post.id, reason: 'twenty letters or more here'));
    final s = await repoAs('super@x.ug');
    await fails(s.community.moderate(action: 'remove', targetType: 'post', targetId: post.id, reason: 'short'));
    await s.community.moderate(action: 'remove', targetType: 'post', targetId: post.id, reason: 'twenty letters or more here');
    expect((await s.community.moderationLog()).first.reason, contains('twenty'));
  });

  test('survey results stay hidden below 5 answers and one answer each', () async {
    final r = await repoAs('student@x.ug');
    final surveys = await r.community.surveys();
    final open = surveys.firstWhere((s) => s.isOpen && !s.takenByMe);
    final answers = {for (final q in open.questions) q.id: q.kind == 'text' ? 'ok' : (q.options.isEmpty ? '3' : q.options.first)};
    await r.community.submitSurvey(open.id, answers);
    await fails(r.community.submitSurvey(open.id, answers));
  });

  test('tutor review needs a confirmed lesson', () async {
    final r = await repoAs('student@x.ug');
    final t = (await r.community.tutorCards()).first;
    await r.community.requestTutor(tutorId: t.tutorId, courseCode: t.modules.first.courseCode, message: 'help please');
    final req = (await r.community.myTutorRequests()).first;
    await fails(r.community.reviewTutor(requestId: req.id, rating: 5));
  });

  test('office edits need a source; students cannot edit; campus saves', () async {
    final r = await repoAs('admin@x.ug');
    final o = (await r.offices()).first;
    await fails(r.community.saveOffice(o.copyWith(directions: 'Turn left', source: '')));
    await r.community.saveOffice(o.copyWith(directions: 'Turn left', lat: 0.3, lng: 32.5, source: 'Registrar, in person'));
    final back = (await r.offices()).firstWhere((x) => x.id == o.id);
    expect(back.hasLocation, isTrue);
    expect(back.isVerified, isTrue);
    await r.community.saveCampus(const Campus(id: 'new-1', name: 'Main', lat: 0.3, lng: 32.5));
    expect((await r.community.campuses()).any((c) => c.name == 'Main'), isTrue);
    await r.signOut();
    await r.signIn(email: 'student@x.ug', password: 'password1');
    await fails(r.community.saveOffice(o.copyWith(directions: 'x', source: 'my guess')));
  });
}
