import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../error/app_exception.dart';

/// Crops a captured photo to the guide frame the user saw on screen, so only the document
/// (plus a small margin) is kept instead of the whole camera frame (table, hands, background).
abstract final class FrameCropper {
  /// Extra space kept around the frame so card edges are never cut off (fraction of the short side).
  static const double defaultMargin = 0.04;

  /// Maps [frame] (screen coordinates) to a pixel rectangle in an upright photo of [image] size
  /// that was shown full-screen with `BoxFit.cover` on a screen of [screen] size.
  static Rect frameToImageRect({
    required Rect frame,
    required Size screen,
    required Size image,
    double margin = defaultMargin,
  }) {
    final scale = math.max(screen.width / image.width, screen.height / image.height);
    final shownWidth = image.width * scale;
    final shownHeight = image.height * scale;
    final dx = (shownWidth - screen.width) / 2; // part of the photo cut off on each side
    final dy = (shownHeight - screen.height) / 2;

    final padded = frame.inflate(frame.shortestSide * margin);
    final left = ((padded.left + dx) / scale).clamp(0.0, image.width);
    final top = ((padded.top + dy) / scale).clamp(0.0, image.height);
    final right = ((padded.right + dx) / scale).clamp(0.0, image.width);
    final bottom = ((padded.bottom + dy) / scale).clamp(0.0, image.height);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Decodes [sourcePath] (applying the EXIF orientation), crops it to [frame] and writes a
  /// JPEG to [targetPath]. Runs in a background isolate - decoding a 12 MP photo takes a moment.
  static Future<String> cropToFrame({
    required String sourcePath,
    required String targetPath,
    required Rect frame,
    required Size screen,
  }) async {
    final ok = await compute(_cropWorker, <Object>[
      sourcePath,
      targetPath,
      frame.left,
      frame.top,
      frame.right,
      frame.bottom,
      screen.width,
      screen.height,
    ]);
    if (!ok) {
      throw const AppException(AppErrorType.storage, 'Could not process the photo. Please try taking it again.');
    }
    return targetPath;
  }
}

bool _cropWorker(List<Object> args) {
  final decoded = img.decodeImage(File(args[0] as String).readAsBytesSync());
  if (decoded == null) return false;
  final upright = img.bakeOrientation(decoded);

  final rect = FrameCropper.frameToImageRect(
    frame: Rect.fromLTRB(args[2] as double, args[3] as double, args[4] as double, args[5] as double),
    screen: Size(args[6] as double, args[7] as double),
    image: Size(upright.width.toDouble(), upright.height.toDouble()),
  );
  if (rect.width < 1 || rect.height < 1) return false;

  final cropped = img.copyCrop(
    upright,
    x: rect.left.round(),
    y: rect.top.round(),
    width: rect.width.round(),
    height: rect.height.round(),
  );
  File(args[1] as String).writeAsBytesSync(img.encodeJpg(cropped, quality: 95));
  return true;
}
