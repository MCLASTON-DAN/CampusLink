import 'package:campuslink/data/local_repository.dart';
import 'package:campuslink/data/models.dart';
import 'package:campuslink/features/timetable/timetable_merge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TimetableEntry t(String id, int day, String s, String e, [String code = 'X']) =>
    TimetableEntry(id: id, courseCode: code, dayOfWeek: day, startTime: s, endTime: e);

void main() {
  test('sending the same complaint twice makes one complaint', () async {
    SharedPreferences.setMockInitialValues({});
    final r = LocalRepository(await SharedPreferences.getInstance());
    await r.signIn(email: 'student@x.ug', password: 'password1');
    final before = (await r.myRequests()).length;
    final req = HelpRequest(
        id: 'one-id', studentId: r.currentUserSync!.id, title: 'Missing marks', description: '',
        createdAt: DateTime.now(), updatedAt: DateTime.now());
    await r.createRequest(req);
    await r.createRequest(req); // double tap / retry
    expect((await r.myRequests()).length, before + 1);

    final office = (await r.offices()).first;
    await r.moveRequest('one-id', office.id, office.name);
    expect((await r.myRequests()).firstWhere((x) => x.id == 'one-id').officeId, office.id);
  });

  test('clashes: overlap clashes, back-to-back does not, other days never', () {
    final c = findClashes([
      t('a', 1, '08:00', '10:00'),
      t('b', 1, '09:00', '11:00'),
      t('c', 1, '10:00', '12:00'), // overlaps b only
      t('d', 1, '12:00', '13:00'), // touches c: fine
      t('e', 2, '09:00', '11:00'), // other day
    ]);
    expect(c['a']!.map((x) => x.id), ['b']);
    expect(c['b']!.map((x) => x.id).toSet(), {'a', 'c'});
    expect(c.containsKey('d'), isFalse);
    expect(c.containsKey('e'), isFalse);
  });

  test('an import repeating a class you have is spotted', () {
    expect(sameClass(t('1', 1, '08:00', '10:00', 'bds101'), t('2', 1, '08:00', '10:00', 'BDS101 ')), isTrue);
    expect(sameClass(t('1', 1, '08:00', '10:00', 'BDS101'), t('2', 2, '08:00', '10:00', 'BDS101')), isFalse);
  });
}
