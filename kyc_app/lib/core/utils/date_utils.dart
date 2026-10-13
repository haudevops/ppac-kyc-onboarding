/// Calendar-date helpers. KYC dates are plain calendar dates (no time zone), exchanged
/// with the API as `YYYY-MM-DD`.
String _two(int v) => v.toString().padLeft(2, '0');

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String formatIsoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String formatDisplayDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

final RegExp _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Strict parser: returns null for malformed or impossible dates (e.g. 2023-02-30).
DateTime? parseIsoDate(String? value) {
  if (value == null) return null;
  final match = _isoDate.firstMatch(value.trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// Age in whole years on [today].
int ageOn(DateTime dateOfBirth, DateTime today) {
  var age = today.year - dateOfBirth.year;
  final hadBirthday = today.month > dateOfBirth.month ||
      (today.month == dateOfBirth.month && today.day >= dateOfBirth.day);
  if (!hadBirthday) age--;
  return age;
}

/// `dd/MM/yyyy HH:mm` in local time.
String formatDisplayDateTime(DateTime d) {
  final local = d.toLocal();
  return '${formatDisplayDate(local)} ${_two(local.hour)}:${_two(local.minute)}';
}
