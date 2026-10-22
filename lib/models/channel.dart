import 'content_type.dart';

class Channel {
  final String id;
  final String name;
  final String url;
  final String logo;
  final String group;
  final ContentType type;
  final String? tvgId;
  final String? tvgName;
  final String? language;
  final String? country;
  final String? seriesKey;
  final String? seriesName;
  final int? season;
  final int? episode;
  final String? plot;
  final bool isSeriesFolder;
  final int episodeCount;

  /// Unix seconds when the provider added the item (0 when unknown).
  final int addedAt;

  /// Real release date as yyyymmdd (0 when unknown). Comes from the provider
  /// metadata, falling back to a year written in the title.
  final int releaseDate;
  final int archiveDays;

  Channel({
    required this.id,
    required this.name,
    required this.url,
    required this.logo,
    required this.group,
    required this.type,
    this.tvgId,
    this.tvgName,
    this.language,
    this.country,
    this.seriesKey,
    this.seriesName,
    this.season,
    this.episode,
    this.plot,
    this.isSeriesFolder = false,
    this.episodeCount = 0,
    this.addedAt = 0,
    this.releaseDate = 0,
    this.archiveDays = 0,
  });

  static final RegExp _titleYear = RegExp(r'(?:^|[^0-9])((?:19|20)[0-9]{2})(?![0-9])');

  /// Release key used for sorting: stored date or the year in the title.
  int get releaseKey {
    if (releaseDate > 0) return releaseDate;
    final m = _titleYear.allMatches(displaySeriesName).lastOrNull;
    final y = m == null ? 0 : int.parse(m.group(1)!);
    return y > 1900 && y <= DateTime.now().year + 2 ? y * 10000 + 101 : 0;
  }

  /// Parses provider dates such as "2019-05-21", "2019" or Unix seconds.
  static int parseReleaseDate(Object? raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return 0;
    final iso = RegExp(r'^((?:19|20)[0-9]{2})(?:[-/.]([0-9]{1,2})(?:[-/.]([0-9]{1,2}))?)?').firstMatch(s);
    if (iso != null) {
      final y = int.parse(iso.group(1)!);
      final mo = int.tryParse(iso.group(2) ?? '') ?? 1;
      final d = int.tryParse(iso.group(3) ?? '') ?? 1;
      if (mo < 1 || mo > 12 || d < 1 || d > 31) return y * 10000 + 101;
      return y * 10000 + mo * 100 + d;
    }
    final dmy = RegExp(r'^([0-9]{1,2})[-/.]([0-9]{1,2})[-/.]((?:19|20)[0-9]{2})').firstMatch(s);
    if (dmy != null) {
      final d = int.parse(dmy.group(1)!), mo = int.parse(dmy.group(2)!);
      final y = int.parse(dmy.group(3)!);
      if (mo < 1 || mo > 12 || d < 1 || d > 31) return y * 10000 + 101;
      return y * 10000 + mo * 100 + d;
    }
    return 0;
  }

  bool get isPlayable => url.isNotEmpty && !isSeriesFolder;

  String get displaySeriesName =>
      (seriesName != null && seriesName!.trim().isNotEmpty)
      ? seriesName!
      : name;

  factory Channel.fromMap(Map<String, dynamic> map) {
    return Channel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Sconosciuto',
      url: map['url'] as String? ?? '',
      logo: map['logo'] as String? ?? '',
      group: map['group'] as String? ?? 'Senza categoria',
      type: ContentType.values.firstWhere(
        (e) => e.name == (map['type'] as String? ?? 'live'),
        orElse: () => ContentType.live,
      ),
      tvgId: map['tvg_id'] as String?,
      tvgName: map['tvg_name'] as String?,
      language: map['language'] as String?,
      country: map['country'] as String?,
      seriesKey: map['series_key'] as String?,
      seriesName: map['series_name'] as String?,
      season: (map['season'] as num?)?.toInt(),
      episode: (map['episode'] as num?)?.toInt(),
      plot: map['plot'] as String?,
      isSeriesFolder: map['is_series_folder'] == true,
      episodeCount: (map['episode_count'] as num?)?.toInt() ?? 0,
      addedAt: (map['added_at'] as num?)?.toInt() ?? 0,
      releaseDate: (map['release_date'] as num?)?.toInt() ?? 0,
      archiveDays: (map['archive_days'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'logo': logo,
      'group': group,
      'type': type.name,
      'tvg_id': tvgId,
      'tvg_name': tvgName,
      'language': language,
      'country': country,
      'series_key': seriesKey,
      'series_name': seriesName,
      'season': season,
      'episode': episode,
      'plot': plot,
      'is_series_folder': isSeriesFolder,
      'episode_count': episodeCount,
      'added_at': addedAt,
      'release_date': releaseDate,
      'archive_days': archiveDays,
    };
  }

  Channel copyWith({
    String? id,
    String? name,
    String? url,
    String? logo,
    String? group,
    ContentType? type,
    String? tvgId,
    String? tvgName,
    String? language,
    String? country,
    String? seriesKey,
    String? seriesName,
    int? season,
    int? episode,
    String? plot,
    bool? isSeriesFolder,
    int? episodeCount,
    int? addedAt,
    int? releaseDate,
    int? archiveDays,
  }) {
    return Channel(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      logo: logo ?? this.logo,
      group: group ?? this.group,
      type: type ?? this.type,
      tvgId: tvgId ?? this.tvgId,
      tvgName: tvgName ?? this.tvgName,
      language: language ?? this.language,
      country: country ?? this.country,
      seriesKey: seriesKey ?? this.seriesKey,
      seriesName: seriesName ?? this.seriesName,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      plot: plot ?? this.plot,
      isSeriesFolder: isSeriesFolder ?? this.isSeriesFolder,
      episodeCount: episodeCount ?? this.episodeCount,
      addedAt: addedAt ?? this.addedAt,
      releaseDate: releaseDate ?? this.releaseDate,
      archiveDays: archiveDays ?? this.archiveDays,
    );
  }

  factory Channel.fromJson(Map<String, dynamic> json) => Channel.fromMap(json);

  Map<String, dynamic> toJson() => toMap();
}
