import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Runtime configuration, read from compile-time defines.
///
/// Values come from the `.env` file at the project root:
///   flutter run --dart-define-from-file=.env
/// (the Android Studio / VS Code run configurations already pass this flag).
/// Any key can also be overridden individually with `--dart-define=KEY=value`.
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 20),
    this.sendTimeout = const Duration(seconds: 60),
    this.maxRetries = 3,
    this.statusPollInterval = const Duration(seconds: 2),
    this.protectScreen = true,
  });

  factory AppConfig.fromEnvironment() {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    // Empty -> emulator defaults: the Android emulator reaches the host through 10.0.2.2,
    // the iOS simulator uses localhost.
    final fallback = !kIsWeb && Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000';
    final base = fromEnv.trim().isNotEmpty ? fromEnv.trim() : fallback;

    return AppConfig(
      apiBaseUrl: base.replaceAll(RegExp(r'/+$'), ''),
      connectTimeout: const Duration(milliseconds: int.fromEnvironment('API_CONNECT_TIMEOUT_MS', defaultValue: 10000)),
      receiveTimeout: const Duration(milliseconds: int.fromEnvironment('API_RECEIVE_TIMEOUT_MS', defaultValue: 20000)),
      sendTimeout: const Duration(milliseconds: int.fromEnvironment('API_SEND_TIMEOUT_MS', defaultValue: 60000)),
      maxRetries: const int.fromEnvironment('API_MAX_RETRIES', defaultValue: 3),
      statusPollInterval:
          const Duration(milliseconds: int.fromEnvironment('KYC_STATUS_POLL_INTERVAL_MS', defaultValue: 2000)),
      protectScreen: const bool.fromEnvironment('PROTECT_SCREEN', defaultValue: true),
    );
  }

  final String apiBaseUrl;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  /// Generous because KYC submissions upload several images.
  final Duration sendTimeout;
  final int maxRetries;
  final Duration statusPollInterval;

  /// Block screenshots/recording on Android and hide content in the app switcher.
  /// Set PROTECT_SCREEN=false only to record a demo.
  final bool protectScreen;

  String get apiUrl => '$apiBaseUrl/api/v1';
}
