import 'dart:io';

import 'package:campuslink/data/community_models.dart';
import 'package:campuslink/data/local_repository.dart';
import 'package:campuslink/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Badges must always come from the office that really posted.
/// These tests fail if any code path guesses or loses the office again.
void main() {
  test('an item with no office information gets NO badge (never a guessed one)', () {
    final post = Post.fromMap({
      'id': 'p1', 'publisher_id': 'x', 'kind': 'news', 'title': 't', 'body': 'b',
      'published_at': DateTime.now().toIso8601String(),
    });
    expect(post.publisherKind, isNull);
    expect(post.badge, isNull);
    final event = CampusEvent.fromMap({'id': 'e1', 'title': 'Event', 'starts_at': DateTime.now().toIso8601String()});
    expect(event.badge, isNull);
  });

  test('each office has its own colour', () {
    expect(badgeForKind('administration'), 'red');
    expect(badgeForKind('guild'), 'green');
    expect(badgeForKind('press'), 'purple');
    expect(badgeForKind('unknown'), isNull);
    expect(badgeForKind(null), isNull);
  });

  test('a Newsroom event shows PURPLE everywhere: Events page, Home and search use the same loader', () async {
    SharedPreferences.setMockInitialValues({});
    final r = LocalRepository(await SharedPreferences.getInstance());
    await r.signIn(email: 'press@x.ug', password: 'password1');
    final press = (await r.community.myMemberships()).firstWhere((m) => m.publisherKind == 'press');
    final created = await r.community.createEvent(CampusEvent(
      id: '',
      title: 'Newsroom open day',
      startsAt: DateTime.now().add(const Duration(days: 2)),
      publisherId: press.publisherId,
    ));
    expect(created.badge, 'purple', reason: 'event page');
    final home = (await r.events()).firstWhere((e) => e.title == 'Newsroom open day');
    expect(home.badge, 'purple', reason: 'Home "Coming up" and search');
    final all = (await r.community.upcomingEvents()).firstWhere((e) => e.title == 'Newsroom open day');
    expect(all.badge, 'purple', reason: 'Events list');
  });

  test('no data code may fall back to a made-up office', () {
    for (final f in Directory('lib/data').listSync().whereType<File>()) {
      final src = f.readAsStringSync();
      expect(RegExp(r"\?\?\s*'(guild|administration|press)'").hasMatch(src), isFalse,
          reason: '${f.path} guesses an office. Use null (no badge) instead.');
      expect(RegExp(r"this\.publisherKind\s*=\s*'").hasMatch(src), isFalse,
          reason: '${f.path} gives publisherKind a default office.');
    }
  });
}
