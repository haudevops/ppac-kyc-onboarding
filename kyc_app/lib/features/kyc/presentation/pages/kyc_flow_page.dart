import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/presentation/widgets.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/widgets/logout_dialog.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import '../../domain/entities/kyc_enums.dart';
import '../../domain/repositories/kyc_repository.dart';
import '../bloc/kyc_bloc.dart';
import '../steps/document_step.dart';
import '../steps/personal_details_step.dart';
import '../steps/review_step.dart';
import '../steps/selfie_step.dart';
import '../steps/verification_step.dart';
import '../widgets/step_indicator.dart';

/// Host of the multi-step onboarding wizard. Owns the [KycBloc] for the signed-in user.
class KycFlowPage extends StatelessWidget {
  const KycFlowPage({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => KycBloc(
        repository: context.read<KycRepository>(),
        userId: user.id,
        pollInterval: context.read<AppConfig>().statusPollInterval,
      )..add(const KycStarted()),
      child: _KycFlowView(user: user),
    );
  }
}

class _KycFlowView extends StatefulWidget {
  const _KycFlowView({required this.user});

  final User user;

  @override
  State<_KycFlowView> createState() => _KycFlowViewState();
}

class _KycFlowViewState extends State<_KycFlowView> with WidgetsBindingObserver {
  /// Verified users land on their profile. Right after an approval we first show the
  /// success screen, and the user opens the profile from there.
  bool _showProfile = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back in the foreground: refresh a pending verification immediately.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<KycBloc>().add(const KycStatusRefreshRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<KycBloc, KycState>(
          listenWhen: (p, c) => c.message != null && p.message != c.message,
          listener: (context, state) => showUiMessage(context, state.message!),
        ),
        // Already approved when the app opens -> straight to the profile.
        BlocListener<KycBloc, KycState>(
          listenWhen: (p, c) =>
              p.loadStatus != KycLoadStatus.ready &&
              c.loadStatus == KycLoadStatus.ready &&
              c.serverStatus == KycStatus.approved,
          listener: (context, state) => setState(() => _showProfile = true),
        ),
      ],
      child: BlocBuilder<KycBloc, KycState>(
        buildWhen: (p, c) =>
            p.loadStatus != c.loadStatus ||
            p.step != c.step ||
            p.isOffline != c.isOffline ||
            p.canEdit != c.canEdit ||
            p.serverStatus != c.serverStatus,
        builder: (context, state) {
          if (_showProfile && state.serverStatus == KycStatus.approved) {
            return ProfilePage(user: widget.user);
          }
          final step = state.step;
          final canGoBack = state.loadStatus == KycLoadStatus.ready &&
              state.canEdit &&
              step != KycStep.personalDetails &&
              step != KycStep.verification;

          return PopScope(
            // Android back / iOS swipe moves to the previous wizard step instead of leaving.
            canPop: !canGoBack,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop && canGoBack) context.read<KycBloc>().add(const KycStepBackRequested());
            },
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Identity verification'),
                actions: [
                  IconButton(icon: const Icon(Icons.logout), tooltip: 'Log out', onPressed: () => confirmLogout(context)),
                ],
              ),
              body: SafeArea(
                bottom: false,
                child: switch (state.loadStatus) {
                  KycLoadStatus.initial || KycLoadStatus.loading => const Center(child: CircularProgressIndicator()),
                  KycLoadStatus.failure => _LoadError(
                      message: state.loadError ?? 'Could not load your verification.',
                      onRetry: () => context.read<KycBloc>().add(const KycStarted()),
                    ),
                  KycLoadStatus.ready => Column(
                      children: [
                        StepIndicator(current: step),
                        if (state.isOffline)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: InfoBanner(
                              message: 'Offline - your progress is saved on this device.',
                              icon: Icons.cloud_off,
                            ),
                          ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                            child: KeyedSubtree(key: ValueKey(step), child: _stepView(step)),
                          ),
                        ),
                      ],
                    ),
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _stepView(KycStep step) => switch (step) {
        KycStep.personalDetails => const PersonalDetailsStep(),
        KycStep.document => const DocumentStep(),
        KycStep.selfie => const SelfieStep(),
        KycStep.review => const ReviewStep(),
        KycStep.verification => VerificationStep(onViewProfile: () => setState(() => _showProfile = true)),
      };
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
