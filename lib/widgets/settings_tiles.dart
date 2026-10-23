import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import 'tv_focusable.dart';

/// TV: one focus stop per settings row with the orange focus ring, scrolled
/// into view; the row's own controls never take the focus. Touch: unchanged.
Widget tvSettingsRow({required Widget child, VoidCallback? onPressed}) {
  if (!DeviceTypeService.isTv || onPressed == null) return child;
  return TvFocusable(
    onPressed: onPressed,
    focusedScale: 1,
    borderRadius: BorderRadius.circular(12),
    child: child,
  );
}

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
            child: Text(
              title,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: DeviceTypeService.isTv ? 16 : 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                description!,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          // A Material (not a coloured Container) so the focus/tap highlight of
          // the tiles is painted on top of the card and visible with a remote.
          Material(
            color: AppColors.glass,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      indent: 56,
                      color: AppColors.border,
                    ),
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
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Widget _title(String title, String? badge) => Row(
  children: [
    Flexible(
      child: Text(
        title,
        style: TextStyle(
          fontSize: DeviceTypeService.isTv ? 17 : 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    if (badge != null) EngineBadge(badge),
  ],
);

Widget? _subtitle(String? text) => text == null
    ? null
    : Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          height: 1.4,
        ),
      );

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
    return tvSettingsRow(
      onPressed: () => onChanged(!value),
      child: SwitchListTile(
        secondary: Icon(icon, color: AppColors.textSecondary),
        title: _title(title, badge),
        subtitle: _subtitle(subtitle),
        value: value,
        activeThumbColor: AppColors.textPrimary,
        activeTrackColor: AppColors.primary,
        onChanged: onChanged,
      ),
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
    return tvSettingsRow(
      onPressed: onTap,
      child: ListTile(
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
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            if (onTap != null && color == null) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ],
        ),
        onTap: onTap,
      ),
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
    final content = _content();
    if (!DeviceTypeService.isTv) return content;
    final step = divisions > 0 ? (max - min) / divisions : (max - min) / 20;
    return _TvSliderFocus(
      onStep: (direction) {
        final next = (value + step * direction).clamp(min, max).toDouble();
        if (next != value) onChanged(next);
      },
      child: ExcludeFocus(child: content),
    );
  }

  Widget _content() {
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
              Text(
                format(value),
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
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

/// TV: Left/Right change the value, Up/Down move to the next setting
/// (the plain slider used Up/Down to change the value too, so the remote
/// could not leave it).
class _TvSliderFocus extends StatefulWidget {
  final Widget child;
  final ValueChanged<int> onStep;
  const _TvSliderFocus({required this.child, required this.onStep});

  @override
  State<_TvSliderFocus> createState() => _TvSliderFocusState();
}

class _TvSliderFocusState extends State<_TvSliderFocus> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onStep(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onStep(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _onKey,
      onFocusChange: (value) {
        setState(() => _focused = value);
        if (value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_focused) return;
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 120),
              alignment: 0.5,
            );
          });
        }
      },
      child: Container(
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _focused ? AppColors.textPrimary : AppColors.clear,
            width: 3,
          ),
        ),
        child: widget.child,
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
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(ctx).size.height * 0.8,
      ),
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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final o in options)
                      _tvOption(
                        autofocus: o == current,
                        onPressed: () => Navigator.pop(ctx, o),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                          ),
                          title: Text(
                            label(o),
                            style: TextStyle(
                              color: o == current
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontWeight: o == current
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          subtitle: _subtitle(detail?.call(o)),
                          trailing: o == current
                              ? Icon(
                                  Icons.check_rounded,
                                  color: AppColors.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(ctx, o),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// TV: list option with focus ring; the current choice is highlighted as
/// soon as the list opens.
Widget _tvOption({
  required bool autofocus,
  required VoidCallback onPressed,
  required Widget child,
}) {
  if (!DeviceTypeService.isTv) return child;
  return TvFocusable(
    autofocus: autofocus,
    onPressed: onPressed,
    focusedScale: 1,
    borderRadius: BorderRadius.circular(10),
    child: child,
  );
}

/// TV: an informational row that still takes one focus stop, so the remote
/// can scroll through long read-only lists (results, events). Touch: plain.
class TvInfoRow extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final bool isThreeLine;
  const TvInfoRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.isThreeLine = false,
  });

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      isThreeLine: isThreeLine,
    );
    if (!DeviceTypeService.isTv) return tile;
    return TvFocusable(
      onPressed: () {},
      focusedScale: 1,
      borderRadius: BorderRadius.circular(12),
      child: tile,
    );
  }
}
