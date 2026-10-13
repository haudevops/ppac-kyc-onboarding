import '../../domain/entities/user.dart';

User userFromJson(Map<String, dynamic> json) => User(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['fullName'] as String?,
    );

Map<String, dynamic> userToJson(User user) => {
      'id': user.id,
      'email': user.email,
      'fullName': user.fullName,
    };

class AuthSession {
  const AuthSession({required this.user, required this.accessToken, required this.refreshToken});

  /// Parses `data` of POST /auth/login and /auth/register.
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final tokens = json['tokens'] as Map<String, dynamic>;
    return AuthSession(
      user: userFromJson(json['user'] as Map<String, dynamic>),
      accessToken: tokens['accessToken'] as String,
      refreshToken: tokens['refreshToken'] as String,
    );
  }

  final User user;
  final String accessToken;
  final String refreshToken;
}
