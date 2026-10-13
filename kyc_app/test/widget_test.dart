import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_enums.dart';
import 'package:kyc_app/features/kyc/presentation/camera/capture_overlay.dart';
import 'package:kyc_app/features/kyc/presentation/widgets/step_indicator.dart';

void main() {
  testWidgets('step indicator shows every step and checks completed ones', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StepIndicator(current: KycStep.selfie))),
    );

    for (final step in KycStep.values) {
      expect(find.text(step.label), findsOneWidget);
    }
    // Details + Document are done.
    expect(find.byIcon(Icons.check), findsNWidgets(2));
  });

  test('capture guide keeps the document aspect ratio and fits the screen', () {
    const screen = Size(390, 844);
    final card = CaptureOverlayGeometry.holeFor(CaptureMode.idCard, screen);
    expect(card.width / card.height, closeTo(1.586, 0.001));
    expect(card.width, lessThan(screen.width));

    final face = CaptureOverlayGeometry.holeFor(CaptureMode.selfie, screen);
    expect(face.height, greaterThan(face.width));
    expect(face.center.dx, screen.width / 2);
  });
}
