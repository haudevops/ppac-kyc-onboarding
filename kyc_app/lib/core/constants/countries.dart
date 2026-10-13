/// Short list of ISO 3166-1 alpha-2 countries for the demo. A production app would load
/// the full list (with localisation) from the backend or a package.
const Map<String, String> kCountries = {
  'VN': 'Vietnam',
  'AU': 'Australia',
  'CA': 'Canada',
  'CN': 'China',
  'FR': 'France',
  'DE': 'Germany',
  'HK': 'Hong Kong',
  'IN': 'India',
  'ID': 'Indonesia',
  'JP': 'Japan',
  'KR': 'South Korea',
  'MY': 'Malaysia',
  'PH': 'Philippines',
  'SG': 'Singapore',
  'TW': 'Taiwan',
  'TH': 'Thailand',
  'GB': 'United Kingdom',
  'US': 'United States',
};

String countryName(String? code) => code == null ? '-' : (kCountries[code] ?? code);

/// International dialling codes (ITU-T E.164) for [kCountries].
const Map<String, String> kDialCodes = {
  'VN': '84',
  'AU': '61',
  'CA': '1',
  'CN': '86',
  'FR': '33',
  'DE': '49',
  'HK': '852',
  'IN': '91',
  'ID': '62',
  'JP': '81',
  'KR': '82',
  'MY': '60',
  'PH': '63',
  'SG': '65',
  'TW': '886',
  'TH': '66',
  'GB': '44',
  'US': '1',
};

/// Default country for the phone prefix.
const String kDefaultPhoneCountry = 'VN';

/// Flag emoji for an ISO 3166-1 alpha-2 code (e.g. `VN` -> 🇻🇳).
String countryFlag(String code) => String.fromCharCodes(
      code.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41),
    );

/// A phone number split into the selected country and the national part typed by the user.
class PhoneParts {
  const PhoneParts(this.countryCode, this.nationalNumber);

  final String countryCode;
  final String nationalNumber;
}

/// Splits a stored E.164 number (`+84901234567`) into country + national number.
/// Codes shared by several countries (`+1`) resolve to [preferred] when it matches.
PhoneParts splitPhoneNumber(String? e164, {String preferred = kDefaultPhoneCountry}) {
  final v = e164?.replaceAll(' ', '') ?? '';
  if (!v.startsWith('+')) return PhoneParts(preferred, v);
  final digits = v.substring(1);
  String? best;
  for (final e in kDialCodes.entries) {
    if (!digits.startsWith(e.value)) continue;
    final better = best == null ||
        e.value.length > kDialCodes[best]!.length ||
        (e.value.length == kDialCodes[best]!.length && e.key == preferred);
    if (better) best = e.key;
  }
  if (best == null) return PhoneParts(preferred, v); // unknown prefix: keep as typed
  return PhoneParts(best, digits.substring(kDialCodes[best]!.length));
}

/// Builds the E.164 number from the selected country and what the user typed.
/// A leading trunk `0` is dropped (`0901 234 567` -> `+84901234567`); a number typed with its own
/// `+` prefix is kept as is. Returns null when nothing was typed.
String? composePhoneNumber(String countryCode, String input) {
  final v = input.replaceAll(RegExp(r'[\s\-().]'), '');
  if (v.isEmpty) return null;
  if (v.startsWith('+')) return v;
  final national = v.replaceFirst(RegExp(r'^0+'), '');
  return '+${kDialCodes[countryCode] ?? ''}$national';
}
