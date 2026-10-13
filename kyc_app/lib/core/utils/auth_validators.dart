/// Form validators for the auth screens (mirrors the backend password policy).
abstract final class AuthValidators {
  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!_email.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  static String? loginPassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    return null;
  }

  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.length < 8) return 'At least 8 characters';
    if (v.length > 72) return 'At most 72 characters';
    if (!RegExp('[a-z]').hasMatch(v)) return 'Add a lowercase letter';
    if (!RegExp('[A-Z]').hasMatch(v)) return 'Add an uppercase letter';
    if (!RegExp(r'\d').hasMatch(v)) return 'Add a digit';
    return null;
  }

  static String? optionalName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length < 2) return 'Name is too short';
    return null;
  }
}
