import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/presentation/widgets.dart';
import '../../domain/entities/kyc_enums.dart';
import '../bloc/kyc_bloc.dart';

/// Step 5 - live verification status (polling) and the final decision.
class VerificationStep extends StatelessWidget {
  const VerificationStep({super.key, this.onViewProfile});

  /// Shown as "Go to my profile" once approved.
  final VoidCallback? onViewProfile;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KycBloc, KycState>(
      builder: (context, state) {
        final bloc = context.read<KycBloc>();
        return RefreshIndicator(
          onRefresh: () async => bloc.add(const KycStatusRefreshRequested()),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: switch (state.serverStatus) {
                  KycStatus.approved => const _Outcome(
                      key: ValueKey('approved'),
                      icon: Icons.verified_rounded,
                      color: Colors.green,
                      title: "You're verified!",
                      message: 'Your identity has been confirmed. You now have full access to your account.',
                    ),
                  KycStatus.rejected => _Outcome(
                      key: const ValueKey('rejected'),
                      icon: Icons.cancel_rounded,
                      color: Theme.of(context).colorScheme.error,
                      title: 'Verification unsuccessful',
                      message: state.rejectionReason ?? 'We could not verify your identity.',
                    ),
                  KycStatus.resubmissionRequested => _Outcome(
                      key: const ValueKey('resubmission'),
                      icon: Icons.assignment_late_rounded,
                      color: Colors.orange.shade700,
                      title: 'Action needed',
                      message: state.rejectionReason ?? 'Some information needs to be updated.',
                    ),
                  _ => const _Pending(key: ValueKey('pending')),
                },
              ),
              const SizedBox(height: 32),
              _Timeline(status: state.serverStatus),
              const SizedBox(height: 24),
              if (state.serverStatus.isPending) ...[
                if (state.pollingError || state.isOffline)
                  const InfoBanner(
                    message: 'Connection problem - retrying automatically. Your submission is safe.',
                    icon: Icons.wifi_off,
                  )
                else
                  Text(
                    state.lastCheckedAt == null
                        ? 'Checking status...'
                        : 'Last checked at ${TimeOfDay.fromDateTime(state.lastCheckedAt!).format(context)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 12),
                if (!state.isPolling)
                  OutlinedButton.icon(
                    onPressed: () => bloc.add(const KycStatusRefreshRequested()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Check status'),
                  ),
              ],
              if (state.serverStatus == KycStatus.approved && onViewProfile != null)
                PrimaryButton(
                  label: 'Go to my profile',
                  icon: Icons.person_outline,
                  onPressed: onViewProfile,
                ),
              if (state.serverStatus == KycStatus.rejected)
                Text(
                  'This decision is final. If you believe it is a mistake, please contact our support team.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              if (state.serverStatus == KycStatus.resubmissionRequested) ...[
                if (state.resubmissionItems.isNotEmpty) ...[
                  Text('Please redo:', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in state.resubmissionItems)
                        Chip(avatar: const Icon(Icons.refresh, size: 18), label: Text(item.label)),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                PrimaryButton(
                  label: 'Fix and resubmit',
                  icon: Icons.edit_note,
                  onPressed: () => bloc.add(const KycResubmitRequested()),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Pending extends StatelessWidget {
  const _Pending({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        SizedBox.square(
          dimension: 96,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const SizedBox.square(dimension: 96, child: CircularProgressIndicator(strokeWidth: 5)),
              Icon(Icons.fingerprint, size: 44, color: theme.colorScheme.primary),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Verifying your identity', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'This usually takes a few seconds. You can leave the app - we will pick up right here when you return.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({super.key, required this.icon, required this.color, required this.title, required this.message});

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.elasticOut,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: Icon(icon, size: 96, color: color),
        ),
        const SizedBox(height: 16),
        Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(message, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.status});

  final KycStatus status;

  @override
  Widget build(BuildContext context) {
    final decided = status.isDecided;
    final decisionLabel = switch (status) {
      KycStatus.approved => 'Approved',
      KycStatus.rejected => 'Rejected',
      KycStatus.resubmissionRequested => 'Changes requested',
      _ => 'Decision',
    };
    final items = <(String, bool, bool)>[
      ('Submitted', true, false),
      ('Automated checks', status == KycStatus.processing || decided, status == KycStatus.processing),
      (decisionLabel, decided, false),
    ];

    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (final (label, done, active) in items)
              ListTile(
                dense: true,
                leading: active
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        done ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: done ? scheme.primary : scheme.outline,
                      ),
                title: Text(label),
              ),
          ],
        ),
      ),
    );
  }
}
