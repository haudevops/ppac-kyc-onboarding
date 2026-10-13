import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_app/core/media/frame_cropper.dart';

void main() {
  group('FrameCropper.frameToImageRect', () {
    test('same aspect ratio: frame scales straight to the photo', () {
      final r = FrameCropper.frameToImageRect(
        frame: const Rect.fromLTWH(20, 200, 360, 227),
        screen: const Size(400, 800),
        image: const Size(1000, 2000), // 2.5x the screen, same 1:2 ratio
        margin: 0,
      );
      expect(r.left, closeTo(50, 0.01));
      expect(r.top, closeTo(500, 0.01));
      expect(r.width, closeTo(900, 0.01));
      expect(r.height, closeTo(567.5, 0.01));
    });

    test('photo wider than the screen: the cut-off sides are accounted for', () {
      // 1080x1920 photo covering a 400x800 screen: scale = 800/1920, shown width 450 → 25 px cut each side.
      final r = FrameCropper.frameToImageRect(
        frame: const Rect.fromLTWH(0, 0, 400, 800),
        screen: const Size(400, 800),
        image: const Size(1080, 1920),
        margin: 0,
      );
      expect(r.left, closeTo(60, 0.01));
      expect(r.right, closeTo(1020, 0.01));
      expect(r.top, closeTo(0, 0.01));
      expect(r.bottom, closeTo(1920, 0.01));
    });

    test('margin is added and the result is clamped to the photo', () {
      final r = FrameCropper.frameToImageRect(
        frame: const Rect.fromLTWH(0, 100, 400, 250),
        screen: const Size(400, 800),
        image: const Size(400, 800),
      );
      expect(r.left, 0); // would be negative with the margin
      expect(r.right, 400);
      expect(r.top, closeTo(90, 0.01)); // 4% of the 250 px short side
      expect(r.bottom, closeTo(360, 0.01));
    });
  });
}
