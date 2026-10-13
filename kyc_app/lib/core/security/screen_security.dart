import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android: sets FLAG_SECURE on the activity window (see MainActivity.kt), which blocks
/// screenshots / screen recording and hides the app content in the recent-apps switcher.
/// iOS has no equivalent API; there [PrivacyOverlay] hides content in the app switcher.
abstract final class ScreenSecurity {
  static const _channel = MethodChannel('kyc_app/screen_security');

  static Future<void> setSecure(bool secure) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on PlatformException catch (e) {
      debugPrint('ScreenSecurity: $e');
    } on MissingPluginException {
      // Running in a test / host without the native side.
    }
  }
}
