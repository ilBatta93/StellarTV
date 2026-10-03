import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/series_details.dart';
import 'series_grouping.dart';

class XtreamService {
  String _normalizeServerUrl(String server) {
    var url = server.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  String _buildApiUrl(String server, String username, String password) {
    final base = _normalizeServerUrl(server);
    return '$base/player_api.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}';
  }

  String _buildM3uUrl(String server, String username, String password) {
    final base = _normalizeServerUrl(server);
    return '$base/get.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}&type=m3u_plus';
  }

  Future<bool> authenticate({
    required String server,
    required String username,
    required String password,
  }) async {
    final apiUrl = _buildApiUrl(server, username, password);
    final response = await http.get(Uri.parse(apiUrl));
    if (response.statusCode != 200) return false;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final userInfo = data['user_info'] as Map<String, dynamic>?;
    if (userInfo == null) return false;
    final status = userInfo['auth'] ?? 0;
    return status == 1;
  }

  String getM3uUrl(String server, String username, String password) {
    return _buildM3uUrl(server, username, password);
  }

  Future<List<Channel>> getLiveChannels({
    required String server,
    required String username,
    required String password,
  }) async {
    final base = _normalizeServerUrl(server);
    final url =
        '$base/player_api.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}&action=get_live_streams';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return [];
    final List<dynamic> data = jsonDecode(response.body) as List;
    final categories = await _getCategories(base, username, password, 'live');
    return data.map((item) {
      final catId = item['category_id']?.toString() ?? '';
      final groupName = categories[catId] ?? 'Uncategorized';
      return Channel(
        id: 'live_${item['stream_id']}',
        name: item['name']?.toString() ?? 'Unknown',
        url:
            '$base/${Uri.encodeComponent(username)}/${Uri.encodeComponent(password)}/${item['stream_id']}.m3u8',
        logo: item['stream_icon']?.toString() ?? '',
        group: groupName,
        type: ContentType.live,
        tvgId: item['epg_channel_id']?.toString(),
      );
    }).toList();
  }

  Future<List<Channel>> getVodChannels({
    required String server,
    required String username,
    required String password,
  }) async {
    final base = _normalizeServerUrl(server);
    final url =
        '$base/player_api.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}&action=get_vod_streams';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return [];
    final List<dynamic> data = jsonDecode(response.body) as List;
    final categories = await _getCategories(base, username, password, 'vod');
    return data.map((item) {
      final catId = item['category_id']?.toString() ?? '';
      final groupName = categories[catId] ?? 'Uncategorized';
      return Channel(
        id: 'movie_${item['stream_id']}',
        name: item['name']?.toString() ?? 'Unknown',
        url:
            '$base/movie/${Uri.encodeComponent(username)}/${Uri.encodeComponent(password)}/${item['stream_id']}.${item['container_extension'] ?? 'mp4'}',
        logo: item['stream_icon']?.toString() ?? '',
        group: groupName,
        type: ContentType.movie,
      );
    }).toList();
  }

  Future<List<Channel>> getSeriesChannels({
    required String server,
    required String username,
    required String password,
  }) async {
    final base = _normalizeServerUrl(server);
    final url =
        '$base/player_api.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}&action=get_series';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return [];
    final List<dynamic> data = jsonDecode(response.body) as List;
    final categories =
        await _getCategories(base, username, password, 'series');
    return data.map((item) {
      final catId = item['category_id']?.toString() ?? '';
      final groupName = categories[catId] ?? 'Uncategorized';
      final seriesId = item['series_id']?.toString() ?? '';
      return Channel(
        id: 'series_$seriesId',
        name: item['name']?.toString() ?? 'Unknown',
        url: '',
        logo: (item['cover'] ?? item['stream_icon'])?.toString() ?? '',
        group: groupName,
        type: SeriesGrouping.isAnimeGroup(groupName)
            ? ContentType.anime
            : ContentType.series,
        seriesKey: 'series_$seriesId',
        seriesName: item['name']?.toString(),
        plot: item['plot']?.toString(),
        isSeriesFolder: true,
      );
    }).toList();
  }

  Future<SeriesDetails> getSeriesInfo({
    required String server,
    required String username,
    required String password,
    required Channel series,
  }) async {
    final base = _normalizeServerUrl(server);
    final seriesId = (series.seriesKey ?? series.id).replaceFirst('series_', '');
    final url =
        '$base/player_api.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}&action=get_series_info&series_id=${Uri.encodeComponent(seriesId)}';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Impossibile caricare le stagioni (HTTP ${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Risposta serie non valida dal server');
    }
    final data = decoded.cast<String, dynamic>();
    final info = _asMap(data['info']);
    final overview = (info['plot'] ?? info['description'] ?? series.plot ?? '')
        .toString();
    final cover = (info['cover'] ?? series.logo).toString();
    final user = Uri.encodeComponent(username);
    final pass = Uri.encodeComponent(password);

    final seasons = <int, List<SeriesEpisode>>{};
    for (final episodeJson in _extractEpisodeMaps(data['episodes'])) {
      final streamId = (episodeJson['id'] ?? episodeJson['episode_id'])
          ?.toString();
      if (streamId == null || streamId.isEmpty) continue;
      final episodeInfo = _asMap(episodeJson['info']);
      final season = _toInt(episodeJson['season']) ??
          _toInt(episodeInfo['season']) ??
          1;
      final number = _toInt(episodeJson['episode_num']) ??
          _toInt(episodeJson['episode']) ??
          (seasons[season]?.length ?? 0) + 1;
      final ext =
          (episodeJson['container_extension'] ?? 'mp4').toString();
      final title = (episodeJson['title'] ??
              episodeInfo['name'] ??
              'Episodio $number')
          .toString();
      final image = (episodeInfo['movie_image'] ??
              episodeJson['cover'] ??
              cover)
          .toString();
      final channel = Channel(
        id: 'episode_$streamId',
        name: '${series.name} · S${season.toString().padLeft(2, '0')}E${number.toString().padLeft(2, '0')} · $title',
        url: '$base/series/$user/$pass/$streamId.$ext',
        logo: image,
        group: series.group,
        type: series.type,
        seriesKey: series.seriesKey ?? series.id,
        seriesName: series.name,
        season: season,
        episode: number,
        plot: episodeInfo['plot']?.toString(),
      );
      (seasons[season] ??= []).add(
        SeriesEpisode(
          channel: channel,
          season: season,
          number: number,
          title: title,
          overview: episodeInfo['plot']?.toString(),
          image: image.isEmpty ? null : image,
          duration: _durationFrom(episodeInfo, episodeJson),
        ),
      );
    }

    if (seasons.isEmpty) {
      throw Exception('Nessun episodio trovato per questa serie');
    }

    final ordered = seasons.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final e in ordered) {
      e.value.sort((a, b) => a.number.compareTo(b.number));
    }

    return SeriesDetails(
      series: series.copyWith(
        logo: cover.isNotEmpty ? cover : series.logo,
        plot: overview,
      ),
      overview: overview,
      seasons: [
        for (final e in ordered)
          SeriesSeason(
            number: e.key,
            name: e.key <= 0 ? 'Speciali' : 'Stagione ${e.key}',
            episodes: e.value,
          ),
      ],
    );
  }

  Iterable<Map<String, dynamic>> _extractEpisodeMaps(dynamic raw) sync* {
    if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((a, b) => _toInt(a.key)?.compareTo(_toInt(b.key) ?? 0) ??
            a.key.toString().compareTo(b.key.toString()));
      for (final entry in entries) {
        yield* _extractEpisodeMaps(entry.value);
      }
      return;
    }
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          yield item.map((k, v) => MapEntry(k.toString(), v));
        } else {
          yield* _extractEpisodeMaps(item);
        }
      }
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  Duration? _durationFrom(Map<String, dynamic> info, Map<String, dynamic> episode) {
    final secs = _toInt(info['duration_secs'] ??
        info['duration_sec'] ??
        episode['duration_secs']);
    if (secs != null && secs > 0) return Duration(seconds: secs);
    final raw = (info['duration'] ?? episode['duration'])?.toString();
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':').map(int.tryParse).toList();
    if (parts.contains(null)) return null;
    if (parts.length == 3) {
      return Duration(hours: parts[0]!, minutes: parts[1]!, seconds: parts[2]!);
    }
    if (parts.length == 2) {
      return Duration(minutes: parts[0]!, seconds: parts[1]!);
    }
    return null;
  }

  Future<Map<String, String>> _getCategories(
    String base,
    String username,
    String password,
    String type,
  ) async {
    final url =
        '$base/player_api.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}&action=get_${type}_categories';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return {};
      final List<dynamic> data = jsonDecode(response.body) as List;
      final map = <String, String>{};
      for (final cat in data) {
        map[cat['category_id']?.toString() ?? ''] =
            cat['category_name']?.toString() ?? 'Uncategorized';
      }
      return map;
    } catch (_) {
      return {};
    }
  }
}
