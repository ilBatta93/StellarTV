import 'package:flutter/material.dart';

import '../../models/player_settings.dart';
import '../../player/playback_engine.dart';
import '../../player/playback_session.dart';
import '../../theme/app_theme.dart';
import '../../services/device_type_service.dart';
import '../tv_focusable.dart';
import 'player_format.dart';

Future<void> _showSheet(
  BuildContext context,
  String title,
  Widget Function(BuildContext sheetContext) builder,
) {
  final previousFocus = FocusManager.instance.primaryFocus;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                title,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            Flexible(child: builder(sheetContext)),
            const SizedBox(height: 8),
          ],
        ),
      ),
      ),
    ),
  ).whenComplete(() {
    if (previousFocus?.context != null) previousFocus?.requestFocus();
  });
}

class _Option extends StatelessWidget {
  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? AppColors.primary : AppColors.textPrimary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: detail == null || detail!.isEmpty
          ? null
          : Text(
              detail!,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
      trailing: selected
          ? Icon(Icons.check_rounded, color: AppColors.primary)
          : null,
      onTap: onTap,
    );
    if (!DeviceTypeService.isTv) return tile;
    return TvFocusable(onPressed: onTap, child: tile);
  }
}

class _Unsupported extends StatelessWidget {
  final String message;
  final PlaybackSession session;

  const _Unsupported({required this.message, required this.session});

  @override
  Widget build(BuildContext context) {
    final current = session.engine?.type;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          if (current == PlayerEngineType.exo) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Passa a mpv'),
              onPressed: () {
                Navigator.pop(context);
                session.switchEngine(PlayerEngineType.mediakit);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _TrackList extends StatelessWidget {
  final Future<List<MediaTrack>> tracks;
  final String emptyMessage;
  final String? noneLabel;
  final ValueChanged<MediaTrack?> onSelect;

  const _TrackList({
    required this.tracks,
    required this.emptyMessage,
    required this.onSelect,
    this.noneLabel,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MediaTrack>>(
      future: tracks,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Text(
              'Impossibile leggere le tracce di questo flusso.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        final list = snap.data ?? const [];
        final anySelected = list.any((t) => t.selected);
        return ListView(
          shrinkWrap: true,
          children: [
            if (noneLabel != null)
              _Option(
                label: noneLabel!,
                selected: !anySelected,
                onTap: () {
                  Navigator.pop(context);
                  onSelect(null);
                },
              ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Text(
                  emptyMessage,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            for (final t in list)
              _Option(
                label: t.label,
                detail: t.detail,
                selected: t.selected,
                onTap: () {
                  Navigator.pop(context);
                  onSelect(t);
                },
              ),
          ],
        );
      },
    );
  }
}

Future<void> showAudioSheet(BuildContext context, PlaybackSession session) {
  final engine = session.engine;
  return _showSheet(context, 'Traccia audio', (ctx) {
    if (engine == null || !engine.supportsAudioTracks) {
      return _Unsupported(
        message:
            'Questo dispositivo non permette di cambiare traccia audio con ExoPlayer.',
        session: session,
      );
    }
    return _TrackList(
      tracks: engine.getAudioTracks(),
      emptyMessage: 'Questo flusso ha una sola traccia audio.',
      onSelect: (t) {
        if (t != null && identical(session.engine, engine)) {
          engine.selectAudioTrack(t);
        }
      },
    );
  });
}

Future<void> showSubtitleSheet(
  BuildContext context,
  PlaybackSession session, {
  bool onlineActive = false,
  bool onlineLoading = false,
  VoidCallback? onLoadOnline,
  VoidCallback? onDisableOnline,
}) {
  final engine = session.engine;
  return _showSheet(context, 'Sottotitoli', (ctx) {
    final onlineOption = _Option(
      label: 'Italiano (OpenSubtitles)',
      detail: onlineLoading
          ? 'Ricerca in corso...'
          : onlineActive
          ? 'Attivi, scaricati da internet'
          : 'Scaricati da internet, in italiano',
      selected: onlineActive,
      onTap: onlineActive || onlineLoading
          ? () {}
          : () {
              Navigator.pop(ctx);
              onLoadOnline?.call();
            },
    );
    if (onlineActive) {
      return ListView(
        shrinkWrap: true,
        children: [
          onlineOption,
          _Option(
            label: 'Disattivati',
            selected: false,
            onTap: () {
              Navigator.pop(ctx);
              onDisableOnline?.call();
            },
          ),
        ],
      );
    }
    if (engine == null || !engine.supportsSubtitleTracks) {
      return ListView(
        shrinkWrap: true,
        children: [
          onlineOption,
          _Unsupported(
            message:
                'ExoPlayer non mostra i sottotitoli incorporati nei flussi IPTV. Passa a mpv per vederli, oppure usa quelli online qui sopra.',
            session: session,
          ),
        ],
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        onlineOption,
        _TrackList(
          tracks: engine.getSubtitleTracks(),
          emptyMessage: 'Nessun sottotitolo incorporato in questo contenuto.',
          noneLabel: 'Disattivati',
          onSelect: (t) {
            if (identical(session.engine, engine)) {
              engine.selectSubtitleTrack(t);
            }
          },
        ),
      ],
    );
  });
}

Future<void> showQualitySheet(BuildContext context, PlaybackSession session) {
  final engine = session.engine;
  return _showSheet(context, 'Qualità video', (ctx) {
    if (engine == null || !engine.supportsQualitySelection) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Text(
          engine?.type == PlayerEngineType.mediakit
              ? 'Con mpv la qualità viene adattata automaticamente alla connessione.'
              : 'La scelta della qualità non è disponibile su questo dispositivo.',
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
      );
    }
    return _TrackList(
      tracks: engine.getQualityTracks(),
      emptyMessage: 'Questo flusso è disponibile in una sola qualità.',
      noneLabel: 'Automatica (in base alla connessione)',
      onSelect: (t) {
        if (identical(session.engine, engine)) engine.selectQualityTrack(t);
      },
    );
  });
}

Future<void> showSpeedSheet(BuildContext context, PlaybackSession session) {
  return _showSheet(context, 'Velocità di riproduzione', (ctx) {
    return ListView(
      shrinkWrap: true,
      children: [
        for (final s in kPlaybackSpeeds)
          _Option(
            label: formatSpeed(s),
            selected: session.speed == s,
            onTap: () {
              Navigator.pop(ctx);
              session.setSpeed(s);
            },
          ),
      ],
    );
  });
}

Future<void> showFitSheet(BuildContext context, PlaybackSession session) {
  return _showSheet(context, 'Formato immagine', (ctx) {
    return ListView(
      shrinkWrap: true,
      children: [
        for (final m in VideoFitMode.values)
          _Option(
            label: m.label,
            selected: session.fitMode == m,
            onTap: () {
              Navigator.pop(ctx);
              session.setFitMode(m);
            },
          ),
      ],
    );
  });
}

Future<void> showEngineSheet(BuildContext context, PlaybackSession session) {
  return _showSheet(context, 'Motore di riproduzione', (ctx) {
    return ListView(
      shrinkWrap: true,
      children: [
        for (final e in PlayerEngineType.values)
          _Option(
            label: e.label,
            detail: e.description,
            selected: session.engine?.type == e,
            onTap: () {
              Navigator.pop(ctx);
              if (session.engine?.type != e) session.switchEngine(e);
            },
          ),
      ],
    );
  });
}

Future<void> showSyncSheet(BuildContext context, PlaybackSession session) {
  return _showSheet(context, 'Sincronizzazione', (ctx) {
    if (session.engine?.supportsDelays != true) {
      return _Unsupported(
        message:
            'La regolazione del ritardo di audio e sottotitoli è disponibile con mpv.',
        session: session,
      );
    }
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          _DelayControl(
            label: 'Ritardo sottotitoli',
            value: session.subtitleDelay,
            onChanged: session.setSubtitleDelay,
          ),
          const SizedBox(height: 16),
          _DelayControl(
            label: 'Ritardo audio',
            value: session.audioDelay,
            onChanged: session.setAudioDelay,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  });
}

class _DelayControl extends StatelessWidget {
  final String label;
  final Duration value;
  final ValueChanged<Duration> onChanged;

  const _DelayControl({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget step(String text, int ms) => OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(56, 40),
        padding: EdgeInsets.zero,
      ),
      onPressed: () => onChanged(value + Duration(milliseconds: ms)),
      child: Text(text),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
            ),
            Text(
              formatDelay(value),
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            step('-500', -500),
            const SizedBox(width: 8),
            step('-50', -50),
            const Spacer(),
            TextButton(
              onPressed: () => onChanged(Duration.zero),
              child: const Text('Azzera'),
            ),
            const Spacer(),
            step('+50', 50),
            const SizedBox(width: 8),
            step('+500', 500),
          ],
        ),
      ],
    );
  }
}

Future<void> showPlayerMenu(
  BuildContext context,
  PlaybackSession session, {
  required bool statsVisible,
  required ValueChanged<bool> onStatsChanged,
  bool onlineSubsActive = false,
  bool onlineSubsLoading = false,
  VoidCallback? onLoadOnlineSubs,
  VoidCallback? onDisableOnlineSubs,
}) {
  final engine = session.engine;
  return _showSheet(context, 'Opzioni di riproduzione', (ctx) {
    Widget item(
      IconData icon,
      String title,
      String? value,
      Future<void> Function(BuildContext, PlaybackSession) open,
    ) {
      final tile = ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: Icon(icon, color: AppColors.textSecondary),
        title: Text(title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null)
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
        onTap: () {
          Navigator.pop(ctx);
          open(context, session);
        },
      );
      if (!DeviceTypeService.isTv) return tile;
      return TvFocusable(onPressed: tile.onTap!, child: tile);
    }

    return ListView(
      shrinkWrap: true,
      children: [
        item(
          Icons.memory_rounded,
          'Motore',
          engine?.type.label,
          showEngineSheet,
        ),
        item(Icons.audiotrack_rounded, 'Traccia audio', null, showAudioSheet),
        item(
          Icons.subtitles_rounded,
          'Sottotitoli',
          onlineSubsActive ? 'Italiano (online)' : null,
          (ctx, s) => showSubtitleSheet(
            ctx,
            s,
            onlineActive: onlineSubsActive,
            onlineLoading: onlineSubsLoading,
            onLoadOnline: onLoadOnlineSubs,
            onDisableOnline: onDisableOnlineSubs,
          ),
        ),
        item(
          Icons.high_quality_rounded,
          'Qualità video',
          null,
          showQualitySheet,
        ),
        if (!session.isLive)
          item(
            Icons.speed_rounded,
            'Velocità',
            formatSpeed(session.speed),
            showSpeedSheet,
          ),
        item(
          Icons.aspect_ratio_rounded,
          'Formato immagine',
          session.fitMode.label,
          showFitSheet,
        ),
        item(
          Icons.sync_rounded,
          'Sincronizzazione audio e sottotitoli',
          null,
          showSyncSheet,
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          secondary: const Icon(
            Icons.analytics_outlined,
            color: AppColors.textSecondary,
          ),
          title: const Text('Statistiche per nerd'),
          value: statsVisible,
          activeThumbColor: AppColors.primary,
          onChanged: (v) {
            Navigator.pop(ctx);
            onStatsChanged(v);
          },
        ),
      ],
    );
  });
}
