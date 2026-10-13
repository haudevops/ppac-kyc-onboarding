import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/countries.dart';
import '../../../../core/presentation/widgets.dart';
import '../../../../core/utils/date_utils.dart';
import '../../domain/entities/kyc_draft.dart';
import '../../domain/entities/kyc_enums.dart';
import '../bloc/kyc_bloc.dart';
import 'step_scaffold.dart';

/// Step 4 - review everything, edit any section, then submit.
class ReviewStep extends StatefulWidget {
  const ReviewStep({super.key});

  @override
  State<ReviewStep> createState() => _ReviewStepState();
}

class _ReviewStepState extends State<ReviewStep> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KycBloc, KycState>(
      builder: (context, state) {
        final bloc = context.read<KycBloc>();
        final d = state.draft.details;
        final canEdit = state.canEdit;
        void edit(KycStep step) => bloc.add(KycStepSelected(step));

        final progress = state.uploadProgress;
        final submitLabel = state.isSubmitting && progress != null && progress < 1
            ? 'Uploading ${(progress * 100).round()}%'
            : 'Submit for verification';

        return StepScaffold(
          title: 'Review your information',
          subtitle: 'Make sure everything matches your document before submitting.',
          header: state.showRejectionBanner
              ? InfoBanner(
                  message: 'Reviewer feedback: ${state.rejectionReason}',
                  icon: Icons.error_outline,
                  isError: true,
                )
              : null,
          onBack: state.isSubmitting ? null : () => bloc.add(const KycStepBackRequested()),
          primary: PrimaryButton(
            label: submitLabel,
            icon: Icons.verified_outlined,
            loading: state.isSubmitting && (progress == null || progress >= 1),
            onPressed: canEdit && _confirmed ? () => bloc.add(const KycSubmitted()) : null,
          ),
          children: [
            _Section(
              title: 'Personal details',
              onEdit: canEdit ? () => edit(KycStep.personalDetails) : null,
              rows: {
                'Full name': d.fullName,
                'Date of birth': d.dateOfBirth == null ? null : formatDisplayDate(d.dateOfBirth!),
                'Gender': d.gender?.label,
                'Nationality': countryName(d.nationality),
                'Phone': d.phoneNumber,
              },
            ),
            _Section(
              title: 'Identity document',
              onEdit: canEdit ? () => edit(KycStep.personalDetails) : null,
              rows: {
                'Type': d.idType?.label,
                'Number': d.idNumber,
                'Issued': d.idIssueDate == null ? null : formatDisplayDate(d.idIssueDate!),
                'Expires': d.idExpiryDate == null ? null : formatDisplayDate(d.idExpiryDate!),
              },
            ),
            _Section(
              title: 'Address',
              onEdit: canEdit ? () => edit(KycStep.personalDetails) : null,
              rows: {
                'Address': [d.addressLine1, d.addressLine2].whereType<String>().join(', '),
                'City': d.city,
                'State / province': d.stateProvince,
                'Postal code': d.postalCode,
                'Country': countryName(d.country),
              },
            ),
            _PhotosSection(
              draft: state.draft,
              onEditDocument: canEdit ? () => edit(KycStep.document) : null,
              onEditSelfie: canEdit ? () => edit(KycStep.selfie) : null,
            ),
            if (state.isSubmitting && progress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _confirmed,
              onChanged: canEdit ? (v) => setState(() => _confirmed = v ?? false) : null,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'I confirm that the information is accurate and consent to the processing of my '
                'personal data for identity verification.',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows, this.onEdit});

  final String title;
  final Map<String, String?> rows;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = rows.entries.where((e) => e.value != null && e.value!.isNotEmpty && e.value != '-');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                if (onEdit != null) TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit, size: 18), label: const Text('Edit')),
              ],
            ),
            for (final row in visible)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(row.key, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                    ),
                    Expanded(child: Text(row.value!, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotosSection extends StatelessWidget {
  const _PhotosSection({required this.draft, this.onEditDocument, this.onEditSelfie});

  final KycDraft draft;
  final VoidCallback? onEditDocument;
  final VoidCallback? onEditSelfie;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Photos', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final type in draft.requiredDocuments)
                  _PhotoThumb(
                    document: draft.documents[type],
                    label: type == DocumentType.idFront && draft.effectiveIdType == IdType.passport
                        ? 'Photo page'
                        : type.label,
                    onTap: type == DocumentType.selfie ? onEditSelfie : onEditDocument,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.document, required this.label, this.onTap});

  final KycDocument? document;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final local = document?.localPath;
    final remote = document?.remoteUrl;
    Widget image;
    if (local != null) {
      image = Image.file(File(local), fit: BoxFit.cover, cacheWidth: 300);
    } else if (remote != null) {
      image = Image.network(remote, fit: BoxFit.cover);
    } else {
      image = Icon(document?.isAvailable ?? false ? Icons.cloud_done_outlined : Icons.hide_image_outlined,
          color: scheme.outline);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 96,
              height: 72,
              color: scheme.surfaceContainerHighest,
              child: image,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
