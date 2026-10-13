import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/content_type.dart';

enum DownloadStatus { queued, running, paused, completed, failed }

class DownloadItem {
  final Channel channel;
  DownloadStatus status;
  int received;
  int total;
  String? error;
  final String path;
  final int addedAt;

  DownloadItem({
    required this.channel,
    required this.path,
    this.status = DownloadStatus.queued,
    this.received = 0,
    this.total = 0,
    this.error,
    required this.addedAt,
  });

  String get id => channel.id;
  double? get progress =>
      total > 0 ? (received / total).clamp(0, 1).toDouble() : null;

  Map<String, dynamic> toJson() => {
        'channel': channel.toMap(),
        'status': status.name,
        'received': received,
        'total': total,
        'error': error,
        'path': path,
        'addedAt': addedAt,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> m) => DownloadItem(
        channel:
            Channel.fromMap(Map<String, dynamic>.from(m['channel'] as Map)),
        path: m['path'] as String,
        status: DownloadStatus.values.firstWhere(
          (s) => s.name == m['status'],
          orElse: () => DownloadStatus.paused,
        ),
        received: (m['received'] as num?)?.toInt() ?? 0,
        total: (m['total'] as num?)?.toInt() ?? 0,
        error: m['error'] as String?,
        addedAt: (m['addedAt'] as num?)?.toInt() ?? 0,
      );
}

/// Offline copies of single films and episodes.
///
/// Only direct, unprotected files (Xtream VOD/episodes: mp4, mkv, avi, ts…)
/// are offered; live channels and HLS/DASH playlists are excluded. One
/// download runs at a time and resumes with HTTP Range after pause, errors or
/// app restarts. Video files stay on the device only.
class DownloadService extends ChangeNotifier {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  static const _prefsKey = 'offline_downloads_v1';
  final Map<String, DownloadItem> _items = {};
  bool _loaded = false;
  String? _activeId;
  StreamSubscription<List<int>>? _sub;
  IOSink? _sink;
  http.Client? _client;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  List<DownloadItem> get items => _items.values.toList()
    ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  DownloadItem? itemFor(String id) => _items[id];

  int get usedBytes => _items.values.fold(0, (s, i) => s + i.received);

  /// Pure eligibility rule, also used by tests.
  static bool canDownload(Channel c) {
    if (c.isSeriesFolder || c.type == ContentType.live) return false;
    final uri = Uri.tryParse(c.url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return false;
    }
    final path = uri.path.toLowerCase();
    if (path.endsWith('.m3u8') ||
        path.endsWith('.m3u') ||
        path.endsWith('.mpd')) {
      return false;
    }
    return true;
  }

  static String extensionFor(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    final slash = path.lastIndexOf('/');
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot < slash) return 'mp4';
    final ext = path.substring(dot + 1);
    return RegExp(r'^[a-z0-9]{2,4}$').hasMatch(ext) ? ext : 'mp4';
  }

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        for (final m in jsonDecode(raw) as List) {
          final item = DownloadItem.fromJson(Map<String, dynamic>.from(m));
          if (item.status == DownloadStatus.completed &&
              !File(item.path).existsSync()) {
            continue;
          }
          // An interrupted download continues from where it stopped.
          if (item.status == DownloadStatus.running) {
            item.status = DownloadStatus.queued;
          }
          _items[item.id] = item;
        }
      }
    } catch (e) {
      debugPrint('Downloads: lettura non riuscita $e');
    }
    notifyListeners();
    _pump();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_items.values.map((i) => i.toJson()).toList()),
    );
  }

  /// Channel to play: the local file when the download is complete.
  Channel playable(Channel c) {
    final item = _items[c.id];
    if (item == null || item.status != DownloadStatus.completed) return c;
    if (!File(item.path).existsSync()) return c;
    return c.copyWith(url: Uri.file(item.path).toString());
  }

  Future<void> start(Channel channel) async {
    await init();
    if (!canDownload(channel)) return;
    final existing = _items[channel.id];
    if (existing != null) {
      if (existing.status == DownloadStatus.paused ||
          existing.status == DownloadStatus.failed) {
        existing.status = DownloadStatus.queued;
        existing.error = null;
      }
    } else {
      final dir = await _dir();
      final safe = channel.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      _items[channel.id] = DownloadItem(
        channel: channel,
        path: '${dir.path}/$safe.${extensionFor(channel.url)}',
        addedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    notifyListeners();
    await _save();
    _pump();
  }

  Future<void> pause(String id) async {
    final item = _items[id];
    if (item == null) return;
    if (_activeId == id) await _stopActive();
    if (item.status != DownloadStatus.completed) {
      item.status = DownloadStatus.paused;
    }
    notifyListeners();
    await _save();
    _pump();
  }

  Future<void> remove(String id) async {
    if (_activeId == id) await _stopActive();
    final item = _items.remove(id);
    if (item != null) {
      try {
        final f = File(item.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    notifyListeners();
    await _save();
    _pump();
  }

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _stopActive() async {
    final id = _activeId;
    _activeId = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    _client?.close();
    _client = null;
    final item = id == null ? null : _items[id];
    if (item != null) {
      try {
        item.received = await File(item.path).length();
      } catch (_) {}
    }
  }

  void _pump() {
    if (_activeId != null) return;
    final next = _items.values
        .where((i) => i.status == DownloadStatus.queued)
        .toList()
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    if (next.isEmpty) return;
    unawaited(_run(next.first));
  }

  Future<void> _run(DownloadItem item) async {
    _activeId = item.id;
    item.status = DownloadStatus.running;
    item.error = null;
    notifyListeners();
    final file = File(item.path);
    var offset = await file.exists() ? await file.length() : 0;
    final client = http.Client();
    _client = client;
    try {
      final req = http.Request('GET', Uri.parse(item.channel.url));
      if (offset > 0) req.headers['Range'] = 'bytes=$offset-';
      final res = await client.send(req);
      if (_activeId != item.id) return;
      if (res.statusCode == 416 && offset > 0) {
        _finish(item, offset);
        return;
      }
      if (res.statusCode != 200 && res.statusCode != 206) {
        throw HttpException('Il provider ha risposto ${res.statusCode}');
      }
      final type = res.headers['content-type'] ?? '';
      if (type.contains('mpegurl') || type.contains('text/html')) {
        throw const HttpException('Contenuto non scaricabile');
      }
      if (res.statusCode == 200) offset = 0; // no resume support: restart
      final len = res.contentLength ?? 0;
      item.total = len > 0 ? offset + len : 0;
      item.received = offset;
      _sink = file.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      final done = Completer<void>();
      _sub = res.stream.listen(
        (chunk) {
          _sink?.add(chunk);
          item.received += chunk.length;
          final now = DateTime.now();
          if (now.difference(_lastNotify).inMilliseconds > 500) {
            _lastNotify = now;
            notifyListeners();
          }
        },
        onError: (Object e) {
          if (!done.isCompleted) done.completeError(e);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future;
      await _sink?.flush();
      await _sink?.close();
      _sink = null;
      if (_activeId != item.id) return;
      if (item.total > 0 && item.received < item.total) {
        throw const HttpException('Connessione interrotta');
      }
      _finish(item, item.received);
    } catch (e) {
      if (_activeId != item.id) return; // paused or removed by the user
      try {
        await _sink?.close();
      } catch (_) {}
      _sink = null;
      item.status = DownloadStatus.failed;
      item.error = e is FileSystemException
          ? 'Spazio insufficiente o memoria non scrivibile'
          : e is HttpException
              ? e.message
              : 'Rete non disponibile';
      _activeId = null;
      notifyListeners();
      await _save();
      _pump();
    } finally {
      client.close();
      if (_client == client) _client = null;
    }
  }

  void _finish(DownloadItem item, int bytes) {
    item.status = DownloadStatus.completed;
    item.received = bytes;
    item.total = bytes;
    _activeId = null;
    _sub = null;
    notifyListeners();
    unawaited(_save());
    _pump();
  }
}

String formatBytes(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}
