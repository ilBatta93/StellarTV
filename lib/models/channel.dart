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
  });

  bool get isPlayable => url.isNotEmpty && !isSeriesFolder;

  String get displaySeriesName =>
      (seriesName != null && seriesName!.trim().isNotEmpty)
          ? seriesName!
          : name;

  factory Channel.fromMap(Map<String, dynamic> map) {
    return Channel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Unknown',
      url: map['url'] as String? ?? '',
      logo: map['logo'] as String? ?? '',
      group: map['group'] as String? ?? 'Uncategorized',
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
    );
  }

  factory Channel.fromJson(Map<String, dynamic> json) => Channel.fromMap(json);

  Map<String, dynamic> toJson() => toMap();
}
