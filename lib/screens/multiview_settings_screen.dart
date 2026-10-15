import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/multiview_layout.dart';
import '../providers/ui_settings.dart';
import '../widgets/apple_page_scaffold.dart';
import '../widgets/settings_tiles.dart';

class MultiViewSettingsScreen extends StatelessWidget {
  const MultiViewSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final ui = context.watch<UiSettings>();
    return ApplePageScaffold(
      title: 'MultiView',
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SettingsSection(
            title: 'Riquadri',
            children: [
              SettingsValueTile(
                icon: Icons.dashboard_customize_outlined,
                title: 'Disposizione',
                value: ui.multiViewLayout.label,
                onTap: () async {
                  final layout = await pickOption(
                    context,
                    title: 'Disposizione',
                    options: MultiViewLayout.values,
                    current: ui.multiViewLayout,
                    label: (layout) => layout.label,
                  );
                  if (layout != null) await ui.setMultiViewLayout(layout);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
