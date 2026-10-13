import 'package:equatable/equatable.dart';

import '../../../../core/utils/date_utils.dart';
import 'kyc_enums.dart';

/// Personal details captured in step 1. Every field is optional so the same type
/// represents a partial draft and a complete submission.
class PersonalDetails extends Equatable {
  const PersonalDetails({
    this.fullName,
    this.dateOfBirth,
    this.gender,
    this.nationality,
    this.phoneNumber,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.stateProvince,
    this.postalCode,
    this.country,
    this.idType,
    this.idNumber,
    this.idIssueDate,
    this.idExpiryDate,
  });

  /// Inverse of [toFieldMap]; tolerant to nulls and unknown values.
  factory PersonalDetails.fromFieldMap(Map<String, dynamic> map) {
    String? str(String key) {
      final value = map[key];
      return value is String && value.trim().isNotEmpty ? value : null;
    }

    return PersonalDetails(
      fullName: str('fullName'),
      dateOfBirth: parseIsoDate(str('dateOfBirth')),
      gender: Gender.fromApi(str('gender')),
      nationality: str('nationality'),
      phoneNumber: str('phoneNumber'),
      addressLine1: str('addressLine1'),
      addressLine2: str('addressLine2'),
      city: str('city'),
      stateProvince: str('stateProvince'),
      postalCode: str('postalCode'),
      country: str('country'),
      idType: IdType.fromApi(str('idType')),
      idNumber: str('idNumber'),
      idIssueDate: parseIsoDate(str('idIssueDate')),
      idExpiryDate: parseIsoDate(str('idExpiryDate')),
    );
  }

  final String? fullName;
  final DateTime? dateOfBirth;
  final Gender? gender;

  /// ISO 3166-1 alpha-2.
  final String? nationality;

  /// E.164, e.g. +84901234567.
  final String? phoneNumber;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? stateProvince;
  final String? postalCode;
  final String? country;
  final IdType? idType;
  final String? idNumber;
  final DateTime? idIssueDate;
  final DateTime? idExpiryDate;

  bool get isEmpty => toFieldMap().isEmpty;

  /// API field name -> value (non-empty values only, dates as YYYY-MM-DD).
  /// Used for the API payload, the local draft and per-field change detection.
  Map<String, String> toFieldMap() {
    final entries = <String, String?>{
      'fullName': fullName,
      'dateOfBirth': dateOfBirth == null ? null : formatIsoDate(dateOfBirth!),
      'gender': gender?.apiValue,
      'nationality': nationality,
      'phoneNumber': phoneNumber,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'stateProvince': stateProvince,
      'postalCode': postalCode,
      'country': country,
      'idType': idType?.apiValue,
      'idNumber': idNumber,
      'idIssueDate': idIssueDate == null ? null : formatIsoDate(idIssueDate!),
      'idExpiryDate': idExpiryDate == null ? null : formatIsoDate(idExpiryDate!),
    };
    return {
      for (final e in entries.entries)
        if (e.value != null && e.value!.trim().isNotEmpty) e.key: e.value!.trim(),
    };
  }

  /// Canonical form sent to the API (trimmed, collapsed spaces, upper-cased codes).
  PersonalDetails normalized() {
    String? clean(String? v) {
      final t = v?.trim().replaceAll(RegExp(r'\s+'), ' ');
      return t == null || t.isEmpty ? null : t;
    }

    return PersonalDetails(
      fullName: clean(fullName),
      dateOfBirth: dateOfBirth == null ? null : dateOnly(dateOfBirth!),
      gender: gender,
      nationality: clean(nationality)?.toUpperCase(),
      phoneNumber: clean(phoneNumber)?.replaceAll(' ', ''),
      addressLine1: clean(addressLine1),
      addressLine2: clean(addressLine2),
      city: clean(city),
      stateProvince: clean(stateProvince),
      postalCode: clean(postalCode),
      country: clean(country)?.toUpperCase(),
      idType: idType,
      idNumber: clean(idNumber)?.replaceAll(' ', '').toUpperCase(),
      idIssueDate: idIssueDate == null ? null : dateOnly(idIssueDate!),
      idExpiryDate: idExpiryDate == null ? null : dateOnly(idExpiryDate!),
    );
  }

  /// Field-wise merge: non-null values of [other] win.
  PersonalDetails mergeWith(PersonalDetails? other) {
    if (other == null) return this;
    return PersonalDetails(
      fullName: other.fullName ?? fullName,
      dateOfBirth: other.dateOfBirth ?? dateOfBirth,
      gender: other.gender ?? gender,
      nationality: other.nationality ?? nationality,
      phoneNumber: other.phoneNumber ?? phoneNumber,
      addressLine1: other.addressLine1 ?? addressLine1,
      addressLine2: other.addressLine2 ?? addressLine2,
      city: other.city ?? city,
      stateProvince: other.stateProvince ?? stateProvince,
      postalCode: other.postalCode ?? postalCode,
      country: other.country ?? country,
      idType: other.idType ?? idType,
      idNumber: other.idNumber ?? idNumber,
      idIssueDate: other.idIssueDate ?? idIssueDate,
      idExpiryDate: other.idExpiryDate ?? idExpiryDate,
    );
  }

  @override
  List<Object?> get props => [
        fullName,
        dateOfBirth,
        gender,
        nationality,
        phoneNumber,
        addressLine1,
        addressLine2,
        city,
        stateProvince,
        postalCode,
        country,
        idType,
        idNumber,
        idIssueDate,
        idExpiryDate,
      ];
}
