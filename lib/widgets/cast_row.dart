import 'package:flutter/material.dart';
import '../models/tmdb_person.dart';
import '../screens/person_detail_screen.dart';
import '../theme/app_theme.dart';
import 'poster_card.dart';
import 'section_row.dart';

/// Horizontal list of cast members; tapping one opens the person page.
class CastRow extends StatelessWidget {
  final List<TmdbPerson> cast;

  const CastRow({super.key, required this.cast});

  @override
  Widget build(BuildContext context) {
    if (cast.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Cast',
          subtitle: 'Tocca un attore per saperne di più',
        ),
        HorizontalRow(
          height: 160,
          itemCount: cast.length,
          itemBuilder: (context, i) {
            final person = cast[i];
            return Pressable(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PersonDetailScreen(person: person),
                ),
              ),
              child: SizedBox(
                width: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(48),
                        child: person.profileUrl.isNotEmpty
                            ? Image.network(
                                person.profileUrl,
                                cacheWidth: 256,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _fallback(person),
                              )
                            : _fallback(person),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (person.character != null)
                      Text(
                        person.character!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _fallback(TmdbPerson person) => Container(
    color: AppColors.card,
    alignment: Alignment.center,
    child: Text(
      person.name.isNotEmpty ? person.name[0].toUpperCase() : '?',
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
