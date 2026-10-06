import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/catalog_load_state.dart';
import '../models/content_type.dart';
import '../providers/app_provider.dart';
import '../services/device_type_service.dart';
import '../services/xtream_downloader.dart';
import '../theme/app_theme.dart';
import 'tv_focusable.dart';
import 'settings_tiles.dart';

/// Wraps a Diretta / Film / Serie TV page: shows live download progress
/// while the section is empty, a retry screen when it failed and a slim
/// "saved copy" bar when it is showing offline data. Retrying reloads only
/// this section. Works the same with touch and with the TV remote.
class CatalogSectionFrame extends StatelessWidget {
  final ContentType type;
  final Widget child;
  const CatalogSectionFrame({
    super.key,
    required this.type,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.select<AppProvider, CatalogLoadState>(
      (app) => app.catalogState(type),
    );
    if (state.isPending && !state.hasContent) {
      return CatalogLoadingView(
        type: type,
        queued: state.phase == CatalogLoadPhase.queued,
      );
    }
    if (state.phase == CatalogLoadPhase.failed && !state.hasContent) {
      return CatalogFailureView(type: type, message: state.error);
    }
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: state.phase == CatalogLoadPhase.cached
              ? CatalogStaleBar(type: type, message: state.error)
              : const SizedBox(width: double.infinity),
        ),
        Expanded(key: const ValueKey('section-content'), child: child),
      ],
    );
  }
}

String _sectionName(ContentType type) => switch (type) {
  ContentType.live => 'Diretta',
  ContentType.movie => 'Film',
  _ => 'Serie TV',
};

class CatalogLoadingView extends StatelessWidget {
  final ContentType type;
  final bool queued;
  const CatalogLoadingView({
    super.key,
    required this.type,
    this.queued = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppProvider>();
    final tv = DeviceTypeService.isTv;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: tv ? 34 : 38,
              height: tv ? 34 : 38,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: queued ? AppColors.textMuted : AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              queued
                  ? '${_sectionName(type)} in coda'
                  : 'Caricamento ${_sectionName(type)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder<CatalogProgress?>(
              valueListenable: app.catalogProgress(type),
              builder: (context, progress, _) {
                final label = progress?.label ?? '';
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    queued
                        ? 'Parte appena finisce la sezione precedente'
                        : label.isEmpty
                        ? 'In attesa della risposta del server…'
                        : label,
                    key: ValueKey(
                      queued
                          ? 'q'
                          : label.isEmpty
                          ? 'w'
                          : 'p',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CatalogFailureView extends StatelessWidget {
  final ContentType type;
  final String? message;
  const CatalogFailureView({super.key, required this.type, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 28,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${_sectionName(type)} non disponibile',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                message ?? 'Caricamento non riuscito.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              CatalogRetryButton(type: type, prominent: true),
              const SizedBox(height: 10),
              const Text(
                'Le altre sezioni non vengono ricaricate.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slim bar shown above a section that is displaying its saved copy.
class CatalogStaleBar extends StatelessWidget {
  final ContentType type;
  final String? message;
  const CatalogStaleBar({super.key, required this.type, this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 16,
              color: AppColors.primaryLight,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Tooltip(
                message: message ?? '',
                child: Text(
                  'Copia salvata · aggiornamento ${_sectionName(type)} non riuscito',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CatalogRetryButton(type: type),
          ],
        ),
      ),
    );
  }
}

/// Retries one section. Touch: a regular button. TV: a remote-focusable
/// button with the shared orange focus frame.
class CatalogRetryButton extends StatelessWidget {
  final ContentType type;
  final bool prominent;
  const CatalogRetryButton({
    super.key,
    required this.type,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    final pending = context.select<AppProvider, bool>(
      (app) => app.catalogState(type).isPending,
    );
    final app = context.read<AppProvider>();
    void retry() {
      if (!pending) app.retrySection(type);
    }

    final icon = pending
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          )
        : const Icon(Icons.refresh_rounded, size: 18);
    final label = Text(
      pending ? 'Caricamento…' : 'Riprova ${_sectionName(type)}',
    );
    final button = prominent
        ? FilledButton.icon(
            onPressed: pending ? null : retry,
            icon: icon,
            label: label,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          )
        : TextButton.icon(
            onPressed: pending ? null : retry,
            icon: icon,
            label: Text(pending ? 'Caricamento…' : 'Riprova'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              visualDensity: VisualDensity.compact,
            ),
          );
    return TvFocusable(
      onPressed: retry,
      borderRadius: BorderRadius.circular(12),
      child: button,
    );
  }
}

/// Settings: the state of every section with an individual retry.
class PlaylistStatusList extends StatelessWidget {
  const PlaylistStatusList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (i, entry) in const [
          (ContentType.live, Icons.live_tv_rounded),
          (ContentType.movie, Icons.movie_outlined),
          (ContentType.series, Icons.video_library_outlined),
        ].indexed) ...[
          if (i > 0)
            const Divider(height: 1, indent: 56, color: AppColors.border),
          _SectionTile(type: entry.$1, icon: entry.$2),
        ],
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  final ContentType type;
  final IconData icon;
  const _SectionTile({required this.type, required this.icon});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppProvider>();
    final state = context.select<AppProvider, CatalogLoadState>(
      (a) => a.catalogState(type),
    );
    final count = context.select<AppProvider, int>(
      (a) => a.catalogOf(type).length,
    );
    return ValueListenableBuilder<CatalogProgress?>(
      valueListenable: app.catalogProgress(type),
      builder: (context, progress, _) {
        final subtitle = switch (state.phase) {
          CatalogLoadPhase.loading =>
            (progress?.label.isNotEmpty ?? false)
                ? 'Caricamento · ${progress!.label}'
                : 'Caricamento…',
          CatalogLoadPhase.queued => 'In coda',
          CatalogLoadPhase.ready =>
            count > 0
                ? '${CatalogProgress.formatCount(count)} titoli · aggiornata'
                : 'Nessun contenuto',
          CatalogLoadPhase.cached =>
            'Copia salvata · ${state.error ?? 'aggiornamento non riuscito'}',
          CatalogLoadPhase.failed => state.error ?? 'Non disponibile',
          CatalogLoadPhase.idle => 'Non ancora caricata',
        };
        final color = switch (state.phase) {
          CatalogLoadPhase.failed => AppColors.primary,
          CatalogLoadPhase.cached => AppColors.primaryLight,
          _ => AppColors.textSecondary,
        };
        return tvSettingsRow(
          onPressed: state.isPending ? null : () => app.retrySection(type),
          child: ListTile(
            leading: Icon(icon, color: color),
            title: Text(
              _sectionName(type),
              style: const TextStyle(fontSize: 15),
            ),
            subtitle: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
              ),
            ),
            trailing: state.isPending
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Icon(Icons.refresh_rounded, color: AppColors.primary),
            onTap: state.isPending ? null : () => app.retrySection(type),
          ),
        );
      },
    );
  }
}
