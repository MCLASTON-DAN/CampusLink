import 'package:campuslink/data/access.dart';
import 'package:campuslink/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

Profile who(String id, [UserRole role = UserRole.student]) => Profile(id: id, fullName: id, role: role);
HelpRequest req(String? office) =>
    HelpRequest(id: 'r', studentId: 'amina', officeId: office, title: 't', description: '', createdAt: DateTime(2026), updatedAt: DateTime(2026));

void main() {
  bool sees(Profile me, String? office, {Set<String> mine = const {}, bool conf = false}) =>
      canSeeRequest(me: me, r: req(office), myOffices: mine, confidential: conf);

  test('the student always sees their own request', () {
    expect(sees(who('amina'), 'finance'), isTrue);
    expect(sees(who('amina'), 'counselling', conf: true), isTrue);
  });

  test('office members of other bodies (newsroom, guild, tutors) see nothing', () {
    expect(sees(who('newsroom-reporter'), 'finance'), isFalse);
    expect(sees(who('guild-rep'), null), isFalse);
  });

  test('handlers see only their own office; staff only the general desk', () {
    expect(sees(who('finance-clerk', UserRole.staff), 'finance', mine: {'finance'}), isTrue);
    expect(sees(who('finance-clerk', UserRole.staff), 'registrar', mine: {'finance'}), isFalse,
        reason: 'being staff is not enough for another office');
    expect(sees(who('any-staff', UserRole.staff), null), isTrue, reason: 'general desk is routed by staff');
  });

  test('super admin: yes for normal offices, no for confidential ones', () {
    expect(sees(who('boss', UserRole.superAdmin), 'finance'), isTrue);
    expect(sees(who('boss', UserRole.superAdmin), 'counselling', conf: true), isFalse);
    expect(sees(who('counsellor', UserRole.staff), 'counselling', mine: {'counselling'}, conf: true), isTrue);
  });
}
