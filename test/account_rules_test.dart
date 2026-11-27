import 'package:campuslink/features/account/account_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Uganda phone numbers', () {
    test('common ways of typing become +256…', () {
      expect(normalizeUgPhone('0772 123456'), '+256772123456');
      expect(normalizeUgPhone('0772-123-456'), '+256772123456');
      expect(normalizeUgPhone('772123456'), '+256772123456');
      expect(normalizeUgPhone('256772123456'), '+256772123456');
      expect(normalizeUgPhone('+256 772 123 456'), '+256772123456');
      expect(normalizeUgPhone('00256772123456'), '+256772123456');
      expect(normalizeUgPhone('+254712345678'), '+254712345678'); // Kenya stays as typed
    });
    test('nonsense is rejected', () {
      expect(normalizeUgPhone(''), isNull);
      expect(normalizeUgPhone('12345'), isNull);
      expect(normalizeUgPhone('+25677212345'), isNull); // one digit short
      expect(normalizeUgPhone('hello'), isNull);
    });
  });

  group('School email quick check', () {
    test('school emails pass', () {
      expect(SchoolEmail.quickCheck('xx123456@students.cavendish.ac.ug'), isNull);
      expect(SchoolEmail.quickCheck('  XX123456@Students.Cavendish.ac.ug '), isNull);
    });
    test('personal and broken emails are caught', () {
      expect(SchoolEmail.quickCheck('me@gmail.com'), contains('school email'));
      expect(SchoolEmail.quickCheck('xx123456@'), isNotNull);
      expect(SchoolEmail.quickCheck(''), isNotNull);
    });
  });

  group('Passwords', () {
    test('rules', () {
      expect(PasswordRules.check('short1'), contains('8'));
      expect(PasswordRules.check('onlyletters'), contains('letters and numbers'));
      expect(PasswordRules.check('xx123456x1', email: 'xx123456@students.cavendish.ac.ug'), contains('email'));
      expect(PasswordRules.check('Password1'), contains('common'));
      expect(PasswordRules.check('password1'), contains('common'));
      expect(PasswordRules.check('blue-Mango-42'), isNull);
    });
    test('strength grows', () {
      expect(PasswordRules.strength('abc'), 0);
      expect(PasswordRules.strength('Mango2026long!'), 3);
    });
  });

  test('price label', () {
    expect(TutorOffer.priceLabel(rateUgx: null), 'Price not set');
    expect(TutorOffer.priceLabel(rateUgx: 0), 'Free');
    expect(TutorOffer.priceLabel(rateUgx: 10000, unit: 'session', firstFree: true), 'UGX 10,000 / session · first session free');
    expect(TutorOffer.priceLabel(rateUgx: 150000, unit: 'month', negotiable: true), 'UGX 150,000 / month · can discuss');
  });

  test('error words', () {
    expect(friendlyAccountError(Exception('AuthException: Database error saving new user')), contains('school email'));
    expect(friendlyAccountError(Exception('Invalid login credentials')), contains('Forgot password'));
    expect(friendlyAccountError(Exception('otp_expired')), contains('expired'));
  });
}
