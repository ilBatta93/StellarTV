import 'package:flutter/material.dart';

import '../models/track_languages_policy.dart';
import '../services/title_tracks_service.dart';
import '../theme/app_theme.dart';

/// Audio and subtitle languages of a title: the tracks seen on this device
/// and, through [online], Italian subtitles found on the internet. Shows
/// nothing until something is known. Display only, never focused.
class TrackLanguageBadges extends StatefulWidget {
  /// The title, or every episode of a series.
  final List<String> ids;

  /// Asked once when the page opens; null hides the online badge.
  final Future<bool?> Function()? online;

  const TrackLanguageBadges({super.key, required this.ids, this.online});

  @override
  State<TrackLanguageBadges> createState() => _TrackLanguageBadgesState();
}

class _TrackLanguageBadgesState extends State<TrackLanguageBadges> {
  final _service = TitleTracksService.instance;
  bool? _online;

  @override
  void initState() {
    super.initState();
    _service.ensureLoaded();
    _askOnline();
  }

  Future<void> _askOnline() async {
    final ask = widget.online;
    if (ask == null) return;
    final available = await ask();
    if (mounted && available != null) setState(() => _online = available);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _service,
    builder: (context, _) {
      final tracks = widget.ids.length == 1
          ? _service.of(widget.ids.single)
          : _service.ofAll(widget.ids);
      final embeddedItalian = tracks.subtitles.contains('it');
      final badges = <Widget>[
        if (tracks.audio.isNotEmpty)
          _Badge(
            icon: Icons.audiotrack_rounded,
            label: 'Audio ${languagesLabel(tracks.audio)}',
            // A single language is information; several are the point.
            highlight: tracks.alternateAudio,
          ),
        if (tracks.subtitles.isNotEmpty)
          _Badge(
            icon: Icons.subtitles_rounded,
            label: 'Sottotitoli ${languagesLabel(tracks.subtitles)}',
            highlight: true,
          ),
        if (_online == true && !embeddedItalian)
          const _Badge(
            icon: Icons.cloud_download_outlined,
            label: 'Sottotitoli IT online',
            highlight: true,
          ),
      ];
      if (badges.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: badges),
      );
    },
  );
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;

  const _Badge({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.primary : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
          color: highlight ? color.withValues(alpha: 0.6) : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
