import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/poster_badges.dart';
import '../models/settings_preview_zone.dart';
import '../providers/ui_settings.dart';
import '../widgets/apple_page_scaffold.dart';
import '../widgets/settings_tiles.dart';
import 'settings_preview.dart';

/// Short summary for the settings tile: "4 di 6 attivi".
String posterBadgesSummary(UiSettings ui) {
  final on = [
    ui.showRatings,
    ui.badgeNew,
    ui.showQuality,
    ui.badgePlatform,
    ui.favoriteHeart,
    ui.posterProgress,
  ].where((v) => v).length;
  return '$on di 6 attivi';
}

/// What the catalog posters show, grouped by the corner each badge owns
/// (see [PosterSlot]), so the page reads like the poster itself.
class PosterBadgesScreen extends StatefulWidget {
  const PosterBadgesScreen({super.key});

  @override
  State<PosterBadgesScreen> createState() => _PosterBadgesScreenState();
}

class _PosterBadgesScreenState extends State<PosterBadgesScreen> {
  /// The catalog preview, lit on the corner of the badge under the focus.
  late final SettingsPreviewController _preview = SettingsPreviewController(
    context.read<UiSettings>(),
  )..point(PreviewZone.posterTopLeft);

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<UiSettings>();
    return ApplePageScaffold(
      title: 'Badge sulle locandine',
      body: SettingsPreviewLayout(
        controller: _preview,
        list: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            PreviewTarget(
              zone: PreviewZone.posterTopLeft,
              child: SettingsSection(
                title: 'In alto a sinistra',
                description: 'Uno sotto l\'altro, sempre nello stesso ordine.',
                children: [
                  SettingsSwitchTile(
                    icon: Icons.star_outline_rounded,
                    title: 'Voto',
                    value: ui.showRatings,
                    onChanged: ui.setShowRatings,
                  ),
                  SettingsValueTile(
                    icon: Icons.leaderboard_outlined,
                    title: 'Fonte del voto',
                    subtitle: ui.ratingSource.description,
                    value: ui.ratingSource.label,
                    onTap: () => pickWithPreview<RatingSource>(
                      context,
                      controller: _preview,
                      title: 'Fonte del voto',
                      options: RatingSource.values,
                      current: ui.ratingSource,
                      label: (s) => s.label,
                      detail: (s) => s.description,
                      apply: (settings, s) => settings.setRatingSource(s),
                    ),
                  ),
                  SettingsSwitchTile(
                    icon: Icons.fiber_new_outlined,
                    title: 'Nuovo',
                    subtitle:
                        'Sui titoli aggiunti dalla sorgente negli ultimi '
                        '$newBadgeDays giorni',
                    value: ui.badgeNew,
                    onChanged: ui.setBadgeNew,
                  ),
                ],
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.posterTopRight,
              child: SettingsSection(
                title: 'In alto a destra',
                children: [
                  SettingsSwitchTile(
                    icon: Icons.favorite_border_rounded,
                    title: 'Cuore su tutte le locandine',
                    subtitle: 'Spento, resta solo sui titoli già nei preferiti',
                    value: ui.favoriteHeart,
                    onChanged: ui.setFavoriteHeart,
                  ),
                ],
              ),
            ),
            PreviewTarget(
              zone: PreviewZone.posterBottom,
              child: SettingsSection(
                title: 'In basso',
                description:
                    'Con i titoli sulla locandina questi badge stanno subito '
                    'sopra il titolo.',
                children: [
                  SettingsSwitchTile(
                    icon: Icons.hd_outlined,
                    title: 'Qualità',
                    subtitle: '4K, FHD, HD a sinistra',
                    value: ui.showQuality,
                    onChanged: ui.setShowQuality,
                  ),
                  SettingsSwitchTile(
                    icon: Icons.live_tv_outlined,
                    title: 'Piattaforma',
                    subtitle:
                        'Accanto alla qualità, quando è già nota su questo '
                        'dispositivo',
                    value: ui.badgePlatform,
                    onChanged: ui.setBadgePlatform,
                  ),
                  SettingsSwitchTile(
                    icon: Icons.task_alt_rounded,
                    title: 'Avanzamento',
                    subtitle:
                        'Barra sul bordo dei titoli iniziati, spunta a destra '
                        'sui titoli visti',
                    value: ui.posterProgress,
                    onChanged: ui.setPosterProgress,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
