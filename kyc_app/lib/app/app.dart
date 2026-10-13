import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/config/app_config.dart';
import '../core/security/privacy_overlay.dart';
import '../features/auth/domain/repositories/auth_repository.dart';
import '../features/auth/presentation/bloc/auth_bloc.dart';
import '../features/auth/presentation/pages/login_page.dart';
import '../features/auth/presentation/pages/splash_page.dart';
import '../features/kyc/domain/repositories/kyc_repository.dart';
import '../features/kyc/presentation/pages/kyc_flow_page.dart';
import 'dependencies.dart';
import 'theme.dart';

class KycApp extends StatelessWidget {
  const KycApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppConfig>.value(value: dependencies.config),
        RepositoryProvider<AuthRepository>.value(value: dependencies.authRepository),
        RepositoryProvider<KycRepository>.value(value: dependencies.kycRepository),
      ],
      child: BlocProvider(
        create: (context) => AuthBloc(
          repository: context.read<AuthRepository>(),
          clearUserData: context.read<KycRepository>().clearLocalDraft,
        )..add(const AuthSessionCheckRequested()),
        child: const _AppView(),
      ),
    );
  }
}

class _AppView extends StatefulWidget {
  const _AppView();

  @override
  State<_AppView> createState() => _AppViewState();
}

class _AppViewState extends State<_AppView> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KYC Onboarding',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: (context, child) => PrivacyOverlay(
        enabled: context.read<AppConfig>().protectScreen,
        child: BlocListener<AuthBloc, AuthState>(
          listenWhen: (p, c) => p.status != c.status,
          // On logout / session expiry close any pushed route (e.g. the camera).
          listener: (context, state) => _navigatorKey.currentState?.popUntil((route) => route.isFirst),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: BlocBuilder<AuthBloc, AuthState>(
        buildWhen: (p, c) => p.status != c.status || p.user?.id != c.user?.id,
        builder: (context, state) => switch (state.status) {
          AuthStatus.unknown => const SplashPage(),
          AuthStatus.unauthenticated => const LoginPage(),
          // Keyed by user so switching accounts creates a fresh KycBloc.
          AuthStatus.authenticated => KycFlowPage(key: ValueKey(state.user!.id), user: state.user!),
        },
      ),
    );
  }
}
