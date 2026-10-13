import '../../../../core/utils/date_utils.dart';
import '../entities/kyc_enums.dart';
import '../entities/personal_details.dart';

/// Client-side rules mirroring the backend Zod schema (backend stays the source of truth;
/// these give instant feedback and avoid a round trip).
/// Each method returns an error message or null. Keys of [validate] are API field names.
abstract final class PersonalDetailsValidator {
  static final RegExp _name = RegExp(r"^[\p{L}\p{M}' .-]+$", unicode: true);
  static final RegExp _genericId = RegExp(r'^[A-Z0-9-]{5,30}$');
  static final RegExp _vnNationalId = RegExp(r'^(\d{9}|\d{12})$');
  static final RegExp _passport = RegExp(r'^[A-Z0-9]{6,9}$');
  static final RegExp _phone = RegExp(r'^\+[1-9]\d{7,14}$');
  static final RegExp _country = RegExp(r'^[A-Z]{2}$');

  static const minimumAge = 18;

  static String? fullName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Full name is required';
    if (v.length < 2) return 'Full name is too short';
    if (v.length > 100) return 'Full name is too long';
    if (!_name.hasMatch(v)) return 'Use letters only (as printed on your ID)';
    if (!v.contains(' ')) return 'Enter your full name (first and last name)';
    return null;
  }

  static String? dateOfBirth(DateTime? value, {DateTime? now}) {
    if (value == null) return 'Date of birth is required';
    final today = dateOnly(now ?? DateTime.now());
    if (value.isAfter(today)) return 'Date of birth cannot be in the future';
    if (value.isBefore(DateTime(1900))) return 'Enter a valid date of birth';
    if (ageOn(value, today) < minimumAge) return 'You must be at least $minimumAge years old';
    return null;
  }

  static String? idNumber(String? value, {IdType? idType, String? nationality}) {
    final v = value?.replaceAll(' ', '').toUpperCase() ?? '';
    if (v.isEmpty) return 'ID number is required';
    if (idType == IdType.passport) {
      return _passport.hasMatch(v) ? null : 'Passport number must be 6-9 letters or digits';
    }
    if (idType == IdType.nationalId && nationality == 'VN') {
      return _vnNationalId.hasMatch(v) ? null : 'Vietnamese ID numbers have 9 or 12 digits';
    }
    return _genericId.hasMatch(v) ? null : 'ID number must be 5-30 letters, digits or dashes';
  }

  static String? idType(IdType? value) => value == null ? 'Select a document type' : null;

  static String? idIssueDate(DateTime? value, {DateTime? dateOfBirth, DateTime? now}) {
    if (value == null) return null; // optional
    final today = dateOnly(now ?? DateTime.now());
    if (value.isAfter(today)) return 'Issue date cannot be in the future';
    if (dateOfBirth != null && value.isBefore(dateOfBirth)) return 'Issue date cannot be before your birth date';
    return null;
  }

  static String? idExpiryDate(DateTime? value, {DateTime? issueDate, DateTime? now}) {
    if (value == null) return 'Expiry date is required';
    final today = dateOnly(now ?? DateTime.now());
    if (!value.isAfter(today)) return 'This document has expired';
    if (issueDate != null && !value.isAfter(issueDate)) return 'Expiry date must be after the issue date';
    return null;
  }

  static String? requiredText(String? value, String label, {int min = 1, int max = 200}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '$label is required';
    if (v.length < min) return '$label is too short';
    if (v.length > max) return '$label is too long';
    return null;
  }

  static String? optionalText(String? value, String label, {int max = 200}) {
    final v = value?.trim() ?? '';
    return v.length > max ? '$label is too long' : null;
  }

  static String? country(String? value, String label) {
    if (value == null || value.isEmpty) return '$label is required';
    return _country.hasMatch(value) ? null : 'Select a valid $label';
  }

  static String? phone(String? value) {
    final v = value?.replaceAll(' ', '') ?? '';
    if (v.isEmpty) return null; // optional
    return _phone.hasMatch(v) ? null : 'Use international format, e.g. +84901234567';
  }

  /// Validates the whole form. Empty map == valid.
  static Map<String, String> validate(PersonalDetails details, {DateTime? now}) {
    final d = details.normalized();
    final errors = <String, String?>{
      'fullName': fullName(d.fullName),
      'dateOfBirth': dateOfBirth(d.dateOfBirth, now: now),
      'nationality': country(d.nationality, 'nationality'),
      'phoneNumber': phone(d.phoneNumber),
      'addressLine1': requiredText(d.addressLine1, 'Address', min: 3),
      'addressLine2': optionalText(d.addressLine2, 'Address line 2'),
      'city': requiredText(d.city, 'City', max: 100),
      'stateProvince': optionalText(d.stateProvince, 'State / province', max: 100),
      'postalCode': optionalText(d.postalCode, 'Postal code', max: 20),
      'country': country(d.country, 'country'),
      'idType': idType(d.idType),
      'idNumber': idNumber(d.idNumber, idType: d.idType, nationality: d.nationality),
      'idIssueDate': idIssueDate(d.idIssueDate, dateOfBirth: d.dateOfBirth, now: now),
      'idExpiryDate': idExpiryDate(d.idExpiryDate, issueDate: d.idIssueDate, now: now),
    };
    return {
      for (final e in errors.entries)
        if (e.value != null) e.key: e.value!,
    };
  }
}
