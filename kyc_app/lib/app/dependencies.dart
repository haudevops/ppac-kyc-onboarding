import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/media/image_processor.dart';
import '../core/network/api_client.dart';
import '../core/network/session_events.dart';
import '../core/security/draft_cipher.dart';
import '../core/storage/token_storage.dart';
import '../features/auth/data/datasources/auth_remote_data_source.dart';
import '../features/auth/data/repositories/auth_repository_impl.dart';
import '../features/auth/domain/repositories/auth_repository.dart';
import '../features/kyc/data/datasources/kyc_local_data_source.dart';
import '../features/kyc/data/datasources/kyc_remote_data_source.dart';
import '../features/kyc/data/repositories/kyc_repository_impl.dart';
import '../features/kyc/domain/repositories/kyc_repository.dart';

/// Composition root: the only place where concrete implementations are created.
/// Exposed to the widget tree through RepositoryProviders (see app.dart).
class AppDependencies {
  const AppDependencies({
    required this.config,
    required this.authRepository,
    required this.kycRepository,
    required this.sessionEvents,
  });

  static Future<AppDependencies> create(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    // Keychain items readable only on this device after first unlock: not migrated to backups
    // or other devices.
    const secureStorage = FlutterSecureStorage(
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    );
    final tokenStorage = TokenStorage(secureStorage);

    // iOS keeps Keychain items after uninstall: drop stale tokens on the first run of a fresh install.
    const firstRunKey = 'app.initialized';
    if (!(prefs.getBool(firstRunKey) ?? false)) {
      await tokenStorage.clear();
      await prefs.setBool(firstRunKey, true);
    }

    final sessionEvents = SessionEvents();
    final api = ApiClient.create(config: config, tokenStorage: tokenStorage, sessionEvents: sessionEvents);

    return AppDependencies(
      config: config,
      sessionEvents: sessionEvents,
      authRepository: AuthRepositoryImpl(
        remote: AuthRemoteDataSource(api),
        tokenStorage: tokenStorage,
        sessionEvents: sessionEvents,
      ),
      kycRepository: KycRepositoryImpl(
        remote: KycRemoteDataSource(api),
        local: KycLocalDataSource(
          prefs: prefs,
          imageProcessor: const ImageProcessor(),
          cipher: AesGcmDraftCipher(secureStorage),
        ),
      ),
    );
  }

  final AppConfig config;
  final AuthRepository authRepository;
  final KycRepository kycRepository;
  final SessionEvents sessionEvents;
}
