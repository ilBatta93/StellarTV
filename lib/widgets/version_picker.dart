import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../theme/app_theme.dart';
import 'tv_focusable.dart';

/// Copies of one live channel or film in different qualities ("HD",
/// "Full HD", "4K"...). Returns the one picked; the caller remembers it.
Future<Channel?> showVersionPicker(
  BuildContext context, {
  required List<Channel> versions,
  required String currentId,
  required String? Function(Channel) labelOf,
  String? title,
  String? extraLabel,
  VoidCallback? onExtra,
}) async {
  final picked = await showDialog<Object>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Versione di ${title ?? versions.first.name}'),
      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in versions)
                _VersionTile(
                  channel: c,
                  quality: labelOf(c),
                  current: c.id == currentId,
                  onPressed: () => Navigator.pop(ctx, c),
                ),
              if (extraLabel != null && onExtra != null)
                _VersionTile.action(
                  label: extraLabel,
                  onPressed: () => Navigator.pop(ctx, _extra),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annulla'),
        ),
      ],
    ),
  );
  if (identical(picked, _extra)) {
    onExtra?.call();
    return null;
  }
  return picked is Channel ? picked : null;
}

const _extra = Object();

class _VersionTile extends StatelessWidget {
  const _VersionTile({
    required Channel this.channel,
    required this.quality,
    required this.current,
    required this.onPressed,
  }) : label = null;

  const _VersionTile.action({
    required String this.label,
    required this.onPressed,
  }) : channel = null,
       quality = null,
       current = false;

  final Channel? channel;
  final String? label;
  final String? quality;
  final bool current;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = channel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TvFocusable(
        autofocus: current,
        focusedScale: 1,
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: current
                      ? const Icon(Icons.check_rounded, size: 20)
                      : null,
                ),
                if (quality case final quality?) ...[
                  QualityChip(quality),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    c?.name ?? label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c == null
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small quality tag shown next to a grouped channel or film.
class QualityChip extends StatelessWidget {
  const QualityChip(this.label, {super.key, this.count});
  final String label;

  /// Number of versions, shown as "×N" when set.
  final int? count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(
      count == null ? label : '$label ×$count',
      maxLines: 1,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
