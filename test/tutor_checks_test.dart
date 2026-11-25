import 'dart:typed_data';

import 'package:campuslink/data/community_models.dart';
import 'package:campuslink/data/community_repository.dart';
import 'package:campuslink/data/local_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TutorCard card({bool checked = false, int lessons = 0, int reviews = 0, double score = 0, bool tick = false, int upheld = 0}) =>
    TutorCard(
      tutorId: 't',
      name: 'T',
      verified: tick,
      modules: [TutorModule(id: 'm', courseCode: 'BDA2207', grade: 'A', priceUgx: 0, gradeChecked: checked)],
      lessons: lessons,
      reviews: reviews,
      score: score,
      upheld: upheld,
    );

void main() {
  test('the 4 levels', () {
    expect(card().levelNo, 1);
    expect(card().suggested, isFalse, reason: 'new tutors are search-only');
    expect(card(checked: true).levelNo, 2);
    expect(card(checked: true).suggested, isTrue);
    expect(card(checked: true, lessons: 10, reviews: 3, score: 4.1).levelNo, 3);
    expect(card(checked: true, lessons: 10, reviews: 3, score: 4.1, upheld: 1).levelNo, 2);
    expect(card(lessons: 50, reviews: 20, score: 4.9).levelNo, 1, reason: 'lessons never replace the grade check');
    expect(card(checked: true, tick: true).levelNo, 4);
  });

  test('results slip: self-check blocked, reason needed, approval suggests, grade change removes it', () async {
    SharedPreferences.setMockInitialValues({});
    final r = LocalRepository(await SharedPreferences.getInstance());
    final slip = Uint8List.fromList(List.filled(100, 1));

    await r.signIn(email: 'student@x.ug', password: 'password1');
    final c = r.community;
    final mod = [const TutorModule(id: '', courseCode: 'bda 2207', grade: 'A', priceUgx: 10000)];
    await c.saveMyTutorProfile(bio: 'x' * 50, availability: 'Evenings', modules: mod);
    expect((await c.myTutorCard())!.levelNo, 1);
    await expectLater(c.sendGradeProof(courseCode: 'BDA2207', grade: 'B', bytes: slip, extension: 'jpg'),
        throwsA(isA<CommunityException>()), reason: 'slip must match the grade on the profile');
    await c.sendGradeProof(courseCode: 'BDA2207', grade: 'A', bytes: slip, extension: 'jpg');
    await expectLater(c.sendGradeProof(courseCode: 'BDA2207', grade: 'A', bytes: slip, extension: 'jpg'),
        throwsA(isA<CommunityException>()), reason: 'one waiting slip per unit');
    expect(await c.gradeProofQueue(), isEmpty, reason: 'students cannot check slips');
    final me = r.currentUserSync!.id;
    await r.signOut();

    await r.signIn(email: 'super@x.ug', password: 'password1');
    final q = (await r.community.gradeProofQueue()).where((p) => p.tutorId == me).single;
    await expectLater(r.community.reviewGradeProof(q.id, approve: false, reason: ''), throwsA(isA<CommunityException>()));
    await r.community.reviewGradeProof(q.id, approve: true);
    expect((await r.community.gradeProofQueue()).where((p) => p.tutorId == me), isEmpty);
    await r.signOut();

    await r.signIn(email: 'student@x.ug', password: 'password1');
    var mine = (await r.community.myTutorCard())!;
    expect((mine.levelNo, mine.suggested), (2, true));
    // Saving again with the same grade keeps the check...
    await r.community.saveMyTutorProfile(bio: 'x' * 50, availability: 'Weekends', modules: mod);
    expect((await r.community.myTutorCard())!.levelNo, 2);
    // ...changing the grade removes it.
    await r.community.saveMyTutorProfile(
        bio: 'x' * 50, availability: 'Weekends', modules: [const TutorModule(id: '', courseCode: 'BDA2207', grade: 'A+', priceUgx: 10000)]);
    mine = (await r.community.myTutorCard())!;
    expect(mine.levelNo, 1);
  });
}
