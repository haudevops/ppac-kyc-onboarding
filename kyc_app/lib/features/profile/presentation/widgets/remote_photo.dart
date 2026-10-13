import 'package:flutter/material.dart';

/// Network image for short-lived presigned URLs: spinner while loading and, when the URL has
/// expired or the network failed, a [fallback] or a "tap to reload" placeholder.
class RemotePhoto extends StatelessWidget {
  const RemotePhoto({super.key, required this.url, this.fallback, this.onRetry, this.fit = BoxFit.cover});

  final String url;
  final Widget? fallback;
  final VoidCallback? onRetry;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Image.network(
      url,
      fit: fit,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: const Center(child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
      errorBuilder: (context, error, stackTrace) =>
          fallback ??
          InkWell(
            onTap: onRetry,
            child: ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, color: scheme.outline),
                    if (onRetry != null) Text('Tap to reload', style: TextStyle(color: scheme.outline, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}
