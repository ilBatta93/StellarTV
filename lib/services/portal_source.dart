import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/series_details.dart';
import '../models/source_access.dart';
import 'series_grouping.dart';
import 'source_login_result.dart';
import 'xtream_downloader.dart' show CatalogProgress;

class PortalException implements Exception {
  const PortalException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Client for set-top-box portals reached with a MAC address.
///
/// Items keep a `stvportal://` address: the playable link is created by the
/// portal only when playback starts ([resolve]), because portal links carry
/// short-lived tokens.
class PortalSource {
  PortalSource(String portal, String mac, {http.Client? client})
    : mac = SourceAccess.normalizeMac(mac) ?? mac.trim().toUpperCase(),
      _root = rootOf(portal),
      _client = client ?? http.Client();

  final String mac;
  final String _root;
  final http.Client _client;
  String? _endpoint;
  String? _token;

  static const scheme = 'stvportal';
  static const _ua =
      'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 '
      '(KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3';

  /// Portal root without the `/c/` page the boxes open.
  static String rootOf(String portal) {
    var url = portal.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    url = url.replaceAll(RegExp(r'/+$'), '');
    url = url.replaceAll(RegExp(r'/(c|index\.html|portal\.php)$'), '');
    url = url.replaceAll(RegExp(r'/server/load\.php$'), '');
    return url.replaceAll(RegExp(r'/+$'), '');
  }

  List<String> get _endpoints => _root.endsWith('/stalker_portal')
      ? ['$_root/server/load.php']
      : [
          '$_root/portal.php',
          '$_root/server/load.php',
          '$_root/stalker_portal/server/load.php',
        ];

  Map<String, String> get _headers => {
    'User-Agent': _ua,
    'X-User-Agent': 'Model: MAG250; Link: WiFi',
    'Referer': '$_root/c/',
    'Accept': '*/*',
    'Cookie':
        'mac=${Uri.encodeComponent(mac)}; stb_lang=en; '
        'timezone=${Uri.encodeComponent('Europe/Rome')}',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<Object?> _get(String endpoint, Map<String, String> query) async {
    final uri = Uri.parse(endpoint)
        .replace(queryParameters: {...query, 'JsHttpRequest': '1-xml'});
    final res = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const _Unauthorized();
    }
    if (res.statusCode != 200) throw _Status(res.statusCode);
    final body = res.body.trim();
    if (body.toLowerCase().contains('authorization failed')) {
      throw const _Unauthorized();
    }
    final decoded = jsonDecode(body);
    return decoded is Map ? decoded['js'] : null;
  }

  /// Handshake and profile; finds which address the portal answers on.
  Future<void> connect() async {
    _token = null;
    Object? lastError;
    for (final endpoint in _endpoint == null ? _endpoints : [_endpoint!]) {
      try {
        final js = await _get(endpoint, {
          'type': 'stb',
          'action': 'handshake',
          'token': '',
          'prehash': '0',
        });
        final token = js is Map ? js['token']?.toString() ?? '' : '';
        if (token.isEmpty) {
          lastError = const FormatException('handshake');
          continue;
        }
        _endpoint = endpoint;
        _token = token;
        await _profile();
        return;
      } catch (e) {
        if (e is _Unauthorized && _token != null) rethrow;
        lastError = e;
      }
    }
    throw lastError ?? const FormatException('portal');
  }

  Future<void> _profile() async {
    final sn = crypto.md5
        .convert(utf8.encode(mac))
        .toString()
        .toUpperCase()
        .substring(0, 13);
    final id = crypto.sha256.convert(utf8.encode(mac)).toString().toUpperCase();
    final js = await _get(_endpoint!, {
      'type': 'stb',
      'action': 'get_profile',
      'hd': '1',
      'ver':
          'ImageDescription: 0.2.18-r23-250; ImageDate: Thu Sep 13 11:31:16 '
          'EEST 2018; PORTAL version: 5.6.2; API Version: JS API version: 343; '
          'STB API version: 146; Player Engine version: 0x58c',
      'num_banks': '2',
      'sn': sn,
      'stb_type': 'MAG250',
      'image_version': '218',
      'video_out': 'hdmi',
      'device_id': id,
      'device_id2': id,
      'signature': '',
      'auth_second_step': '1',
      'hw_version': '1.7-BD-00',
      'not_valid_token': '0',
    });
    // Portals answer an unknown MAC with an empty or blocked profile.
    if (js is! Map || js['blocked']?.toString() == '1') {
      throw const _Unauthorized();
    }
  }

  /// Retries once with a fresh token when the portal drops the session.
  Future<Object?> _call(Map<String, String> query) async {
    if (_token == null) await connect();
    try {
      return await _get(_endpoint!, query);
    } on _Unauthorized {
      await connect();
      return _get(_endpoint!, query);
    }
  }

  static Future<SourceLoginResult> check(String portal, String mac) async {
    final invalid = invalidSourceAddress(
      portal.contains('://') ? portal : 'http://$portal',
    );
    if (invalid != null) return invalid;
    if (SourceAccess.normalizeMac(mac) == null) {
      return const SourceLoginResult(SourceLoginKind.badCredentials);
    }
    final source = PortalSource(portal, mac);
    try {
      await source.connect();
      // Some portals hand a token to any MAC: the channel genres answer
      // only for a registered one.
      final genres = await source._call({
        'type': 'itv',
        'action': 'get_genres',
      });
      if (genres is! List) {
        return const SourceLoginResult(SourceLoginKind.badCredentials);
      }
      return const SourceLoginResult(SourceLoginKind.ok);
    } on _Unauthorized {
      return const SourceLoginResult(SourceLoginKind.badCredentials);
    } on _Status catch (e) {
      return classifySourceLogin(statusCode: e.code);
    } catch (error) {
      return classifySourceLogin(error: error);
    } finally {
      source.close();
    }
  }

  void close() => _client.close();

  // ---- Catalog -------------------------------------------------------------

  Future<List<Channel>> section(
    ContentType type, {
    void Function(CatalogProgress progress)? onProgress,
  }) => _guard(() async {
    return switch (type) {
      ContentType.live => _live(onProgress),
      ContentType.movie => _ondemand('vod', ContentType.movie, onProgress),
      _ => _ondemand('series', ContentType.series, onProgress),
    };
  });

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on _Unauthorized {
      throw const PortalException(
        'Il portale non riconosce questo indirizzo MAC o l’accesso è scaduto.',
      );
    } on _Status catch (e) {
      throw PortalException('Il portale ha risposto con errore ${e.code}.');
    } on TimeoutException {
      throw const PortalException(
        'Il portale non risponde. Controlla la connessione e riprova.',
      );
    } on SocketException {
      throw const PortalException(
        'Impossibile raggiungere il portale. Controlla la connessione.',
      );
    } on FormatException {
      throw const PortalException(
        'L’indirizzo non corrisponde a un portale. Controlla l’URL.',
      );
    }
  }

  Future<Map<String, String>> _genres(String module) async {
    final js = await _call({
      'type': module,
      'action': module == 'itv' ? 'get_genres' : 'get_categories',
    });
    return {
      if (js is List)
        for (final g in js)
          if (g is Map && g['id'] != null && g['id'].toString() != '*')
            g['id'].toString(): (g['title'] ?? g['name'] ?? '').toString(),
    };
  }

  Future<List<Channel>> _live(
    void Function(CatalogProgress progress)? onProgress,
  ) async {
    final genres = await _genres('itv');
    final js = await _call({'type': 'itv', 'action': 'get_all_channels'});
    final data = js is Map ? js['data'] : js;
    final out = <Channel>[];
    if (data is List) {
      for (final c in data) {
        if (c is! Map) continue;
        final cmd = c['cmd']?.toString() ?? '';
        final id = c['id']?.toString() ?? '';
        if (cmd.isEmpty || id.isEmpty) continue;
        out.add(
          Channel(
            id: 'portal_itv_$id',
            name: (c['name'] ?? '').toString(),
            url: address('itv', cmd),
            logo: _image(c['logo']),
            group: genres[c['tv_genre_id']?.toString()] ?? 'Senza categoria',
            type: ContentType.live,
            tvgId: _blank(c['xmltv_id']),
          ),
        );
      }
    }
    onProgress?.call(CatalogProgress(items: out.length));
    return out;
  }

  /// On-demand lists come in small pages per category: a few categories at
  /// a time, with a page cap so a huge portal cannot run forever.
  Future<List<Channel>> _ondemand(
    String module,
    ContentType type,
    void Function(CatalogProgress progress)? onProgress,
  ) async {
    Map<String, String> genres;
    try {
      genres = await _genres(module);
    } on _Status {
      if (module == 'series') return const []; // portal without series
      rethrow;
    } on FormatException {
      if (module == 'series') return const [];
      rethrow;
    }
    final out = <Channel>[];
    final seen = <String>{};
    var pagesLeft = 4000;
    final queue = genres.entries.toList();
    Future<void> worker() async {
      while (queue.isNotEmpty && pagesLeft > 0) {
        final genre = queue.removeLast();
        for (var page = 1; pagesLeft > 0; page++) {
          pagesLeft--;
          final js = await _call({
            'type': module,
            'action': 'get_ordered_list',
            'category': genre.key,
            'genre': '*',
            'sortby': 'added',
            'p': '$page',
          });
          if (js is! Map) break;
          final data = js['data'];
          if (data is! List || data.isEmpty) break;
          for (final item in data) {
            if (item is! Map) continue;
            final c = _item(module, type, item, genre.value);
            if (c != null && seen.add(c.id)) out.add(c);
          }
          onProgress?.call(CatalogProgress(items: out.length));
          final total = int.tryParse('${js['total_items'] ?? ''}') ?? 0;
          final per = int.tryParse('${js['max_page_items'] ?? ''}') ?? 14;
          if (per <= 0 || page * per >= total) break;
        }
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) worker()]);
    // Movies a portal marks as series belong to the Serie TV section.
    if (type == ContentType.movie) {
      out.removeWhere((c) => c.isSeriesFolder);
    }
    return out;
  }

  Channel? _item(String module, ContentType type, Map item, String group) {
    final id = item['id']?.toString() ?? '';
    final name = (item['name'] ?? item['o_name'] ?? '').toString();
    if (id.isEmpty || name.isEmpty) return null;
    final isSeries =
        module == 'series' ||
        item['is_series'] == 1 ||
        item['is_series'] == '1' ||
        item['is_series'] == true;
    final cmd = item['cmd']?.toString() ?? '';
    final logo = _image(item['screenshot_uri'] ?? item['cover']);
    final plot = _blank(item['description']);
    final release = Channel.parseReleaseDate(item['year']);
    final added = DateTime.tryParse('${item['added'] ?? ''}');
    if (isSeries) {
      final key = 'portal:$module:$id';
      return Channel(
        id: 'portal_${module}_s_$id',
        name: name,
        url: '',
        logo: logo,
        group: group.isEmpty ? 'Senza categoria' : group,
        type: SeriesGrouping.isAnimeGroup(group)
            ? ContentType.anime
            : ContentType.series,
        seriesKey: key,
        seriesName: name,
        plot: plot,
        isSeriesFolder: true,
        releaseDate: release,
        addedAt: added == null ? 0 : added.millisecondsSinceEpoch ~/ 1000,
      );
    }
    if (cmd.isEmpty || type != ContentType.movie) return null;
    return Channel(
      id: 'portal_vod_$id',
      name: name,
      url: address('vod', cmd),
      logo: logo,
      group: group.isEmpty ? 'Senza categoria' : group,
      type: ContentType.movie,
      plot: plot,
      releaseDate: release,
      addedAt: added == null ? 0 : added.millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// Seasons and episodes of a portal series folder.
  Future<SeriesDetails> seriesDetails(Channel series) => _guard(() async {
    final parts = (series.seriesKey ?? '').split(':');
    if (parts.length != 3 || parts.first != 'portal') {
      throw const PortalException('Serie non disponibile.');
    }
    final module = parts[1], id = parts[2];
    final js = await _call({
      'type': module,
      'action': 'get_ordered_list',
      'movie_id': id,
      'season_id': '0',
      'episode_id': '0',
      'p': '1',
    });
    final data = js is Map ? js['data'] : null;
    final seasons = <SeriesSeason>[];
    if (data is List) {
      var fallback = 0;
      for (final s in data) {
        if (s is! Map) continue;
        fallback++;
        final cmd = s['cmd']?.toString() ?? '';
        final name = (s['name'] ?? '').toString();
        final number =
            int.tryParse(RegExp(r'(\d+)').firstMatch(name)?.group(1) ?? '') ??
            fallback;
        final list = s['series'];
        if (cmd.isEmpty || list is! List) continue;
        seasons.add(
          SeriesSeason(
            number: number,
            name: 'Stagione $number',
            episodes: [
              for (final e in list)
                if (int.tryParse('$e') case final ep?)
                  SeriesEpisode(
                    channel: Channel(
                      id: 'portal_${module}_e_${id}_${number}_$ep',
                      name:
                          '${series.displaySeriesName} S${'$number'.padLeft(2, '0')} '
                          'E${'$ep'.padLeft(2, '0')}',
                      url: address('vod', cmd, episode: ep),
                      logo: series.logo,
                      group: series.group,
                      type: ContentType.series,
                      seriesKey: series.seriesKey,
                      seriesName: series.displaySeriesName,
                      season: number,
                      episode: ep,
                    ),
                    season: number,
                    number: ep,
                    title: 'Episodio $ep',
                  ),
            ],
          ),
        );
      }
    }
    seasons.sort((a, b) => a.number.compareTo(b.number));
    return SeriesDetails(
      series: series,
      overview: series.plot ?? '',
      seasons: seasons,
    );
  });

  // ---- Playback ------------------------------------------------------------

  static String address(String module, String cmd, {int? episode}) => Uri(
    scheme: scheme,
    host: module,
    queryParameters: {'cmd': cmd, 'series': ?episode?.toString()},
  ).toString();

  static bool isAddress(String url) => url.startsWith('$scheme:');

  /// Asks the portal for the playable link of a `stvportal://` address.
  Future<String> resolve(String url) => _guard(() async {
    final uri = Uri.parse(url);
    final module = uri.host == 'itv' ? 'itv' : 'vod';
    final cmd = uri.queryParameters['cmd'] ?? '';
    final js = await _call({
      'type': module,
      'action': 'create_link',
      'cmd': cmd,
      'series': uri.queryParameters['series'] ?? '',
      'forced_storage': 'undefined',
      'disable_ad': '0',
      'download': '0',
    });
    final created = js is Map ? js['cmd']?.toString() ?? '' : '';
    final link = linkFromCmd(created) ?? linkFromCmd(cmd);
    if (link == null) {
      throw const PortalException('Il portale non ha fornito il flusso.');
    }
    return link;
  });

  /// `ffmpeg http://…` → `http://…`; null when there is no usable address.
  static String? linkFromCmd(String cmd) {
    for (final part in cmd.trim().split(RegExp(r'\s+'))) {
      final uri = Uri.tryParse(part);
      if (uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty &&
          uri.host != 'localhost') {
        return part;
      }
    }
    return null;
  }

  String _image(Object? raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return '';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    final origin = Uri.parse(_root);
    return origin.replace(path: s.startsWith('/') ? s : '/$s').toString();
  }

  static String? _blank(Object? s) {
    final t = s?.toString().trim() ?? '';
    return t.isEmpty ? null : t;
  }
}

/// The portal session of the stored access, shared by player, downloads and
/// series pages so one token serves them all.
class PortalSession {
  PortalSession._();
  static PortalSource? _source;
  static String? _key;

  static PortalSource of(String portal, String mac) {
    final key = '$portal|$mac';
    if (_key != key || _source == null) {
      _source?.close();
      _source = PortalSource(portal, mac);
      _key = key;
    }
    return _source!;
  }

  static void reset() {
    _source?.close();
    _source = null;
    _key = null;
  }
}

class _Unauthorized implements Exception {
  const _Unauthorized();
}

class _Status implements Exception {
  const _Status(this.code);
  final int code;
}
