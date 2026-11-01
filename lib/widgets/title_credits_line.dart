import 'package:flutter/material.dart';

import '../models/tmdb_person.dart';
import '../models/title_credits.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';

/// "Regia di …", length and original title under the title chips.
/// Read-only text: the people are reachable from the cast row.
class TitleCreditsLine extends StatelessWidget {
  final List<TmdbPerson> directors;
  final TitleInfo info;
  final bool movie;

  /// Title shown on the page: an original title it already contains is
  /// not repeated.
  final String? title;

  const TitleCreditsLine({
    super.key,
    required this.directors,
    required this.info,
    required this.movie,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final tv = DeviceTypeService.isTv;
    final makers = directors.isNotEmpty ? directors : info.creators;
    final runtime = info.runtime;
    final facts = [
      if (runtime != null)
        movie ? formatRuntime(runtime) : 'Episodi da ${formatRuntime(runtime)}',
      if (info.originalTitle case final original?
          when !(title ?? '').toLowerCase().contains(original.toLowerCase()))
        'Titolo originale: $original',
    ];
    if (makers.isEmpty && facts.isEmpty) return const SizedBox.shrink();
    final base = TextStyle(
      color: AppColors.textSecondary,
      fontSize: tv ? 16 : 13,
      height: 1.35,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            if (makers.isNotEmpty) ...[
              TextSpan(text: directors.isNotEmpty ? 'Regia di ' : 'Ideata da '),
              TextSpan(
                text: joinNames(makers),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (facts.isNotEmpty) const TextSpan(text: '  ·  '),
            ],
            TextSpan(text: facts.join('  ·  ')),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Plot block shared by title pages. On TV the text stays on the dark
/// side of the backdrop instead of running over the picture.
class TitlePlot extends StatelessWidget {
  final String plot;
  final String? tagline;

  const TitlePlot({super.key, required this.plot, this.tagline});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final tv = DeviceTypeService.isTv;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: tv ? 560 : double.infinity),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trama', style: theme.titleMedium),
          const SizedBox(height: 8),
          if (tagline case final line?) ...[
            Text(
              line,
              style: theme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(plot, style: theme.bodyMedium),
        ],
      ),
    );
  }
}
