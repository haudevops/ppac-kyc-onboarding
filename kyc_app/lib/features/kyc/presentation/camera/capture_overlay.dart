import 'dart:math' as math;

import 'package:flutter/material.dart';

/// What is being captured; drives the overlay shape and which lens is used.
enum CaptureMode {
  /// ID-1 card (national ID / driver's license): 85.60 x 53.98 mm.
  idCard(1.586, 'Place the card inside the frame'),

  /// Passport photo page (ID-3): 125 x 88 mm.
  passport(1.42, 'Place the passport photo page inside the frame'),

  /// Face inside an oval, front camera.
  selfie(0.75, 'Position your face inside the oval');

  const CaptureMode(this.aspectRatio, this.instruction);

  /// width / height of the guide shape.
  final double aspectRatio;
  final String instruction;

  bool get isSelfie => this == selfie;
}

/// Single source of truth for where the guide hole sits, shared by the painter and the
/// widgets positioned around it (instructions, hints).
abstract final class CaptureOverlayGeometry {
  static Rect holeFor(CaptureMode mode, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    if (mode.isSelfie) {
      final width = math.min(size.width * 0.72, size.height * 0.5 * mode.aspectRatio);
      return Rect.fromCenter(center: center, width: width, height: width / mode.aspectRatio);
    }
    final width = size.width * 0.9;
    return Rect.fromCenter(center: center, width: width, height: width / mode.aspectRatio);
  }
}

/// Darkens everything except a rounded rectangle (documents) or an oval (selfie),
/// then draws the guide outline. Corner brackets help align documents.
class CaptureOverlayPainter extends CustomPainter {
  const CaptureOverlayPainter({required this.mode, required this.guideColor});

  final CaptureMode mode;
  final Color guideColor;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = CaptureOverlayGeometry.holeFor(mode, size);
    final holePath = Path();
    if (mode.isSelfie) {
      holePath.addOval(hole);
    } else {
      holePath.addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(16)));
    }

    // Even-odd fill: full-screen rect minus the hole.
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(holePath, Offset.zero);
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.62));

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.8);
    canvas.drawPath(holePath, outline);

    if (!mode.isSelfie) _drawCornerBrackets(canvas, hole);
  }

  void _drawCornerBrackets(Canvas canvas, Rect r) {
    const length = 28.0;
    const radius = 16.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = guideColor;

    final path = Path()
      // top-left
      ..moveTo(r.left, r.top + radius + length)
      ..lineTo(r.left, r.top + radius)
      ..arcToPoint(Offset(r.left + radius, r.top), radius: const Radius.circular(radius))
      ..lineTo(r.left + radius + length, r.top)
      // top-right
      ..moveTo(r.right - radius - length, r.top)
      ..lineTo(r.right - radius, r.top)
      ..arcToPoint(Offset(r.right, r.top + radius), radius: const Radius.circular(radius))
      ..lineTo(r.right, r.top + radius + length)
      // bottom-right
      ..moveTo(r.right, r.bottom - radius - length)
      ..lineTo(r.right, r.bottom - radius)
      ..arcToPoint(Offset(r.right - radius, r.bottom), radius: const Radius.circular(radius))
      ..lineTo(r.right - radius - length, r.bottom)
      // bottom-left
      ..moveTo(r.left + radius + length, r.bottom)
      ..lineTo(r.left + radius, r.bottom)
      ..arcToPoint(Offset(r.left, r.bottom - radius), radius: const Radius.circular(radius))
      ..lineTo(r.left, r.bottom - radius - length);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CaptureOverlayPainter oldDelegate) =>
      oldDelegate.mode != mode || oldDelegate.guideColor != guideColor;
}
