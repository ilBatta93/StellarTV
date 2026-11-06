import 'package:flutter/material.dart';

import '../services/vpn_service.dart';
import '../theme/app_theme.dart';
import 'auth_scaffold.dart';

/// Login shortcut to the optional personal VPN, with its current state, so
/// the VPN can be set up before the first connection. Android only.
class VpnLoginButton extends StatelessWidget {
  const VpnLoginButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (!VpnService.supported) return const SizedBox.shrink();
    final vpn = VpnService.instance;
    return ListenableBuilder(
      listenable: vpn,
      builder: (context, _) {
        final on = vpn.state == VpnState.connected;
        final text = !vpn.configured || !vpn.enabled
            ? 'VPN personale (facoltativa)'
            : on
            ? 'VPN attiva · ${vpn.label ?? ''}'
            : 'VPN non connessa';
        return AuthAction(
          onPressed: onPressed,
          child: TextButton.icon(
            onPressed: onPressed,
            icon: Icon(
              on ? Icons.vpn_lock_rounded : Icons.vpn_lock_outlined,
              color: on
                  ? AppColors.success
                  : vpn.enabled && vpn.configured
                  ? AppColors.error
                  : null,
            ),
            label: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
      },
    );
  }
}
