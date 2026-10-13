import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_app/core/constants/countries.dart';
import 'package:kyc_app/features/kyc/domain/validation/personal_details_validator.dart';

void main() {
  group('composePhoneNumber', () {
    test('prepends the dial code and drops the trunk 0', () {
      expect(composePhoneNumber('VN', '0901 234 567'), '+84901234567');
      expect(composePhoneNumber('VN', '901234567'), '+84901234567');
      expect(composePhoneNumber('SG', '8123 4567'), '+6581234567');
    });

    test('keeps a number typed with its own + prefix', () {
      expect(composePhoneNumber('VN', '+6581234567'), '+6581234567');
    });

    test('returns null when empty (the field is optional)', () {
      expect(composePhoneNumber('VN', '  '), isNull);
    });

    test('the result passes the E.164 validator', () {
      expect(PersonalDetailsValidator.phone(composePhoneNumber('VN', '0901234567')), isNull);
      expect(PersonalDetailsValidator.phone(composePhoneNumber('VN', '12')), isNotNull);
    });
  });

  group('splitPhoneNumber', () {
    test('splits a stored E.164 number', () {
      final p = splitPhoneNumber('+84901234567');
      expect(p.countryCode, 'VN');
      expect(p.nationalNumber, '901234567');
    });

    test('prefers the longest dial code', () {
      expect(splitPhoneNumber('+85291234567').countryCode, 'HK'); // +852, not +85x
      expect(splitPhoneNumber('+886912345678').countryCode, 'TW');
    });

    test('shared +1 resolves to the preferred country', () {
      expect(splitPhoneNumber('+14165550123', preferred: 'CA').countryCode, 'CA');
      expect(splitPhoneNumber('+12025550123', preferred: 'US').countryCode, 'US');
    });

    test('empty defaults to Vietnam', () {
      final p = splitPhoneNumber(null);
      expect(p.countryCode, 'VN');
      expect(p.nationalNumber, '');
    });

    test('round-trips with composePhoneNumber', () {
      final p = splitPhoneNumber('+6581234567');
      expect(composePhoneNumber(p.countryCode, p.nationalNumber), '+6581234567');
    });
  });

  test('countryFlag', () {
    expect(countryFlag('VN'), '🇻🇳');
  });
}
