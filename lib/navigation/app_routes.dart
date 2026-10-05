import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/tmdb_item.dart';
import '../providers/app_provider.dart';
import '../providers/history_provider.dart';
import '../screens/player_screen.dart';
import '../screens/series_detail_screen.dart';
import '../screens/title_detail_screen.dart';

/// Plays a channel. For series episodes [queue] is the ordered episode list
/// used by "Episodio successivo"; when omitted the player loads it itself.
void playChannel(BuildContext context, Channel channel,
    {Duration? startAt, List<Channel>? queue, bool replace = false}) {
  if (channel.isSeriesFolder) {
    openChannel(context, channel);
    return;
  }
  context.read<HistoryProvider>().recordStart(channel);
  final route = MaterialPageRoute(
      builder: (_) =>
          PlayerScreen(channel: channel, startAt: startAt, queue: queue));
  if (replace) {
    Navigator.pushReplacement(context, route);
  } else {
    Navigator.push(context, route);
  }
}

/// Opens the combined series page (plot, cast and seasons/episodes).
void openSeries(BuildContext context, Channel channel,
    {TmdbItem? item, bool replace = false}) {
  final route = MaterialPageRoute(
    settings: RouteSettings(name: titleRouteName(channel.seriesKey ?? channel.id)),
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

void openChannel(BuildContext context, Channel channel, {bool replace = false}) {
  if (channel.type == ContentType.live) {
    playChannel(context, channel);
    return;
  }
  if (channel.type == ContentType.series ||
      channel.type == ContentType.anime) {
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

void openTmdbItem(BuildContext context, TmdbItem item) {
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
