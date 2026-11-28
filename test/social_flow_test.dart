import 'package:campuslink/data/local_repository.dart';
import 'package:campuslink/data/providers.dart';
import 'package:campuslink/features/community/events_screens.dart';
import 'package:campuslink/features/community/news_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('reacting and commenting on an event work', (tester) async {
    tester.view.physicalSize = const Size(390, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    final repo = LocalRepository(prefs!);
    await tester.runAsync(() => repo.signIn(email: 'student@x.ug', password: 'password1'));
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo), isDemoModeProvider.overrideWithValue(true)],
      child: const MaterialApp(home: EventDetailScreen(eventId: 'ev-1')),
    ));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    final react = find.text('Like');
    expect(react, findsOneWidget);
    await tester.tap(react);
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Liked'), findsOneWidget);

    final box = find.byType(TextField).last;
    await tester.enterText(box, 'Great event!');
    await tester.tap(find.byIcon(Icons.send_rounded));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Great event!'), findsOneWidget);
  });

  testWidgets('the heart on a news card likes the post right there', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    final repo = LocalRepository(prefs!);
    await tester.runAsync(() => repo.signIn(email: 'student@x.ug', password: 'password1'));
    final post = (await tester.runAsync(() => repo.community.posts()))!.firstWhere((p) => !p.likedByMe);
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo), isDemoModeProvider.overrideWithValue(true)],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PostCard(post)))),
    ));
    await tester.pump();
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.text(' ${post.likes + 1}'), findsOneWidget);
  });
}
