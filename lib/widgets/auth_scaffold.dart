import 'package:flutter/material.dart';

import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import 'brand_logo.dart';
import 'tv_focusable.dart';

/// Presentation-only shell shared by account and Xtream access.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.form,
    this.alternatives,
  });
  final String title;
  final String subtitle;
  final Widget form;
  final Widget? alternatives;

  @override
  Widget build(BuildContext context) {
    final tv = DeviceTypeService.isTv;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = tv && constraints.maxWidth >= 760;
            final identity = Column(
              crossAxisAlignment: wide
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: BrandLogo(size: 54),
                ),
                SizedBox(height: wide ? 32 : 28),
                Text(
                  title,
                  textAlign: wide ? TextAlign.left : TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: tv ? 28 : 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  textAlign: wide ? TextAlign.left : TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                if (wide && alternatives != null) ...[
                  const SizedBox(height: 32),
                  alternatives ?? const SizedBox.shrink(),
                ],
              ],
            );
            final fields = AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  form,
                  if (!wide && alternatives != null) ...[
                    const SizedBox(height: 24),
                    const Divider(color: AppColors.border),
                    const SizedBox(height: 16),
                    alternatives ?? const SizedBox.shrink(),
                  ],
                ],
              ),
            );
            return FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: tv ? 44 : 24,
                  vertical: tv ? 24 : 32,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - (tv ? 48 : 64)).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: wide ? 1040 : 440),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(child: identity),
                                const SizedBox(width: 80),
                                Expanded(child: fields),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                identity,
                                const SizedBox(height: 32),
                                fields,
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One remote focus stop per button, with existing native touch activation.
class AuthAction extends StatelessWidget {
  const AuthAction({super.key, required this.onPressed, required this.child});
  final VoidCallback? onPressed;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final action = onPressed;
    if (action == null) return ExcludeFocus(child: child);
    return TvFocusable(
      onPressed: action,
      borderRadius: BorderRadius.circular(24),
      child: child,
    );
  }
}
