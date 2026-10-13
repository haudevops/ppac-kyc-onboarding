import '../../../../core/network/api_client.dart';
import '../../domain/entities/user.dart';
import '../models/auth_models.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource(this._api);

  final ApiClient _api;

  Future<AuthSession> login({required String email, required String password}) async {
    final data = await _api.post(
      '/auth/login',
      data: {'email': email, 'password': password},
      authenticated: false,
    );
    return AuthSession.fromJson(data);
  }

  Future<AuthSession> register({required String email, required String password, String? fullName}) async {
    final data = await _api.post(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        if (fullName != null && fullName.isNotEmpty) 'fullName': fullName,
      },
      authenticated: false,
    );
    return AuthSession.fromJson(data);
  }

  Future<User> me() async {
    final data = await _api.get('/auth/me');
    return userFromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> logout(String refreshToken) async {
    await _api.post(
      '/auth/logout',
      data: {'refreshToken': refreshToken},
      authenticated: false,
      timeout: const Duration(seconds: 5),
    );
  }
}
