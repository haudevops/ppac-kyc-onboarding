import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/presentation/widgets.dart';
import '../../domain/entities/kyc_enums.dart';
import '../bloc/kyc_bloc.dart';
import '../camera/camera_capture_page.dart';
import '../camera/capture_overlay.dart';
import '../widgets/document_slot_card.dart';
import 'step_scaffold.dart';

/// Step 3 - selfie with the front camera and an oval face guide.
class SelfieStep extends StatelessWidget {
  const SelfieStep({super.key});

  Future<void> _capture(BuildContext context) async {
    final bloc = context.read<KycBloc>();
    final path = await CameraCapturePage.open(context, mode: CaptureMode.selfie, title: 'Take a selfie');
    if (path != null) bloc.add(KycDocumentCaptured(type: DocumentType.selfie, sourcePath: path));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KycBloc, KycState>(
      builder: (context, state) {
        const type = DocumentType.selfie;
        final ready = state.draft.hasDocument(type) && !state.processingDocuments.contains(type);
        final requested = state.requestedOn(KycStep.selfie);
        return StepScaffold(
          header: requested.isEmpty
              ? null
              : InfoBanner(
                  message: 'Please retake: ${requested.map((i) => i.label.toLowerCase()).join(', ')}. '
                      '${state.rejectionReason ?? ''}',
                  icon: Icons.assignment_late_outlined,
                  isError: true,
                ),
          title: 'Take a selfie',
          subtitle: 'We compare it with the photo on your document to make sure it is really you.',
          primary: PrimaryButton(
            label: 'Continue',
            icon: Icons.arrow_forward,
            onPressed: ready ? () => context.read<KycBloc>().add(const KycStepContinued()) : null,
          ),
          onBack: () => context.read<KycBloc>().add(const KycStepBackRequested()),
          children: [
            DocumentSlotCard(
              title: 'Your selfie',
              subtitle: 'Look straight at the camera with a neutral expression.',
              document: state.draft.documents[type],
              processing: state.processingDocuments.contains(type),
              oval: true,
              aspectRatio: CaptureMode.selfie.aspectRatio,
              enabled: state.canEdit,
              onCapture: () => _capture(context),
              onRetryUpload: () => context.read<KycBloc>().add(const KycDocumentUploadRetried(type)),
            ),
            const SizedBox(height: 16),
            const _Tip(icon: Icons.wb_sunny_outlined, text: 'Find good, even lighting - face a window if you can.'),
            const _Tip(icon: Icons.face_retouching_off, text: 'Remove glasses, hats and face masks.'),
            const _Tip(icon: Icons.person_outline, text: 'Only you should be in the picture.'),
          ],
        );
      },
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
