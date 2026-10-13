import 'package:flutter/material.dart';

/// Common layout for wizard steps: scrollable content + sticky bottom actions.
class StepScaffold extends StatelessWidget {
  const StepScaffold({
    super.key,
    required this.title,
    required this.children,
    required this.primary,
    this.subtitle,
    this.onBack,
    this.header,
  });

  final String title;
  final String? subtitle;
  final Widget? header;
  final List<Widget> children;
  final Widget primary;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              if (header != null) ...[header!, const SizedBox(height: 16)],
              Text(title, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: textTheme.bodyMedium),
              ],
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                if (onBack != null) ...[
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(onPressed: onBack, child: const Text('Back')),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(child: primary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
