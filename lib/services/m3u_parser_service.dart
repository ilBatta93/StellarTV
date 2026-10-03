import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/channel.dart';
import '../models/content_type.dart';
import 'series_grouping.dart';

class M3uParserService {
  Future<List<Channel>> parseFromUrl(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to load playlist: ${response.statusCode}');
    }
    return parseFromString(response.body);
  }

  List<Channel> parseFromString(String content) {
    final lines = LineSplitter.split(content);
    final channels = <Channel>[];
    int counter = 0;

    String? currentName;
    String? currentLogo;
    String? currentGroup;
    String? currentTvgId;
    String? currentTvgName;
    ContentType? currentTypeHint;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('#EXTINF')) {
        currentName = _extractAttribute(trimmed, 'tvg-name') ??
            _extractName(trimmed);
        currentLogo = _extractAttribute(trimmed, 'tvg-logo') ?? '';
        currentTvgId = _extractAttribute(trimmed, 'tvg-id');
        currentTvgName = _extractAttribute(trimmed, 'tvg-name');
        currentGroup =
            _extractAttribute(trimmed, 'group-title') ?? 'Uncategorized';
        currentTypeHint = _typeFromExtInf(trimmed);
      } else if (!trimmed.startsWith('#')) {
        counter++;
        final name = currentName ?? 'Channel $counter';
        final group = currentGroup ?? 'Uncategorized';
        final type = currentTypeHint ??
            SeriesGrouping.inferType(url: trimmed, group: group, name: name);
        final parsed = type == ContentType.series
            ? SeriesGrouping.parseTitle(name)
            : null;
        final seriesName = parsed?.seriesName;
        channels.add(Channel(
          id: 'ch_$counter',
          name: name,
          url: trimmed,
          logo: currentLogo ?? '',
          group: group,
          type: type,
          tvgId: currentTvgId,
          tvgName: currentTvgName,
          seriesKey: type == ContentType.series
              ? SeriesGrouping.seriesKey(
                  seriesName ?? name,
                  group,
                )
              : null,
          seriesName:
              type == ContentType.series ? (seriesName ?? name) : null,
          season: parsed?.season,
          episode: parsed?.episode,
        ));
        currentName = null;
        currentLogo = null;
        currentGroup = null;
        currentTvgId = null;
        currentTvgName = null;
        currentTypeHint = null;
      }
    }

    return channels;
  }

  ContentType? _typeFromExtInf(String line) {
    final tvgType = _extractAttribute(line, 'tvg-type') ??
        _extractAttribute(line, 'type');
    switch (tvgType?.toLowerCase()) {
      case 'movie':
      case 'vod':
        return ContentType.movie;
      case 'series':
      case 'show':
        return ContentType.series;
      case 'live':
        return ContentType.live;
    }
    return null;
  }

  String? _extractAttribute(String line, String attr) {
    final regex = RegExp('$attr="([^"]*)"');
    final match = regex.firstMatch(line);
    return match?.group(1);
  }

  String? _extractName(String line) {
    final commaIndex = line.lastIndexOf(',');
    if (commaIndex != -1 && commaIndex < line.length - 1) {
      return line.substring(commaIndex + 1).trim();
    }
    return null;
  }
}
