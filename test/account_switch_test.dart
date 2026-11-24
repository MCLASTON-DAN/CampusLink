import 'package:campuslink/data/local_repository.dart';
import 'package:campuslink/data/models.dart';
import 'package:campuslink/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pretends each person has their own timetable, like the live server does.
class _PerPersonRepo extends LocalRepository {
  _PerPersonRepo(super.prefs);
  int loads = 0;
  @override
  Future<List<TimetableEntry>> timetable() async {
    loads++;
    final me = (await currentUser.first)?.id ?? 'nobody';
    return [
      TimetableEntry(id: me, courseCode: me, dayOfWeek: 1, startTime: '08:00', endTime: '10:00'),
    ];
  }
}

void main() {
  test('after switching accounts, the new person never sees the old timetable', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = _PerPersonRepo(await SharedPreferences.getInstance());
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    final keep = c.listen(timetableProvider, (_, __) {});

    await repo.signIn(email: 'alice@x.ug', password: 'password1');
    await c.read(currentUserProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((await c.read(timetableProvider.future)).single.courseCode, contains('alice'));

    await repo.signOut();
    await repo.signIn(email: 'bob@x.ug', password: 'password1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((await c.read(timetableProvider.future)).single.courseCode, contains('bob'));
    keep.close();
  });
}
