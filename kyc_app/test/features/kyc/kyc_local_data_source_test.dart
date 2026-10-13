import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_app/core/media/image_processor.dart';
import 'package:kyc_app/core/security/draft_cipher.dart';
import 'package:kyc_app/features/kyc/data/datasources/kyc_local_data_source.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_draft.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  const key = 'kyc.draft.v1.user-1';
  late Directory documents;
  late Directory temporary;
  late SharedPreferences prefs;
  late KycLocalDataSource dataSource;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    documents = await Directory.systemTemp.createTemp('kyc_docs');
    temporary = await Directory.systemTemp.createTemp('kyc_tmp');
    dataSource = KycLocalDataSource(
      prefs: prefs,
      imageProcessor: const ImageProcessor(),
      cipher: AesGcmDraftCipher(const FlutterSecureStorage()),
      documentsDirectory: () async => documents,
      temporaryDirectory: () async => temporary,
    );
  });

  tearDown(() async {
    await documents.delete(recursive: true);
    await temporary.delete(recursive: true);
  });

  File photo(String name) =>
      File('${documents.path}/kyc_drafts/user-1/$name')
        ..createSync(recursive: true)
        ..writeAsBytesSync([0xff, 0xd8, 0xff]);

  test('the draft is stored encrypted (no PII in plain text) and round-trips', () async {
    final selfie = photo('selfie.jpg');
    final draft = completeDraft(step: KycStep.selfie)
        .withDocument(KycDocument(type: DocumentType.selfie, localPath: selfie.path));

    await dataSource.save('user-1', draft);

    final raw = prefs.getString(key)!;
    expect(raw, startsWith('aesgcm1:'));
    expect(raw, isNot(contains('Alice')));
    expect(raw, isNot(contains('079090001234')));

    final restored = await dataSource.load('user-1');
    expect(restored, isNotNull);
    expect(restored!.details, draft.details);
    expect(restored.step, KycStep.selfie);
    expect(restored.documents[DocumentType.selfie]?.localPath, selfie.path);
  });

  test('a tampered or legacy plain-text draft is discarded instead of crashing', () async {
    await prefs.setString(key, '{"step":"review"}');
    expect(await dataSource.load('user-1'), isNull);
    expect(prefs.getString(key), isNull);

    await dataSource.save('user-1', completeDraft());
    final raw = prefs.getString(key)!;
    await prefs.setString(key, '${raw.substring(0, raw.length - 8)}AAAAAAAA');
    expect(await dataSource.load('user-1'), isNull);
  });

  test('clear removes the draft and every cached photo', () async {
    final selfie = photo('selfie.jpg');
    await dataSource.save('user-1', completeDraft());
    await dataSource.clear('user-1');
    expect(prefs.getString(key), isNull);
    expect(selfie.existsSync(), isFalse);
  });
}
