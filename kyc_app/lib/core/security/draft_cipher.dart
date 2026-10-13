import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypts data that is persisted outside secure storage (the KYC draft holds PII:
/// name, date of birth, ID number, address).
abstract interface class DraftCipher {
  Future<String> encrypt(String plaintext);

  /// Throws if the data was tampered with or the key changed.
  Future<String> decrypt(String ciphertext);
}

/// AES-256-GCM (authenticated encryption). The random 256-bit key lives in the
/// Keychain / Android Keystore-backed storage and never leaves the device, so the encrypted
/// blob in SharedPreferences (or in a device backup) is useless on its own.
class AesGcmDraftCipher implements DraftCipher {
  AesGcmDraftCipher(this._secureStorage);

  static const _keyName = 'kyc.draftKey.v1';
  static const _prefix = 'aesgcm1:';

  final FlutterSecureStorage _secureStorage;
  final AesGcm _algorithm = AesGcm.with256bits();
  Future<SecretKey>? _key;

  Future<SecretKey> _loadKey() => _key ??= _readOrCreateKey();

  Future<SecretKey> _readOrCreateKey() async {
    final stored = await _secureStorage.read(key: _keyName);
    if (stored != null) return SecretKey(base64Decode(stored));
    final key = await _algorithm.newSecretKey();
    await _secureStorage.write(key: _keyName, value: base64Encode(await key.extractBytes()));
    return key;
  }

  @override
  Future<String> encrypt(String plaintext) async {
    final box = await _algorithm.encrypt(utf8.encode(plaintext), secretKey: await _loadKey());
    return '$_prefix${base64Encode(box.concatenation())}';
  }

  @override
  Future<String> decrypt(String ciphertext) async {
    if (!ciphertext.startsWith(_prefix)) throw const FormatException('Unknown draft format');
    final box = SecretBox.fromConcatenation(
      base64Decode(ciphertext.substring(_prefix.length)),
      nonceLength: _algorithm.nonceLength,
      macLength: _algorithm.macAlgorithm.macLength,
    );
    final clear = await _algorithm.decrypt(box, secretKey: await _loadKey());
    return utf8.decode(clear);
  }
}
