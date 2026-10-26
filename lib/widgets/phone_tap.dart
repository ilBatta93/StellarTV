import 'package:flutter/material.dart';

import '../services/device_type_service.dart';

/// Touch target for a control whose activation on TV is only the remote.
/// On a phone the child receives the tap. On TV the child is unchanged.
class PhoneTap extends StatelessWidget {
  const PhoneTap({
    super.key,
    required this.onTap,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  final VoidCallback onTap;
  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    if (DeviceTypeService.isTv) return child;
    return Material(
      color: const Color(0x00000000),
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: child,
      ),
    );
  }
}
