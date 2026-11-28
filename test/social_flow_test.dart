import 'package:campuslink/data/local_repository.dart';
import 'package:campuslink/data/models.dart';
import 'package:campuslink/data/providers.dart';
import 'package:campuslink/features/community/events_screens.dart';
import 'package:campuslink/features/community/news_screen.dart';
import 'package:campuslink/features/study/group_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lets the practice copy's saving (real async) and the screen (fake time) both finish.
Future<void> settle(WidgetTester tester, [int rounds = 20]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<LocalRepository> signedIn(WidgetTester tester, String email, {Size size = const Size(390, 4000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await tester.runAsync(SharedPreferences.getInstance);
  final repo = LocalRepository(prefs!);
  await tester.runAsync(() => repo.signIn(email: email, password: 'password1'));
  return repo;
}

Widget app(LocalRepository repo, Widget home) => ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo), isDemoModeProvider.overrideWithValue(true)],
      child: MaterialApp(home: home),
    );

void main() {
  testWidgets('events: like with the heart, see who liked it, and comment', (tester) async {
    final repo = await signedIn(tester, 'student@x.ug');
    await tester.pumpWidget(app(repo, const EventDetailScreen(eventId: 'ev-1')));
    await settle(tester);

    // A like is a like, not a "reaction": no emoji picker on events.
    expect(find.byIcon(Icons.add_reaction_outlined), findsNothing);
    await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
    await settle(tester);
    expect(find.text('1 like'), findsOneWidget);

    await tester.tap(find.text('1 like'));
    await settle(tester, 6);
    expect(find.text('Liked by'), findsOneWidget);
    Navigator.of(tester.element(find.text('Liked by'))).pop(); // close the sheet
    await settle(tester, 10);

    await tester.enterText(find.byType(TextField).last, 'Great event!');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await settle(tester);
    expect(find.text('Great event!'), findsOneWidget);

    // Comments have their own small heart.
    await tester.tap(find.byIcon(Icons.favorite_border_rounded).last);
    await settle(tester);
    expect(find.byIcon(Icons.favorite_rounded), findsNWidgets(2));
  });

  testWidgets('the heart on a news card likes the post right there', (tester) async {
    final repo = await signedIn(tester, 'student@x.ug', size: const Size(390, 1200));
    final post = (await tester.runAsync(() => repo.community.posts()))!.firstWhere((p) => !p.likedByMe);
    await tester.pumpWidget(app(repo, Scaffold(body: SingleChildScrollView(child: PostCard(post)))));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await settle(tester, 10);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.text('${post.likes + 1}'), findsOneWidget);
  });

  testWidgets('chat: react like WhatsApp, switch, and take it back', (tester) async {
    final repo = await signedIn(tester, 'owner@x.ug', size: const Size(390, 900));
    final me = repo.currentUserSync!.id;
    await tester.runAsync(() async {
      await repo.createStudyGroup(StudyGroup(id: 'grp', name: 'Stats crew', courseCode: 'BDA2207', description: '', ownerId: me, memberIds: [me]));
      await repo.sendGroupMessage('grp', 'Who has the CAT notes?');
    });
    await tester.pumpWidget(app(repo, const GroupChatScreen(groupId: 'grp')));
    await settle(tester);
    final bubble = find.text('Who has the CAT notes?');
    expect(bubble, findsOneWidget);

    Future<void> react(String emoji) async {
      await tester.longPress(bubble);
      await settle(tester, 6);
      await tester.tap(find.text(emoji).last);
      await settle(tester, 8);
    }

    await react('❤️');
    expect(find.text('❤️'), findsOneWidget, reason: 'the badge under the message');
    await react('😂');
    expect(find.text('❤️'), findsNothing);
    expect(find.text('😂'), findsOneWidget);
    await react('😂'); // same again removes it
    expect(find.text('😂'), findsNothing);
  });
}
