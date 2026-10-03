import 'channel.dart';

class SeriesEpisode {
  final Channel channel;
  final int season;
  final int number;
  final String title;
  final String? overview;
  final String? image;
  final Duration? duration;

  const SeriesEpisode({
    required this.channel,
    required this.season,
    required this.number,
    required this.title,
    this.overview,
    this.image,
    this.duration,
  });

  String get code {
    final s = season.toString().padLeft(2, '0');
    final e = number.toString().padLeft(2, '0');
    return 'S$s E$e';
  }
}

class SeriesSeason {
  final int number;
  final String name;
  final List<SeriesEpisode> episodes;

  const SeriesSeason({
    required this.number,
    required this.name,
    required this.episodes,
  });
}

class SeriesDetails {
  final Channel series;
  final String overview;
  final List<SeriesSeason> seasons;

  const SeriesDetails({
    required this.series,
    required this.overview,
    required this.seasons,
  });

  List<SeriesEpisode> get allEpisodes => [
        for (final season in seasons) ...season.episodes,
      ];
}
