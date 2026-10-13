import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../error/app_exception.dart';

/// Compresses captured photos before they are stored/uploaded:
///  * re-encodes as JPEG and downsizes so the short edge is ~[maxShortEdge]px
///    (plenty for document OCR / face match, ~300-700 KB instead of 3-8 MB);
///  * applies EXIF rotation and strips EXIF metadata (GPS location, device info = PII);
///  * steps the quality down until the file fits under [maxBytes] (backend limit is 5 MB).
class ImageProcessor {
  const ImageProcessor({
    this.maxShortEdge = 1600,
    this.maxBytes = 4 * 1024 * 1024,
    this.qualitySteps = const [85, 70, 55, 40],
  });

  final int maxShortEdge;
  final int maxBytes;
  final List<int> qualitySteps;

  /// [targetPath] must end with `.jpg`.
  Future<File> compressForUpload({required String sourcePath, required String targetPath}) async {
    for (final quality in qualitySteps) {
      final result = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        targetPath,
        quality: quality,
        minWidth: maxShortEdge,
        minHeight: maxShortEdge,
        format: CompressFormat.jpeg,
        keepExif: false,
        autoCorrectionAngle: true,
      );
      if (result == null) break;

      final file = File(result.path);
      if (await file.length() <= maxBytes) return file;
    }

    throw const AppException(
      AppErrorType.storage,
      'Could not process the photo. Please try taking it again.',
    );
  }
}
