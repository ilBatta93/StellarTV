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

void playChannel(BuildContext context, Channel channel, {Duration? startAt}) {
  context.read<HistoryProvider>().recordStart(channel);
  Navigator.push(
    context,
    MaterialPageRoute(
        builder: (_) => PlayerScreen(channel: channel, startAt: startAt)),
  );
}

/// Opens the combined series page (plot, cast and seasons/episodes).
void openSeries(BuildContext context, Channel channel,
    {TmdbItem? item, bool replace = false}) {
  final route = MaterialPageRoute(
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

void openChannel(BuildContext context, Channel channel) {
  if (channel.type == ContentType.live) {
    playChannel(context, channel);
    return;
  }
  if (channel.type == ContentType.series ||
      channel.type == ContentType.anime) {
    openSeries(context, channel);
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => TitleDetailScreen(channel: channel)),
  );
}

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
