import 'package:campuslink/data/community_repository.dart';
import 'package:campuslink/data/local_repository.dart';
import 'package:campuslink/widgets/confirm_send.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('edit marks, honest retraction, outsiders blocked', () async {
    SharedPreferences.setMockInitialValues({});
    final r = LocalRepository(await SharedPreferences.getInstance());
    await r.signIn(email: 'guild@x.ug', password: 'password1');
    final m = (await r.community.myMemberships()).firstWhere((m) => m.can('news'));
    final post = await r.community.createPost(
        publisherId: m.publisherId, kind: 'news', title: 'Career fair on Thursday', body: 'x' * 40, sourceNote: 'Guild office');
    await r.community.updatePost(post.id, title: 'Career fair on Friday', body: 'y' * 40);
    var p = (await r.community.post(post.id))!;
    expect((p.title, p.isEdited), ('Career fair on Friday', true));
    await expectLater(r.community.retractPost(post.id, 'wrong'), throwsA(isA<CommunityException>()), reason: 'a real reason is needed');
    await r.signOut();

    await r.signIn(email: 'student@x.ug', password: 'password1');
    await expectLater(r.community.retractPost(post.id, 'I just do not like it'), throwsA(isA<CommunityException>()));
    await expectLater(r.community.updatePost(post.id, title: 'hacked', body: 'z' * 40), throwsA(isA<CommunityException>()));
    await r.signOut();

    await r.signIn(email: 'guild@x.ug', password: 'password1');
    await r.community.retractPost(post.id, 'The fair was postponed to next month.');
    p = (await r.community.post(post.id))!;
    expect(p.isRetracted, isTrue);
    expect(p.retractReason, contains('postponed'));
    await expectLater(r.community.updatePost(post.id, title: 'sneaky fix', body: 'w' * 40), throwsA(isA<CommunityException>()),
        reason: 'a retracted post is frozen; publish a corrected one instead');
  });

  testWidgets('Send stays locked until "I have read it through" is ticked', (t) async {
    bool? result;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () async => result = await confirmBeforeSending(c, title: 'Exam moved', preview: 'BDA2207 is now on Friday', reach: 'All students'),
          child: const Text('go'),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    final send = find.widgetWithText(FilledButton, 'Send');
    expect(t.widget<FilledButton>(send).onPressed, isNull);
    await t.tap(find.text('I have read it through, and it is correct'));
    await t.pump();
    expect(t.widget<FilledButton>(send).onPressed, isNotNull);
    await t.tap(send);
    await t.pumpAndSettle();
    expect(result, isTrue);
  });
}
