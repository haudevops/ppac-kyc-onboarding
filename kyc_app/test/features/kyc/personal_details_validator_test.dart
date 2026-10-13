import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_enums.dart';
import 'package:kyc_app/features/kyc/domain/validation/personal_details_validator.dart';

import 'fixtures.dart';

void main() {
  group('PersonalDetailsValidator', () {
    test('a complete form is valid', () {
      expect(PersonalDetailsValidator.validate(completeDetails(), now: kNow), isEmpty);
    });

    test('full name', () {
      expect(PersonalDetailsValidator.fullName(''), isNotNull);
      expect(PersonalDetailsValidator.fullName('Alice'), isNotNull, reason: 'first + last name required');
      expect(PersonalDetailsValidator.fullName('Nguyễn Văn An'), isNull, reason: 'Vietnamese diacritics');
      expect(PersonalDetailsValidator.fullName("Mary-Jane O'Neil"), isNull);
      expect(PersonalDetailsValidator.fullName('Alice 123'), isNotNull);
    });

    test('date of birth requires an adult', () {
      expect(PersonalDetailsValidator.dateOfBirth(null, now: kNow), isNotNull);
      expect(PersonalDetailsValidator.dateOfBirth(DateTime(2008, 1, 16), now: kNow), isNotNull); // 17
      expect(PersonalDetailsValidator.dateOfBirth(DateTime(2008, 1, 15), now: kNow), isNull); // 18 today
      expect(PersonalDetailsValidator.dateOfBirth(DateTime(2030), now: kNow), isNotNull);
    });

    test('ID number depends on document type and nationality', () {
      expect(PersonalDetailsValidator.idNumber('079090001234', idType: IdType.nationalId, nationality: 'VN'), isNull);
      expect(PersonalDetailsValidator.idNumber('12345', idType: IdType.nationalId, nationality: 'VN'), isNotNull);
      expect(PersonalDetailsValidator.idNumber('c1234567', idType: IdType.passport), isNull);
      expect(PersonalDetailsValidator.idNumber('C12', idType: IdType.passport), isNotNull);
      expect(PersonalDetailsValidator.idNumber('AB-12345', idType: IdType.driverLicense), isNull);
    });

    test('ID dates', () {
      expect(PersonalDetailsValidator.idExpiryDate(DateTime(2025), now: kNow), isNotNull, reason: 'expired');
      expect(
        PersonalDetailsValidator.idExpiryDate(DateTime(2030), issueDate: DateTime(2031), now: kNow),
        isNotNull,
      );
      expect(PersonalDetailsValidator.idIssueDate(DateTime(2027), now: kNow), isNotNull, reason: 'future');
    });

    test('phone is optional but must be E.164', () {
      expect(PersonalDetailsValidator.phone(null), isNull);
      expect(PersonalDetailsValidator.phone('+84 901 234 567'), isNull);
      expect(PersonalDetailsValidator.phone('0901234567'), isNotNull);
    });
  });
}
