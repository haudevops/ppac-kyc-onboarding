import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth_bloc.dart';

/// Asks for confirmation, then logs out (shared by the KYC wizard and the profile screen).
Future<void> confirmLogout(BuildContext context, {String? message}) async {
  final authBloc = context.read<AuthBloc>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Log out?'),
      content: Text(
        message ??
            'Unsubmitted progress stored on this device will be removed. '
                'Details already synced to your account are kept.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out')),
      ],
    ),
  );
  if (confirmed ?? false) authBloc.add(const AuthLogoutRequested());
}
