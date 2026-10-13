import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/entities/kyc_draft.dart';
import '../../domain/entities/kyc_enums.dart';

/// Thumbnail + upload status + capture / retake action for one required image.
class DocumentSlotCard extends StatelessWidget {
  const DocumentSlotCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.document,
    required this.processing,
    required this.onCapture,
    this.onRetryUpload,
    this.oval = false,
    this.aspectRatio = 1.586,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final KycDocument? document;
  final bool processing;
  final VoidCallback onCapture;
  final VoidCallback? onRetryUpload;
  final bool oval;
  final double aspectRatio;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = document?.isAvailable ?? false;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                if (document != null) _UploadChip(state: document!.uploadState, onRetry: onRetryUpload),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: oval ? 200 : double.infinity),
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: _Thumbnail(document: document, processing: processing, oval: oval),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: enabled && !processing ? onCapture : null,
              icon: Icon(hasImage ? Icons.refresh : Icons.photo_camera_outlined),
              label: Text(hasImage ? 'Retake' : 'Capture'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.document, required this.processing, required this.oval});

  final KycDocument? document;
  final bool processing;
  final bool oval;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final localPath = document?.localPath;
    final remoteUrl = document?.remoteUrl;

    Widget child;
    if (processing) {
      child = const Center(child: CircularProgressIndicator());
    } else if (localPath != null) {
      child = Image.file(File(localPath), fit: BoxFit.cover, cacheWidth: 800, gaplessPlayback: true);
    } else if (remoteUrl != null) {
      child = Image.network(
        remoteUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const _Placeholder(icon: Icons.cloud_done_outlined, text: 'Saved on server'),
      );
    } else if (document?.uploadState == DocumentUploadState.uploaded) {
      child = const _Placeholder(icon: Icons.cloud_done_outlined, text: 'Saved on server');
    } else {
      child = _Placeholder(icon: oval ? Icons.face_outlined : Icons.badge_outlined, text: 'No photo yet');
    }

    final decorated = Container(color: scheme.surfaceContainerHighest, child: child);
    return oval
        ? ClipOval(child: decorated)
        : ClipRRect(borderRadius: BorderRadius.circular(12), child: decorated);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 6),
          Text(text, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

class _UploadChip extends StatelessWidget {
  const _UploadChip({required this.state, this.onRetry});

  final DocumentUploadState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, String label, Color color) = switch (state) {
      DocumentUploadState.pending => (Icons.schedule, 'Saved on device', scheme.outline),
      DocumentUploadState.uploading => (Icons.cloud_upload_outlined, 'Uploading...', scheme.primary),
      DocumentUploadState.uploaded => (Icons.cloud_done_outlined, 'Uploaded', Colors.green.shade700),
      DocumentUploadState.failed => (Icons.cloud_off_outlined, 'Retry upload', scheme.error),
    };

    final chip = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );

    if (state == DocumentUploadState.failed && onRetry != null) {
      return InkWell(onTap: onRetry, borderRadius: BorderRadius.circular(8), child: Padding(padding: const EdgeInsets.all(4), child: chip));
    }
    return chip;
  }
}
