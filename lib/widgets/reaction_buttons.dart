import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tmdb_item.dart';
import '../providers/reactions_provider.dart';
import '../theme/app_theme.dart';
import 'tv_focusable.dart';

class ReactionButtons extends StatelessWidget {
  final TmdbItem item;
  const ReactionButtons({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    final reactions = context.watch<ReactionsProvider>();
    final vote = reactions.vote(item);
    Widget command(int value, IconData icon, String label) => TvFocusable(
      onPressed: () => reactions.setVote(item, value),
      child: IconButton(
        tooltip: label,
        isSelected: vote == value,
        onPressed: () => reactions.setVote(item, value),
        icon: Icon(
          icon,
          color: vote == value ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        command(1, Icons.thumb_up_alt_rounded, 'Mi piace'),
        command(-1, Icons.thumb_down_alt_rounded, 'Non mi piace'),
      ],
    );
  }
}
