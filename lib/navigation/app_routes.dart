import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/tmdb_item.dart';
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

void openChannel(BuildContext context, Channel channel) {
  if (channel.type == ContentType.live) {
    playChannel(context, channel);
    return;
  }
  if (channel.type == ContentType.series) {
    // Always land on the seasons/episodes list first, even when the channel
    // is a single episode: its seriesKey reconstructs the series folder.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeriesDetailScreen(
          series: channel.copyWith(
            isSeriesFolder: true,
            seriesKey: channel.seriesKey ?? channel.id,
          ),
        ),
      ),
    );
    return;
  }
  if (channel.type == ContentType.anime) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => TitleDetailScreen(channel: channel)),
    );
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => TitleDetailScreen(channel: channel)),
  );
}

void openTmdbItem(BuildContext context, TmdbItem item) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => TitleDetailScreen(item: item)),
  );
}
