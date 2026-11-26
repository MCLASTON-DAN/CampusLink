import 'package:campuslink/data/community_models.dart';
import 'package:campuslink/data/community_repository.dart';
import 'package:campuslink/data/local_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('small numbers never look like 100%', () {
    expect(outcomeConfidence(1, 1), closeTo(0.21, 0.01));
    expect(outcomeConfidence(9, 10), closeTo(0.60, 0.01));
    expect(outcomeConfidence(90, 100), greaterThan(0.82));
    expect(outcomeConfidence(0, 0), 0);
  });

  test('semesters: Jan-Jun is S1, Jul-Dec is S2', () {
    expect(semesterOf(DateTime(2026, 3, 1)), '2026-S1');
    expect(semesterOf(DateTime(2026, 11, 26)), '2026-S2');
  });

  test('only students with a confirmed lesson can report; bands hidden under 5', () async {
    SharedPreferences.setMockInitialValues({});
    final r = LocalRepository(await SharedPreferences.getInstance());
    await r.signIn(email: 'student@x.ug', password: 'password1');
    final tutor = (await r.community.tutorCards()).first;
    final unit = tutor.modules.first.courseCode;
    await expectLater(r.community.reportOutcome(tutorId: tutor.tutorId, courseCode: unit, band: 4),
        throwsA(isA<CommunityException>()), reason: 'no lesson, no report');
    final card = (await r.community.tutorCards()).firstWhere((c) => c.tutorId == tutor.tutorId);
    expect(card.outcomeBands, isNull);
  });
}
