import 'package:flutter/material.dart';

import '../../domain/entities/kyc_enums.dart';

/// Horizontal progress indicator for the 5 wizard steps.
class StepIndicator extends StatelessWidget {
  const StepIndicator({super.key, required this.current});

  final KycStep current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const steps = KycStep.values;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Expanded(
              child: Semantics(
                label: 'Step ${i + 1} of ${steps.length}: ${steps[i].label}',
                selected: steps[i] == current,
                child: Column(
                  children: [
                    _Dot(index: i, done: i < current.index, active: i == current.index, scheme: scheme),
                    const SizedBox(height: 4),
                    Text(
                      steps[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: i <= current.index ? scheme.primary : scheme.outline,
                            fontWeight: i == current.index ? FontWeight.w700 : FontWeight.w400,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < steps.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 18),
                  color: i < current.index ? scheme.primary : scheme.outlineVariant,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.index, required this.done, required this.active, required this.scheme});

  final int index;
  final bool done;
  final bool active;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final filled = done || active;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? scheme.primary : scheme.surface,
        border: Border.all(color: filled ? scheme.primary : scheme.outlineVariant, width: 2),
      ),
      child: done
          ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
          : Text(
              '${index + 1}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: filled ? scheme.onPrimary : scheme.outline),
            ),
    );
  }
}
