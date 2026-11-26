import 'package:campuslink/data/local_repository.dart';
import 'package:campuslink/data/models.dart';
import 'package:campuslink/data/providers.dart';
import 'package:campuslink/features/account/close_account.dart';
import 'package:campuslink/features/account/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const me = Profile(id: 'u1', fullName: 'Okecho Danmark Laston', programme: 'BDSAI', yearOfStudy: 2);

  Widget app(Widget child) => ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => Stream.value(me))],
        child: MaterialApp(home: child),
      );

  testWidgets('setup walks through 3 steps on a small phone', (t) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(360, 690);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(app(const WelcomeScreen()));
    await t.pumpAndSettle();
    expect(find.text('Welcome to CampusLink'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'Dan');
    await t.pump();
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('Your studies'), findsOneWidget);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('What you care about'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);
    await t.drag(find.byType(ListView), const Offset(0, -900));
    await t.pumpAndSettle();
    expect(find.text('Data saver'), findsOneWidget);
  });

  testWidgets('close account needs CLOSE typed', (t) async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalRepository(await SharedPreferences.getInstance());
    await t.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: CloseAccountScreen()),
    ));
    final button = find.widgetWithText(FilledButton, 'Close my account', skipOffstage: false);
    await t.scrollUntilVisible(find.byType(TextField).at(1), 200, scrollable: find.byType(Scrollable).first);
    await t.enterText(find.byType(TextField).at(1), 'close');
    await t.pump();
    expect(t.widget<FilledButton>(button).onPressed, isNotNull);
    await t.enterText(find.byType(TextField).at(1), 'nope');
    await t.pump();
    expect(t.widget<FilledButton>(button).onPressed, isNull);
  });
}
