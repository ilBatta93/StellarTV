import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/player_settings.dart';
import '../models/tmdb_item.dart';
import '../providers/app_provider.dart';
import '../providers/history_provider.dart';
import '../screens/player_screen.dart';
import '../screens/series_detail_screen.dart';
import '../screens/title_detail_screen.dart';
import '../services/device_type_service.dart';
import '../services/download_service.dart';
import '../services/external_player_service.dart';
import '../services/player_settings_service.dart';
import '../services/recent_live_channels.dart';

/// Plays a channel. For series episodes [queue] is the ordered episode list
/// used by "Episodio successivo"; when omitted the player loads it itself.
/// [external] forces (true) or skips (false) the external player; null
/// follows the setting. The player's own "next episode" (replace) stays
/// inside the app.
void playChannel(
  BuildContext context,
  Channel channel, {
  Duration? startAt,
  List<Channel>? queue,
  bool replace = false,
  bool archivePlayback = false,
  bool? external,
}) {
  final app = context.read<AppProvider>();
  if (app.kidsMode && !app.isKidsContent(channel)) return;
  if (app.kidsMode && queue != null) {
    queue = queue.where(app.isKidsContent).toList();
  }
  if (channel.isSeriesFolder) {
    openChannel(context, channel);
    return;
  }
  if (!archivePlayback) context.read<HistoryProvider>().recordStart(channel);
  // Live channels stay out of the watch history: Diretta keeps its own
  // device-local "Visti di recente" list.
  if (channel.type == ContentType.live && !archivePlayback) {
    RecentLiveChannels.instance.record(channel.id);
  }
  // Offline copies play from the device; history keeps the same ids.
  final offline = DownloadService.instance;
  if (!archivePlayback) channel = offline.playable(channel);
  queue = queue?.map(offline.playable).toList();
  final externals = ExternalPlayerService.instance;
  if (!archivePlayback &&
      !replace &&
      externals.supported &&
      externals.player != null &&
      (external ?? externals.enabled) &&
      ExternalPlayerService.canPlay(channel)) {
    unawaited(_playExternally(context, channel, startAt));
    return;
  }
  final route = MaterialPageRoute(
    builder: (_) => PlayerScreen(
      channel: channel,
      startAt: startAt,
      queue: queue,
      archivePlayback: archivePlayback,
    ),
  );
  if (replace) {
    Navigator.pushReplacement(context, route);
  } else {
    Navigator.push(context, route);
  }
}

/// Hands [channel] to the chosen player app and stores the position it
/// reports back. If the app cannot start, the built-in player opens.
Future<void> _playExternally(
  BuildContext context,
  Channel channel,
  Duration? startAt,
) async {
  final history = context.read<HistoryProvider>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final settings = await PlayerSettingsService().load(
    scope: DeviceTypeService.isTv
        ? PlayerSettingsScope.filmSeriesTv
        : PlayerSettingsScope.shared,
  );
  final resume =
      startAt ??
      (settings.resumePlayback
          ? history.entryFor(channel.id)?.resumePosition
          : null);
  try {
    final result = await ExternalPlayerService.instance.play(
      channel,
      userAgent: effectiveStreamUserAgent(settings.userAgent),
      startAt: resume,
    );
    final duration = result.duration;
    if (duration == null) return;
    if (result.completed) {
      await history.markWatched(channel, duration: duration);
    } else if (result.position case final position?) {
      await history.updatePosition(channel.id, position, duration);
    }
  } on PlatformException {
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Player esterno non disponibile: uso quello interno'),
      ),
    );
    if (!context.mounted) return;
    playChannel(context, channel, startAt: resume, external: false);
  }
}

/// Opens the combined series page (plot, cast and seasons/episodes).
void openSeries(
  BuildContext context,
  Channel channel, {
  TmdbItem? item,
  bool replace = false,
}) {
  final app = context.read<AppProvider>();
  if (app.kidsMode && !app.isKidsContent(channel)) return;
  final route = MaterialPageRoute(
    settings: RouteSettings(
      name: titleRouteName(channel.seriesKey ?? channel.id),
    ),
    builder: (_) => SeriesDetailScreen(
      series: channel.copyWith(
        isSeriesFolder: true,
        seriesKey: channel.seriesKey ?? channel.id,
      ),
      item: item,
    ),
  );
  if (replace) {
    Navigator.pushReplacement(context, route);
  } else {
    Navigator.push(context, route);
  }
}

void openChannel(
  BuildContext context,
  Channel channel, {
  bool replace = false,
}) {
  final app = context.read<AppProvider>();
  if (app.kidsMode && !app.isKidsContent(channel)) return;
  if (channel.type == ContentType.live) {
    playChannel(context, channel);
    return;
  }
  if (channel.type == ContentType.series || channel.type == ContentType.anime) {
    openSeries(context, channel, replace: replace);
    return;
  }
  final route = MaterialPageRoute(
    settings: RouteSettings(name: titleRouteName(channel.id)),
    builder: (_) => TitleDetailScreen(channel: channel),
  );
  if (replace) {
    Navigator.pushReplacement(context, route);
  } else {
    Navigator.push(context, route);
  }
}

/// Route name of a title page, used by the player's "Scheda titolo" button
/// to go back to the page it was opened from instead of opening a copy.
String titleRouteName(String id) => 'title:$id';

/// Keeps track of the pages currently open, so the player can go back to a
/// title page that is already there (instant) instead of rebuilding it.
class OpenRoutesObserver extends NavigatorObserver {
  OpenRoutesObserver._();
  static final OpenRoutesObserver instance = OpenRoutesObserver._();

  final List<Route<dynamic>> _routes = [];
  final ValueNotifier<int> changes = ValueNotifier(0);

  bool containsNamed(String name) =>
      _routes.any((r) => r.settings.name == name && r.isActive);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    changes.value++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _routes[i] = newRoute;
    } else {
      if (oldRoute != null) _routes.remove(oldRoute);
      if (newRoute != null) _routes.add(newRoute);
    }
  }
}

void openTmdbItem(BuildContext context, TmdbItem item) {
  if (!context.read<AppProvider>().isTmdbAllowed(item)) return;
  if (item.contentType != ContentType.movie) {
    final folder = context.read<AppProvider>().findChannelFor(item);
    if (folder != null) {
      openSeries(context, folder, item: item);
      return;
    }
  }
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => TitleDetailScreen(item: item)),
  );
}
