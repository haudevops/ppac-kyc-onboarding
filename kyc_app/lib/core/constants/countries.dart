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
