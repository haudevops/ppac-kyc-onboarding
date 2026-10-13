import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/countries.dart';
import '../../../../core/presentation/widgets.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/widgets/logout_dialog.dart';
import '../../../kyc/domain/entities/kyc_application.dart';
import '../../../kyc/domain/entities/kyc_enums.dart';
import '../../../kyc/domain/repositories/kyc_repository.dart';
import '../cubit/profile_cubit.dart';
import '../widgets/photo_viewer_page.dart';
import '../widgets/remote_photo.dart';

/// Home screen of a verified user: identity data exactly as approved by the backend.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ProfileCubit(repository: context.read<KycRepository>())..load(),
      child: _ProfileView(user: user),
    );
  }
}

class _ProfileView extends StatefulWidget {
  const _ProfileView({required this.user});

  final User user;

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> with WidgetsBindingObserver {
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

  /// Photo URLs are short-lived: renew them when the user comes back to the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) context.read<ProfileCubit>().refreshIfStale();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => confirmLogout(context, message: 'You can log back in at any time.'),
          ),
        ],
      ),
      body: BlocConsumer<ProfileCubit, ProfileState>(
        listenWhen: (p, c) => c.message != null && p.message != c.message,
        listener: (context, state) => showUiMessage(context, state.message!),
        builder: (context, state) {
          final cubit = context.read<ProfileCubit>();
          final application = state.application;
          if (application == null) {
            return state.status == ProfileStatus.failure
                ? _ErrorView(message: state.errorMessage ?? 'Could not load your profile.', onRetry: cubit.load)
                : const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: cubit.load,
            child: _ProfileContent(user: widget.user, application: application),
          );
        },
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.user, required this.application});

  final User user;
  final KycApplication application;

  @override
  Widget build(BuildContext context) {
    final d = application.details;
    final urls = application.documentUrls;
    final isPassport = d.idType == IdType.passport;
    String? date(DateTime? v) => v == null ? null : formatDisplayDate(v);
    String? dateTime(DateTime? v) => v == null ? null : formatDisplayDateTime(v);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _ProfileHeader(
          name: d.fullName ?? user.displayName,
          email: user.email,
          selfieUrl: urls[DocumentType.selfie],
          verifiedAt: application.reviewedAt,
        ),
        const SizedBox(height: 16),
        _InfoCard(
          title: 'Personal information',
          icon: Icons.person_outline,
          rows: {
            'Full name': d.fullName,
            'Date of birth': date(d.dateOfBirth),
            'Gender': d.gender?.label,
            'Nationality': d.nationality == null ? null : countryName(d.nationality),
            'Phone': d.phoneNumber,
            'Email': user.email,
          },
        ),
        _InfoCard(
          title: 'Identity document',
          icon: Icons.badge_outlined,
          rows: {
            'Type': d.idType?.label,
            'Number': d.idNumber,
            'Issued': date(d.idIssueDate),
            'Expires': date(d.idExpiryDate),
          },
          footer: Row(
            children: [
              for (final type in [DocumentType.idFront, if (!isPassport) DocumentType.idBack])
                if (urls[type] != null)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _DocumentThumb(
                        url: urls[type]!,
                        label: isPassport ? 'Photo page' : type.label,
                      ),
                    ),
                  ),
            ],
          ),
        ),
        _InfoCard(
          title: 'Address',
          icon: Icons.home_outlined,
          rows: {
            'Address': [d.addressLine1, d.addressLine2].whereType<String>().join(', '),
            'City': d.city,
            'State / province': d.stateProvince,
            'Postal code': d.postalCode,
            'Country': d.country == null ? null : countryName(d.country),
          },
        ),
        _InfoCard(
          title: 'Verification',
          icon: Icons.verified_outlined,
          rows: {
            'Status': 'Approved',
            'Submitted': dateTime(application.submittedAt),
            'Approved': dateTime(application.reviewedAt),
            'Reference': _shortReference(application.id),
          },
        ),
        const SizedBox(height: 8),
        Text(
          'For your security your ID number is partially hidden. '
          'To change verified information, please contact support.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      ],
    );
  }
}

String? _shortReference(String? id) {
  if (id == null) return null;
  return (id.length > 8 ? id.substring(0, 8) : id).toUpperCase();
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.name, required this.email, this.selfieUrl, this.verifiedAt});

  final String name;
  final String email;
  final String? selfieUrl;
  final DateTime? verifiedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initials = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            GestureDetector(
              onTap: selfieUrl == null ? null : () => PhotoViewerPage.open(context, url: selfieUrl!, title: 'Selfie'),
              child: Hero(
                tag: selfieUrl ?? 'avatar',
                child: ClipOval(
                  child: SizedBox.square(
                    dimension: 104,
                    child: selfieUrl == null
                        ? _Initials(initials: initials)
                        : RemotePhoto(
                            url: selfieUrl!,
                            fallback: _Initials(initials: initials),
                            onRetry: context.read<ProfileCubit>().load,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(name, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(email, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded, size: 18, color: Colors.green.shade700),
                  const SizedBox(width: 6),
                  Text(
                    verifiedAt == null ? 'Identity verified' : 'Verified on ${formatDisplayDate(verifiedAt!.toLocal())}',
                    style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.primaryContainer,
      child: Center(
        child: Text(
          initials.isEmpty ? '?' : initials.toUpperCase(),
          style: TextStyle(fontSize: 36, fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.icon, required this.rows, this.footer});

  final String title;
  final IconData icon;
  final Map<String, String?> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = rows.entries.where((e) => e.value != null && e.value!.trim().isNotEmpty);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            for (final row in visible)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(row.key, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                    ),
                    Expanded(child: SelectableText(row.value!, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            if (footer != null) ...[const SizedBox(height: 8), footer!],
          ],
        ),
      ),
    );
  }
}

class _DocumentThumb extends StatelessWidget {
  const _DocumentThumb({required this.url, required this.label});

  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => PhotoViewerPage.open(context, url: url, title: label),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Hero(
            tag: url,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1.586,
                child: RemotePhoto(url: url, onRetry: context.read<ProfileCubit>().load),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

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
