import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/media/image_processor.dart';
import '../../../../core/security/draft_cipher.dart';
import '../../domain/entities/kyc_draft.dart';
import '../../domain/entities/kyc_enums.dart';
import '../models/kyc_mappers.dart';

/// Local draft storage used to resume an interrupted flow after the app is killed.
///
///  * Draft (form inputs, step, document metadata) -> SharedPreferences, one JSON per user,
///    encrypted with AES-256-GCM ([DraftCipher]; key kept in the Keychain / Keystore).
///  * Photos -> compressed JPEGs in `<app documents>/kyc_drafts/<userId>/` (not the cache
///    directory, which the OS may purge). Paths are stored relative to the documents dir.
///  * Everything is wiped on logout and once the application is approved.
class KycLocalDataSource {
  KycLocalDataSource({
    required SharedPreferences prefs,
    required ImageProcessor imageProcessor,
    required DraftCipher cipher,
    Future<Directory> Function()? documentsDirectory,
    Future<Directory> Function()? temporaryDirectory,
  })  : _prefs = prefs,
        _imageProcessor = imageProcessor,
        _cipher = cipher,
        _documentsDirectory = documentsDirectory ?? getApplicationDocumentsDirectory,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final SharedPreferences _prefs;
  final ImageProcessor _imageProcessor;
  final DraftCipher _cipher;
  final Future<Directory> Function() _documentsDirectory;
  final Future<Directory> Function() _temporaryDirectory;

  static String _key(String userId) => 'kyc.draft.v$kDraftSchemaVersion.$userId';

  Future<KycDraft?> load(String userId) async {
    final raw = _prefs.getString(_key(userId));
    if (raw == null) return null;
    try {
      final root = (await _documentsDirectory()).path;
      return kycDraftFromJson(
        jsonDecode(await _cipher.decrypt(raw)) as Map<String, dynamic>,
        resolvePath: (relative) {
          final absolute = p.join(root, relative);
          return File(absolute).existsSync() ? absolute : null;
        },
      );
    } on Object catch (e) {
      // Corrupted, tampered with, unencrypted legacy format or key lost: drop it rather than crash.
      debugPrint('Discarding unreadable KYC draft: $e');
      await _prefs.remove(_key(userId));
      return null;
    }
  }

  Future<void> save(String userId, KycDraft draft) async {
    final root = (await _documentsDirectory()).path;
    final json = kycDraftToJson(
      draft,
      relativize: (absolute) => p.isWithin(root, absolute) ? p.relative(absolute, from: root) : null,
    );
    await _prefs.setString(_key(userId), await _cipher.encrypt(jsonEncode(json)));
  }

  Future<void> clear(String userId) async {
    await _prefs.remove(_key(userId));
    final dir = await _userDirectory(userId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Compresses [sourcePath] into the user's draft folder and deletes the temporary original.
  Future<String> storeImage({required String userId, required DocumentType type, required String sourcePath}) async {
    final dir = await _userDirectory(userId);
    await dir.create(recursive: true);

    final target = p.join(dir.path, '${type.pathSegment}_${DateTime.now().millisecondsSinceEpoch}.jpg');
    final file = await _imageProcessor.compressForUpload(sourcePath: sourcePath, targetPath: target);

    // Camera / picker output lives in the temp dir: remove the uncompressed original (PII).
    final tmp = (await _temporaryDirectory()).path;
    if (p.isWithin(tmp, sourcePath)) await deleteImage(sourcePath);

    return file.path;
  }

  Future<void> deleteImage(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // ignore - best effort cleanup
    }
  }

  Future<Directory> _userDirectory(String userId) async {
    final root = await _documentsDirectory();
    final safeId = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return Directory(p.join(root.path, 'kyc_drafts', safeId));
  }
}
