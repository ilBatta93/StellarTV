import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/series_details.dart';

class ParsedEpisodeTitle {
  final String seriesName;
  final int? season;
  final int? episode;

  const ParsedEpisodeTitle({
    required this.seriesName,
    this.season,
    this.episode,
  });
}

class SeriesGrouping {
  static final _sxe = RegExp(
    r'(?:^|[\s._\-\[(])S(\d{1,2})\s*[.xXeE]\s*E?(\d{1,3})\b',
    caseSensitive: false,
  );
  static final _sSpaceE = RegExp(
    r'(?:^|[\s._\-\[(])S(\d{1,2})\s+E(\d{1,3})\b',
    caseSensitive: false,
  );
  static final _nxn = RegExp(
    r'(?:^|[\s._\-\[(])(\d{1,2})x(\d{1,3})\b',
    caseSensitive: false,
  );
  static final _seasonWords = RegExp(
    r'(?:season|stagione)\s*(\d{1,2})\s*(?:episode|episodio|ep\.?)\s*(\d{1,3})\b',
    caseSensitive: false,
  );

  static final _animeKeywords = RegExp(
    r'\banime\b|\bmanga\b|one ?piece|naruto|bleach|dragon ?ball|attack on ?ti[ta]an|'
    r'demon ?slayer|jujutsu ?kaisen|my hero ?academia|spy ?x ?family|chainsaw ?man|'
    r'death ?note|fullmetal|hunter ?x ?hunter|sword art ?online|tokyo ?ghoul|'
    r'berserk|evangelion|one ?punch ?man|black ?clover|dr\.? ?stone|haikyu|'
    r'kaguya|ranking of ?kings|mob ?psycho|frieren|blue ?lock|hells ?paradise',
    caseSensitive: false,
  );

  static bool isAnimeGroup(String group) {
    final g = group.toLowerCase();
    return g.contains('anime') ||
        g.contains('manga') ||
        g.contains('japan') ||
        g.contains('giappone') ||
        _animeKeywords.hasMatch(g);
  }

  static bool isAnimeTitle(String name) => _animeKeywords.hasMatch(name);

  static ContentType inferType({
    required String url,
    required String group,
    required String name,
  }) {
    final u = url.toLowerCase();
    final g = group.toLowerCase();
    final isAnimeGroupMatch = isAnimeGroup(group);
    if (u.contains('/series/') ||
        g.contains('series') ||
        g.contains('serie') ||
        looksLikeEpisode(name)) {
      return isAnimeGroupMatch ? ContentType.anime : ContentType.series;
    }
    if (u.contains('/movie/') ||
        u.contains('/vod/') ||
        g.contains('movie') ||
        g.contains('film') ||
        g.contains('vod') ||
        g.contains('cinema')) {
      return ContentType.movie;
    }
    if (isAnimeGroupMatch || (isAnimeTitle(name) && looksLikeEpisode(name))) {
      return ContentType.anime;
    }
    return ContentType.live;
  }

  static bool looksLikeEpisode(String name) => parseTitle(name).episode != null;

  static ParsedEpisodeTitle parseTitle(String raw) {
    final name = raw.trim();
    final match =
        _sxe.firstMatch(name) ??
        _sSpaceE.firstMatch(name) ??
        _nxn.firstMatch(name) ??
        _seasonWords.firstMatch(name);
    if (match == null) {
      return ParsedEpisodeTitle(seriesName: _cleanSeriesName(name));
    }
    final season = int.tryParse(match.group(1) ?? '');
    final episode = int.tryParse(match.group(2) ?? '');
    final before = name.substring(0, match.start);
    return ParsedEpisodeTitle(
      seriesName: _cleanSeriesName(before.isEmpty ? name : before),
      season: season,
      episode: episode,
    );
  }

  static String seriesKey(String seriesName, String group) {
    final n = _normalize(seriesName);
    final g = _normalize(group);
    return 'show_${n.hashCode.abs()}_${g.hashCode.abs()}';
  }

  static List<Channel> catalog(List<Channel> seriesItems) {
    if (seriesItems.isEmpty) return const [];
    final folders = seriesItems.where((c) => c.isSeriesFolder).toList();
    if (folders.isNotEmpty) {
      folders.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return folders;
    }

    final groups = <String, List<Channel>>{};
    for (final item in seriesItems) {
      final key = item.seriesKey ?? item.id;
      (groups[key] ??= []).add(item);
    }

    final result = <Channel>[];
    for (final entries in groups.values) {
      entries.sort(_compareEpisodes);
      final first = entries.first;
      final logo = entries
          .map((e) => e.logo)
          .firstWhere((l) => l.isNotEmpty, orElse: () => first.logo);
      result.add(
        first.copyWith(
          id: first.seriesKey ?? first.id,
          name: first.displaySeriesName,
          url: '',
          logo: logo,
          seriesKey: first.seriesKey ?? first.id,
          seriesName: first.displaySeriesName,
          isSeriesFolder: true,
          episodeCount: entries.length,
          plot: first.plot,
        ),
      );
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  static SeriesDetails detailsFromEpisodes(Channel series, List<Channel> all) {
    final key = series.seriesKey ?? series.id;
    final episodes =
        all
            .where(
              (c) =>
                  c.type == ContentType.series &&
                  c.isPlayable &&
                  (c.seriesKey == key || c.id == series.id),
            )
            .toList()
          ..sort(_compareEpisodes);

    if (episodes.isEmpty && series.isPlayable) {
      episodes.add(series);
    }

    final bySeason = <int, List<SeriesEpisode>>{};
    for (final channel in episodes) {
      final parsed = parseTitle(channel.name);
      final season = channel.season ?? parsed.season ?? 1;
      final number =
          channel.episode ??
          parsed.episode ??
          (bySeason[season]?.length ?? 0) + 1;
      final title = _episodeLabel(channel, parsed);
      (bySeason[season] ??= []).add(
        SeriesEpisode(
          channel: channel,
          season: season,
          number: number,
          title: title,
          overview: channel.plot,
          image: channel.logo.isEmpty ? null : channel.logo,
        ),
      );
    }

    final seasons = bySeason.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return SeriesDetails(
      series: series,
      overview: series.plot ?? '',
      seasons: [
        for (final e in seasons)
          SeriesSeason(
            number: e.key,
            name: e.key <= 0 ? 'Speciali' : 'Stagione ${e.key}',
            episodes: e.value,
          ),
      ],
    );
  }

  static int _compareEpisodes(Channel a, Channel b) {
    final sa = a.season ?? 0;
    final sb = b.season ?? 0;
    if (sa != sb) return sa.compareTo(sb);
    final ea = a.episode ?? 0;
    final eb = b.episode ?? 0;
    if (ea != eb) return ea.compareTo(eb);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  static String _episodeLabel(Channel channel, ParsedEpisodeTitle parsed) {
    if (channel.seriesName != null &&
        channel.name != channel.seriesName &&
        !channel.name.toLowerCase().startsWith(
          channel.seriesName!.toLowerCase(),
        )) {
      return channel.name;
    }
    var label = channel.name;
    if (channel.seriesName != null &&
        label.toLowerCase().startsWith(channel.seriesName!.toLowerCase())) {
      label = label.substring(channel.seriesName!.length);
    }
    label = label.replaceFirst(RegExp(r'^[\s\-–—:|·.]+'), '');
    return label.isEmpty
        ? 'Episodio ${channel.episode ?? parsed.episode ?? ''}'.trim()
        : label;
  }

  static String _cleanSeriesName(String raw) {
    var name = raw.trim();
    name = name.replaceAll(RegExp(r'[\s\-–—:|·._]+$'), '');
    name = name.replaceAll(RegExp(r'\s+'), ' ');
    return name.isEmpty ? raw.trim() : name;
  }

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ').trim();
}
