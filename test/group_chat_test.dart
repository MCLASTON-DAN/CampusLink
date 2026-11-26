import 'package:campuslink/data/local_repository.dart';
import 'package:campuslink/data/models.dart';
import 'package:campuslink/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('mentions: @all, @username and first names; unknown names ignored', () {
    final members = <GroupMember>[(id: 'a', name: 'Amina Nakato', username: 'amina.n'), (id: 'b', name: 'Brian Okello', username: null)];
    expect(parseMentions('hi @amina.n and @brian', members).ids, ['a', 'b']);
    expect(parseMentions('meeting moved @all', members).all, isTrue);
    expect(parseMentions('email me@school.ug', members).ids, isEmpty, reason: 'an email is not a mention');
    expect(parseMentions('@nobody here', members).ids, isEmpty);
  });

  test('invite-only: ask, owner approves; chat is members only; 3 pins max', () async {
    SharedPreferences.setMockInitialValues({});
    final r = LocalRepository(await SharedPreferences.getInstance());

    await r.signIn(email: 'owner@x.ug', password: 'password1');
    final owner = r.currentUserSync!.id;
    await r.createStudyGroup(StudyGroup(
        id: 'grp', name: 'Stats crew', courseCode: 'BDA2207', description: '', ownerId: owner, memberIds: [owner], privacy: 'invite'));
    await r.signOut();

    await r.signIn(email: 'amina@x.ug', password: 'password1');
    final amina = r.currentUserSync!.id;
    await expectLater(r.toggleGroupMembership('grp', true), throwsException, reason: 'invite-only: no direct join');
    await expectLater(r.groupMessages('grp'), throwsException, reason: 'not a member yet');
    await r.requestToJoinGroup('grp', 'I take BDA2207');
    expect(await r.myPendingGroupRequests(), {'grp'});
    await r.signOut();

    await r.signIn(email: 'owner@x.ug', password: 'password1');
    final asks = await r.groupJoinRequests('grp');
    expect(asks.single.userId, amina);
    await r.decideGroupRequest(asks.single.id, approve: true);
    for (var i = 0; i < 4; i++) {
      await r.sendGroupMessage('grp', 'note $i');
    }
    final msgs = await r.groupMessages('grp');
    for (var i = 0; i < 3; i++) {
      await r.pinGroupMessage(msgs[i].id, pin: true);
    }
    await expectLater(r.pinGroupMessage(msgs[3].id, pin: true), throwsException, reason: 'up to 3 pins');
    await r.signOut();

    await r.signIn(email: 'amina@x.ug', password: 'password1');
    await r.sendGroupMessage('grp', 'thanks', replyTo: msgs.first.id);
    expect((await r.groupMessages('grp')).last.replyTo, msgs.first.id);
    await expectLater(r.pinGroupMessage(msgs.first.id, pin: false), throwsException, reason: 'only the owner pins');
  });
}
