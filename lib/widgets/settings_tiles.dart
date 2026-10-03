import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SettingsSection extends StatelessWidget {
  final String title;
  final String? description;
  final List<Widget> children;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(title.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                )),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(description!,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13, height: 1.5)),
            ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 56, color: AppColors.border),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EngineBadge extends StatelessWidget {
  final String label;
  const EngineBadge(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(
              color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

Widget _title(String title, String? badge) => Row(
      children: [
        Flexible(child: Text(title, style: const TextStyle(fontSize: 15))),
        if (badge != null) EngineBadge(badge),
      ],
    );

Widget? _subtitle(String? text) => text == null
    ? null
    : Text(text,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4));

class SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? badge;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppColors.textSecondary),
      title: _title(title, badge),
      subtitle: _subtitle(subtitle),
      value: value,
      activeThumbColor: Colors.white,
      activeTrackColor: AppColors.primary,
      onChanged: onChanged,
    );
  }
}

class SettingsValueTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final String? subtitle;
  final String? badge;
  final Color? color;
  final VoidCallback? onTap;

  const SettingsValueTile({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.subtitle,
    this.badge,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.textSecondary),
      title: color == null
          ? _title(title, badge)
          : Text(title, style: TextStyle(fontSize: 15, color: color)),
      subtitle: _subtitle(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
          if (onTap != null && color == null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

class SettingsSliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? badge;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  const SettingsSliderTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
    this.subtitle,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.textSecondary),
              const SizedBox(width: 16),
              Expanded(child: _title(title, badge)),
              Text(format(value),
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w600)),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 4),
              child: _subtitle(subtitle),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              activeColor: AppColors.primary,
              inactiveColor: AppColors.border,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

Future<T?> pickOption<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required T current,
  required String Function(T) label,
  String? Function(T)? detail,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      title: Text(label(o),
                          style: TextStyle(
                            color: o == current
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontWeight:
                                o == current ? FontWeight.w600 : FontWeight.w400,
                          )),
                      subtitle: _subtitle(detail?.call(o)),
                      trailing: o == current
                          ? const Icon(Icons.check_rounded, color: AppColors.primary)
                          : null,
                      onTap: () => Navigator.pop(ctx, o),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
