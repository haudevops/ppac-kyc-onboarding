import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/presentation/ui_message.dart';
import '../../../../core/presentation/widgets.dart';
import '../../../../core/utils/auth_validators.dart';
import '../bloc/auth_bloc.dart';

/// Login and registration on one screen (toggle at the bottom).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  bool _registerMode = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bloc = context.read<AuthBloc>();
    if (_registerMode) {
      bloc.add(AuthRegisterRequested(email: _email.text, password: _password.text, fullName: _fullName.text));
    } else {
      bloc.add(AuthLoginRequested(email: _email.text, password: _password.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, curr) => prev.isSubmitting && !curr.isSubmitting && curr.errorMessage != null,
      listener: (context, state) => showUiMessage(context, UiMessage.error(state.errorMessage!)),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.verified_user_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        _registerMode ? 'Create your account' : 'Welcome back',
                        style: textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Verify your identity in a few minutes.',
                        style: textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      BlocBuilder<AuthBloc, AuthState>(
                        buildWhen: (p, c) => p.sessionExpired != c.sessionExpired,
                        builder: (context, state) => state.sessionExpired
                            ? const Padding(
                                padding: EdgeInsets.only(bottom: 16),
                                child: InfoBanner(
                                  message: 'Your session has expired. Please log in again - your progress is saved.',
                                  icon: Icons.lock_clock_outlined,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      if (_registerMode) ...[
                        TextFormField(
                          controller: _fullName,
                          decoration: const InputDecoration(labelText: 'Full name (optional)'),
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          textInputAction: TextInputAction.next,
                          validator: AuthValidators.optionalName,
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        validator: AuthValidators.email,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          helperText: _registerMode ? '8+ characters with upper, lower case and a digit' : null,
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        autofillHints: [_registerMode ? AutofillHints.newPassword : AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        validator: _registerMode ? AuthValidators.newPassword : AuthValidators.loginPassword,
                      ),
                      const SizedBox(height: 24),
                      BlocBuilder<AuthBloc, AuthState>(
                        buildWhen: (p, c) => p.isSubmitting != c.isSubmitting,
                        builder: (context, state) => PrimaryButton(
                          label: _registerMode ? 'Create account' : 'Log in',
                          loading: state.isSubmitting,
                          onPressed: _submit,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => setState(() {
                          _registerMode = !_registerMode;
                          _formKey.currentState?.reset();
                        }),
                        child: Text(_registerMode ? 'Already have an account? Log in' : 'New here? Create an account'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
