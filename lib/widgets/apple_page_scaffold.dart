import 'package:flutter/material.dart';
import '../services/device_type_service.dart';

/// A shared secondary-page shell. The body keeps its own scrolling and focus.
class ApplePageScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  const ApplePageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final tv = DeviceTypeService.isTv;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        toolbarHeight: tv ? 64 : 60,
        titleSpacing: tv ? 16 : 8,
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: tv ? 980 : 720),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tv ? 24 : 0),
              child: FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(),
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
