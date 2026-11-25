import 'package:campuslink/data/community_repository.dart';
import 'package:campuslink/data/local_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('RSVP gives a ticket; only the organiser checks in; a ticket works once', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final r = LocalRepository(prefs);

    // Find an event the guild runs.
    await r.signIn(email: 'guild@x.ug', password: 'password1');
    final guild = (await r.community.myMemberships()).firstWhere((m) => m.can('events'));
    final ev = (await r.community.upcomingEvents()).firstWhere((e) => e.publisherId == guild.publisherId);
    await r.signOut();

    // Student says "I'm going" and gets a 6-character code.
    await r.signIn(email: 'student@x.ug', password: 'password1');
    final t = await r.community.rsvp(ev.id);
    expect(t.code.length, 6);
    expect((await r.community.rsvp(ev.id)).code, t.code, reason: 'tapping twice must not make a second ticket');
    expect((await r.community.rsvpCounts([ev.id]))[ev.id]!.$1, 1);
    // A student cannot check themselves in.
    await expectLater(r.community.checkIn(ev.id, t.code), throwsA(isA<CommunityException>()));
    await r.signOut();

    // The organising office checks them in; a fake code fails; a second scan says "already".
    await r.signIn(email: 'guild@x.ug', password: 'password1');
    await expectLater(r.community.checkIn(ev.id, 'ZZZZZZ'), throwsA(isA<CommunityException>()));
    expect(await r.community.checkIn(ev.id, t.code.toLowerCase()), contains('checked in'));
    expect(await r.community.checkIn(ev.id, t.code), contains('already'));
    expect((await r.community.rsvpCounts([ev.id]))[ev.id], (1, 1));
  });
}
