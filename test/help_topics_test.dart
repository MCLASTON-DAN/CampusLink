import 'package:campuslink/data/local_repository.dart';
import 'package:campuslink/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

HelpRequest req(String id, String student, String office, String topic) => HelpRequest(
    id: id, studentId: student, officeId: office, title: topic, description: '', topic: topic,
    createdAt: DateTime.now(), updatedAt: DateTime.now());

void main() {
  test('one reply answers every open request on a topic; confidential stays private', () async {
    SharedPreferences.setMockInitialValues({});
    final r = LocalRepository(await SharedPreferences.getInstance());

    await r.signIn(email: 'amina@x.ug', password: 'password1');
    final amina = r.currentUserSync!.id;
    await r.createRequest(req('q1', amina, 'off-exams', 'Missing marks'));
    await r.createRequest(req('q3', amina, 'off-wellness', 'Personal matter'));
    await r.signOut();
    await r.signIn(email: 'brian@x.ug', password: 'password1');
    await r.createRequest(req('q2', r.currentUserSync!.id, 'off-exams', 'Missing marks'));
    expect((await r.myRequests()).map((x) => x.id), ['q2'], reason: 'students see only their own');
    await r.signOut();

    await r.signIn(email: 'newsroom-reporter@x.ug', password: 'password1');
    expect(await r.myRequests(), isEmpty, reason: 'office members of other bodies see nothing');
    await r.signOut();

    await r.signIn(email: 'super@x.ug', password: 'password1');
    expect(r.currentUserSync!.isSuperAdmin, isTrue);
    final seen = (await r.myRequests()).map((x) => x.id).toSet();
    expect(seen.containsAll({'q1', 'q2'}), isTrue);
    expect(seen.contains('q3'), isFalse, reason: 'counselling is confidential, even for the super admin');
    final n = await r.replyToTopic(
        officeId: 'off-exams', topic: 'Missing marks', message: 'Marks are now uploaded.', status: RequestStatus.resolved);
    expect(n, 2);
    expect((await r.myRequests()).where((x) => x.topic == 'Missing marks').every((x) => x.status == RequestStatus.resolved), isTrue);
  });
}
