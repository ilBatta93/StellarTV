import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/channel.dart';
import '../models/content_type.dart';
import 'series_grouping.dart';
import 'source_login_result.dart';
import 'xtream_downloader.dart' show CatalogProgress;

/// Whole catalog read from a single list address.
class LinkCatalog {
  const LinkCatalog(this.channels, {this.guideUrl});
  final List<Channel> channels;

  /// Guide address announced in the list header (`url-tvg`), if any.
  final String? guideUrl;

  List<Channel> section(ContentType type) => [
    for (final c in channels)
      if (c.type == type ||
          (type == ContentType.series && c.type == ContentType.anime))
        c,
  ];
}

class LinkSourceException implements Exception {
  const LinkSourceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads a text list of entries (`#EXTINF` header + address per entry) into
/// catalog items. Download and parsing stay off the UI thread.
class LinkSource {
  static const _userAgents = [
    'StellarTV/1.0',
    'VLC/3.0.20 LibVLC/3.0.20',
    'okhttp/4.12.0',
  ];

  /// Hard cap: a text list larger than this is not a media list.
  static const maxBytes = 300 * 1024 * 1024;

  /// Checks that [url] answers with a list before anything is saved.
  static Future<SourceLoginResult> check(String url) async {
    final invalid = invalidSourceAddress(url);
    if (invalid != null) return invalid;
    try {
      final head = await _download(url, limit: 64 * 1024);
      final text = utf8.decode(head, allowMalformed: true).trimLeft();
      final stripped = text.startsWith('﻿') ? text.substring(1) : text;
      if (stripped.startsWith('#EXTM3U') || stripped.contains('#EXTINF')) {
        return const SourceLoginResult(SourceLoginKind.ok);
      }
      return const SourceLoginResult(SourceLoginKind.wrongService);
    } on _HttpStatus catch (e) {
      return classifySourceLogin(statusCode: e.code);
    } catch (error) {
      return classifySourceLogin(error: error);
    }
  }

  static Future<LinkCatalog> load(
    String url, {
    void Function(CatalogProgress progress)? onProgress,
  }) async {
    final Uint8List bytes;
    try {
      bytes = await _download(url, limit: maxBytes, onProgress: onProgress);
    } on _HttpStatus catch (e) {
      throw LinkSourceException(
        'Il server ha risposto con errore ${e.code}. Controlla l’indirizzo.',
      );
    } on TimeoutException {
      throw const LinkSourceException(
        'Il server non risponde. Controlla la connessione e riprova.',
      );
    } on SocketException {
      throw const LinkSourceException(
        'Impossibile raggiungere il server. Controlla la connessione e riprova.',
      );
    }
    final catalog = await Isolate.run(() => parse(bytes));
    if (catalog.channels.isEmpty) {
      throw const LinkSourceException(
        'L’indirizzo non contiene elementi riproducibili.',
      );
    }
    onProgress?.call(
      CatalogProgress(bytes: bytes.length, items: catalog.channels.length),
    );
    return catalog;
  }

  static Future<Uint8List> _download(
    String url, {
    required int limit,
    void Function(CatalogProgress progress)? onProgress,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < _userAgents.length; attempt++) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20)
        ..idleTimeout = const Duration(seconds: 10)
        ..userAgent = _userAgents[attempt];
      try {
        final request = await client
            .getUrl(Uri.parse(url.trim()))
            .timeout(const Duration(seconds: 25));
        if (attempt > 0) {
          request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        }
        final response = await request.close().timeout(
          const Duration(seconds: 60),
        );
        if (response.statusCode != 200) {
          await response.drain<void>().catchError((_) {});
          // Some servers refuse unknown clients: try the next identity.
          if (response.statusCode == 403 && attempt < _userAgents.length - 1) {
            lastError = _HttpStatus(response.statusCode);
            continue;
          }
          throw _HttpStatus(response.statusCode);
        }
        final builder = BytesBuilder(copy: false);
        var lastReport = 0;
        await for (final chunk in response.timeout(
          const Duration(seconds: 45),
        )) {
          builder.add(chunk);
          if (builder.length >= limit) break;
          if (builder.length - lastReport > 256 * 1024) {
            lastReport = builder.length;
            onProgress?.call(CatalogProgress(bytes: builder.length));
          }
        }
        return builder.takeBytes();
      } on _HttpStatus {
        rethrow;
      } catch (e) {
        lastError = e;
      } finally {
        client.close(force: true);
      }
    }
    throw lastError ?? const SocketException('rete');
  }

  static final _attr = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');
  static final _fileExt = RegExp(
    r'\.(mp4|mkv|avi|mov|wmv|m4v|webm|mpg|mpeg)(\?|$)',
    caseSensitive: false,
  );

  /// Pure parser, public for tests.
  static LinkCatalog parse(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    final lines = const LineSplitter().convert(text);
    final channels = <Channel>[];
    final seen = <String>{};
    String? guide;
    Map<String, String>? attrs;
    String? title;
    String? groupLine;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTM3U')) {
        final a = _attributes(line);
        final g = a['url-tvg'] ?? a['x-tvg-url'] ?? a['tvg-url'];
        if (g != null && g.trim().isNotEmpty) {
          guide = g.split(',').first.trim();
        }
        continue;
      }
      if (line.startsWith('#EXTINF')) {
        final comma = _titleComma(line);
        attrs = _attributes(comma < 0 ? line : line.substring(0, comma));
        title = comma < 0 ? '' : line.substring(comma + 1).trim();
        groupLine = null;
        continue;
      }
      if (line.startsWith('#EXTGRP:')) {
        groupLine = line.substring(8).trim();
        continue;
      }
      if (line.startsWith('#')) continue;
      if (attrs == null) continue; // address without a header
      final url = line;
      final a = attrs;
      attrs = null;
      if (!seen.add(url)) continue;
      final name = (title?.isNotEmpty ?? false)
          ? title!
          : (a['tvg-name'] ?? 'Senza nome');
      final group = (a['group-title']?.trim().isNotEmpty ?? false)
          ? a['group-title']!.trim()
          : (groupLine?.isNotEmpty ?? false)
          ? groupLine!
          : 'Senza categoria';
      var type = SeriesGrouping.inferType(url: url, group: group, name: name);
      if (type == ContentType.live && _fileExt.hasMatch(url)) {
        type = ContentType.movie;
      }
      final archive = int.tryParse(
        a['catchup-days'] ?? a['tvg-rec'] ?? a['timeshift'] ?? '',
      );
      String? seriesKey, seriesName;
      int? season, episode;
      if (type == ContentType.series || type == ContentType.anime) {
        final parsed = SeriesGrouping.parseTitle(name);
        seriesName = parsed.seriesName;
        season = parsed.season;
        episode = parsed.episode;
        seriesKey = SeriesGrouping.seriesKey(seriesName, group);
      }
      channels.add(
        Channel(
          id: 'link_${_hash(url)}',
          name: name,
          url: url,
          logo: a['tvg-logo'] ?? a['logo'] ?? '',
          group: group,
          type: type,
          tvgId: _blankToNull(a['tvg-id']),
          tvgName: _blankToNull(a['tvg-name']),
          language: _blankToNull(a['tvg-language']),
          country: _blankToNull(a['tvg-country']),
          seriesKey: seriesKey,
          seriesName: seriesName,
          season: season,
          episode: episode,
          archiveDays: type == ContentType.live ? (archive ?? 0) : 0,
          releaseDate: Channel.parseReleaseDate(a['tvg-year'] ?? a['year']),
        ),
      );
    }
    return LinkCatalog(channels, guideUrl: guide);
  }

  /// The title starts after the first comma outside quoted attributes.
  static int _titleComma(String line) {
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line.codeUnitAt(i);
      if (c == 0x22) quoted = !quoted;
      if (c == 0x2C && !quoted) return i;
    }
    return -1;
  }

  static Map<String, String> _attributes(String text) => {
    for (final m in _attr.allMatches(text)) m[1]!.toLowerCase(): m[2]!,
  };

  static String? _blankToNull(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  /// Stable id from the address (FNV-1a, 52 bits so it fits a JS number on
  /// the web build too).
  static String _hash(String s) {
    var h = 0xcbf29ce484222;
    for (final unit in utf8.encode(s)) {
      h ^= unit;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFF;
    }
    return h.toRadixString(36);
  }
}

class _HttpStatus implements Exception {
  const _HttpStatus(this.code);
  final int code;
}
