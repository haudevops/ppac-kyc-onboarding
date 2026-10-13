import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/presentation/widgets.dart';
import '../../domain/entities/kyc_enums.dart';
import '../bloc/kyc_bloc.dart';
import '../camera/camera_capture_page.dart';
import '../camera/capture_overlay.dart';
import '../widgets/document_slot_card.dart';
import 'step_scaffold.dart';

/// Step 2 - photograph the ID (front + back) or the passport photo page.
class DocumentStep extends StatelessWidget {
  const DocumentStep({super.key});

  Future<void> _capture(BuildContext context, DocumentType type, IdType idType) async {
    final bloc = context.read<KycBloc>();
    final isPassport = idType == IdType.passport;
    final path = await CameraCapturePage.open(
      context,
      mode: isPassport ? CaptureMode.passport : CaptureMode.idCard,
      title: isPassport ? 'Passport photo page' : '${idType.label} - ${type.label.toLowerCase()}',
    );
    if (path != null) bloc.add(KycDocumentCaptured(type: type, sourcePath: path));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KycBloc, KycState>(
      builder: (context, state) {
        final idType = state.draft.effectiveIdType;
        final sides = idType.requiredDocuments.where((t) => t != DocumentType.selfie).toList();
        final ready = sides.every(state.draft.hasDocument);
        final isPassport = idType == IdType.passport;

        final requested = state.requestedOn(KycStep.document);
        return StepScaffold(
          header: requested.isEmpty
              ? null
              : InfoBanner(
                  message: 'Please retake: ${requested.map((i) => i.label.toLowerCase()).join(', ')}. '
                      '${state.rejectionReason ?? ''}',
                  icon: Icons.assignment_late_outlined,
                  isError: true,
                ),
          title: 'Photograph your ${idType.label.toLowerCase()}',
          subtitle: 'Use a well-lit place and a dark, plain background. Avoid glare and make sure all text is readable.',
          primary: PrimaryButton(
            label: 'Continue',
            icon: Icons.arrow_forward,
            onPressed: ready && state.processingDocuments.isEmpty
                ? () => context.read<KycBloc>().add(const KycStepContinued())
                : null,
          ),
          onBack: () => context.read<KycBloc>().add(const KycStepBackRequested()),
          children: [
            for (final type in sides) ...[
              DocumentSlotCard(
                title: isPassport ? 'Photo page' : type.label,
                subtitle: isPassport
                    ? 'The page with your photo and the machine-readable zone.'
                    : type == DocumentType.idFront
                        ? 'The side with your photo.'
                        : 'The other side of the card.',
                document: state.draft.documents[type],
                processing: state.processingDocuments.contains(type),
                aspectRatio: isPassport ? CaptureMode.passport.aspectRatio : CaptureMode.idCard.aspectRatio,
                enabled: state.canEdit,
                onCapture: () => _capture(context, type, idType),
                onRetryUpload: () => context.read<KycBloc>().add(KycDocumentUploadRetried(type)),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}
