import 'package:flutter/material.dart';

/// Covers the UI whenever the app is not in the foreground, so the snapshot the OS takes for
/// the app switcher never contains PII (names, ID numbers, document photos).
class PrivacyOverlay extends StatefulWidget {
  const PrivacyOverlay({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<PrivacyOverlay> createState() => _PrivacyOverlayState();
}

class _PrivacyOverlayState extends State<PrivacyOverlay> with WidgetsBindingObserver {
  bool _obscured = false;

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.enabled) return;
    final obscure = state != AppLifecycleState.resumed;
    if (obscure != _obscured) setState(() => _obscured = obscure);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        widget.child,
        if (_obscured)
          Positioned.fill(
            child: ColoredBox(
              color: scheme.surface,
              child: Center(
                // Same artwork as the launcher icon (assets/images/app_logo.png).
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    width: 96,
                    height: 96,
                    cacheWidth: 288,
                    errorBuilder: (_, _, _) => Icon(Icons.verified_user_rounded, size: 72, color: scheme.primary),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
