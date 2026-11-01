import '../services/image_cache_service.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/tmdb_person.dart';
import '../screens/person_detail_screen.dart';
import '../theme/app_theme.dart';
import '../services/device_type_service.dart';
import 'poster_card.dart';
import 'section_row.dart';

/// Horizontal list of people (directors first, then cast); tapping one
/// opens the person page with their titles.
class CastRow extends StatelessWidget {
  final List<TmdbPerson> cast;
  final String title;

  const CastRow({super.key, required this.cast, this.title = 'Cast'});

  @override
  Widget build(BuildContext context) {
    if (cast.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          subtitle: DeviceTypeService.isTv
              ? 'Seleziona una persona per vedere i suoi titoli'
              : 'Tocca una persona per vedere i suoi titoli',
        ),
        HorizontalRow(
          height: 160,
          itemCount: cast.length,
          itemBuilder: (context, i) {
            final person = cast[i];
            final tv = DeviceTypeService.isTv;
            return Pressable(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PersonDetailScreen(person: person),
                ),
              ),
              // TV: inner margin keeps the focus ring off the photo and name.
              child: Container(
                width: 96,
                padding: EdgeInsets.all(tv ? 6 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(48),
                        child: person.profileUrl.isNotEmpty
                            ? CachedNetworkImage(
                                cacheManager: AppImageCache.manager,
                                imageUrl: person.profileUrl,
                                fadeInDuration: const Duration(
                                  milliseconds: 150,
                                ),
                                memCacheWidth: 256,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => _fallback(person),
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
