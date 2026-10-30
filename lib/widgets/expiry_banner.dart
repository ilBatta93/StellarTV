import 'package:flutter/material.dart';

import '../screens/xtream_account_screen.dart';
import '../services/device_type_service.dart';
import '../services/expiry_reminder_service.dart';
import '../theme/app_theme.dart';
import 'tv_focusable.dart';

/// Discreet Home notice shown when the subscription enters a chosen reminder
/// window. Renders nothing otherwise.
class ExpiryBanner extends StatelessWidget {
  const ExpiryBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = ExpiryReminderService.instance;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        if (!svc.showBanner) return const SizedBox.shrink();
        final t = svc.activeThreshold!;
        final left = svc.expiry!.difference(DateTime.now());
        final text = left.isNegative
            ? 'Il tuo accesso è scaduto.'
            : left.inHours < 24
            ? 'Il tuo accesso scade oggi.'
            : 'Il tuo accesso scade tra ${(left.inHours / 24).ceil()} giorni.';
        final tv = DeviceTypeService.isTv;
        Widget button(String label, VoidCallback onTap) => tv
            ? TvFocusable(
                onPressed: onTap,
                focusedScale: 1,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            : TextButton(onPressed: onTap, child: Text(label));
        return Container(
          key: ValueKey('expiry-$t'),
          margin: EdgeInsets.fromLTRB(tv ? 48 : 16, 8, tv ? 48 : 16, 8),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.event_busy_rounded,
                color: AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
              button(
                'Dettagli',
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const XtreamAccountScreen(),
                  ),
                ),
              ),
              button('Più tardi', svc.dismissBanner),
            ],
          ),
        );
      },
    );
  }
}
