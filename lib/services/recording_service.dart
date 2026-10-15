import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/content_type.dart';

enum RecordingStatus { scheduled, recording, completed, failed, cancelled }

class RecordingItem {
  final String id;
  final Channel channel;
  final String title;
  final String path;
  final DateTime start;
  DateTime end;
  RecordingStatus status;
  int bytes;
  String? error;

  RecordingItem({
    required this.id,
    required this.channel,
    required this.title,
    required this.path,
    required this.start,
    required this.end,
    this.status = RecordingStatus.scheduled,
    this.bytes = 0,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'channel': channel.toMap(),
        'title': title,
        'path': path,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'status': status.name,
        'bytes': bytes,
        'error': error,
      };

  factory RecordingItem.fromJson(Map<String, dynamic> m) => RecordingItem(
        id: m['id'] as String,
        channel:
            Channel.fromMap(Map<String, dynamic>.from(m['channel'] as Map)),
        title: m['title'] as String? ?? '',
        path: m['path'] as String,
        start: DateTime.parse(m['start'] as String),
        end: DateTime.parse(m['end'] as String),
        status: RecordingStatus.values.firstWhere(
          (s) => s.name == m['status'],
          orElse: () => RecordingStatus.failed,
        ),
        bytes: (m['bytes'] as num?)?.toInt() ?? 0,
        error: m['error'] as String?,
      );
}

/// Live channel recordings: "Registra ora" from the player and programmes
/// scheduled from the guide. The stream is saved as it arrives (no
/// re-encoding: no extra CPU, heat or quality loss). Files stay on the
/// device; recordings run while the app is open.
class RecordingService extends ChangeNotifier {
  RecordingService._();
  static final RecordingService instance = RecordingService._();

  static const _prefsKey = 'live_recordings_v1';
  static const defaultDuration = Duration(minutes: 60);
  final Map<String, RecordingItem> _items = {};
  final Map<String, _Job> _jobs = {};
  final Map<String, Timer> _timers = {};
  bool _loaded = false;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  List<RecordingItem> get items => _items.values.toList()
    ..sort((a, b) => b.start.compareTo(a.start));

  /// Only plain (non HLS/DASH) live streams can be saved as they arrive.
  static bool canRecord(Channel c) {
    if (c.type != ContentType.live) return false;
    final u = c.url.toLowerCase();
    if (!u.startsWith('http')) return false;
    return !(u.contains('.m3u8') || u.contains('.mpd'));
  }

  RecordingItem? activeFor(Channel c) {
    for (final i in _items.values) {
      if (i.channel.id == c.id && i.status == RecordingStatus.recording) {
        return i;
      }
    }
    return null;
  }

  bool isScheduled(Channel c, DateTime start) => _items.values.any(
        (i) =>
            i.channel.id == c.id &&
            i.start == start &&
            i.status == RecordingStatus.scheduled,
      );

  RecordingItem? scheduledFor(Channel c, DateTime start) {
    for (final i in _items.values) {
      if (i.channel.id == c.id &&
          i.start == start &&
          i.status == RecordingStatus.scheduled) {
        return i;
      }
    }
    return null;
  }

  int get usedBytes => _items.values.fold(0, (s, i) => s + i.bytes);

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        for (final m in jsonDecode(raw) as List) {
          final item = RecordingItem.fromJson(Map<String, dynamic>.from(m));
          _items[item.id] = item;
        }
      } catch (_) {}
    }
    final now = DateTime.now();
    for (final item in _items.values) {
      if (item.status == RecordingStatus.recording) {
        // The app was closed mid-recording: keep what was saved.
        final file = File(item.path);
        item.bytes = file.existsSync() ? file.lengthSync() : 0;
        if (item.end.isAfter(now)) {
          _begin(item);
        } else {
          item.status = item.bytes > 0
              ? RecordingStatus.completed
              : RecordingStatus.failed;
          item.error ??= item.bytes > 0 ? null : 'App chiusa durante la registrazione';
        }
      } else if (item.status == RecordingStatus.scheduled) {
        _arm(item);
      }
    }
    await _save();
    notifyListeners();
  }

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/recordings');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<RecordingItem?> _create(
    Channel channel,
    String title,
    DateTime start,
    DateTime end,
  ) async {
    await init();
    if (!canRecord(channel)) return null;
    final id = '${channel.id}_${start.millisecondsSinceEpoch}';
    final dir = await _dir();
    final item = RecordingItem(
      id: id,
      channel: channel,
      title: title.isEmpty ? channel.name : title,
      path: '${dir.path}/$id.ts',
      start: start,
      end: end,
    );
    _items[id] = item;
    return item;
  }

  /// Starts recording now, until [end] (e.g. end of the current programme)
  /// or for [defaultDuration].
  Future<RecordingItem?> recordNow(
    Channel channel, {
    String title = '',
    DateTime? end,
  }) async {
    final existing = activeFor(channel);
    if (existing != null) return existing;
    final now = DateTime.now();
    var stop = end ?? now.add(defaultDuration);
    if (!stop.isAfter(now.add(const Duration(minutes: 1)))) {
      stop = now.add(defaultDuration);
    }
    final item = await _create(channel, title, now, stop);
    if (item == null) return null;
    _begin(item);
    await _save();
    notifyListeners();
    return item;
  }

  /// Schedules a guide programme (a minute of margin before and after).
  Future<RecordingItem?> schedule(
    Channel channel, {
    required String title,
    required DateTime start,
    required DateTime end,
  }) async {
    final existing = scheduledFor(channel, start);
    if (existing != null) return existing;
    final item = await _create(
      channel,
      title,
      start,
      end.add(const Duration(minutes: 1)),
    );
    if (item == null) return null;
    _arm(item);
    await _save();
    notifyListeners();
    return item;
  }

  void _arm(RecordingItem item) {
    _timers.remove(item.id)?.cancel();
    final now = DateTime.now();
    if (!item.end.isAfter(now)) {
      item.status = RecordingStatus.failed;
      item.error = 'Orario passato con l\'app chiusa';
      return;
    }
    final wait = item.start.subtract(const Duration(minutes: 1)).difference(now);
    if (wait <= Duration.zero) {
      _begin(item);
    } else {
      _timers[item.id] = Timer(wait, () {
        _begin(item);
        _save();
        notifyListeners();
      });
    }
  }

  void _begin(RecordingItem item) {
    item.status = RecordingStatus.recording;
    item.error = null;
    final job = _Job(item, this);
    _jobs[item.id] = job;
    unawaited(job.run());
  }

  void _progress(RecordingItem item) {
    final now = DateTime.now();
    if (now.difference(_lastNotify) < const Duration(seconds: 1)) return;
    _lastNotify = now;
    notifyListeners();
  }

  Future<void> _finished(RecordingItem item, {String? error}) async {
    _jobs.remove(item.id);
    if (item.status == RecordingStatus.recording) {
      if (item.bytes > 0) {
        item.status = RecordingStatus.completed;
        item.error = error;
      } else {
        item.status = RecordingStatus.failed;
        item.error = error ?? 'Nessun dato ricevuto dal canale';
      }
    }
    await _save();
    notifyListeners();
  }

  /// Stops an active recording (keeping the file) or cancels a scheduled one.
  Future<void> stop(String id) async {
    final item = _items[id];
    if (item == null) return;
    _timers.remove(id)?.cancel();
    if (item.status == RecordingStatus.scheduled) {
      _items.remove(id);
    } else if (item.status == RecordingStatus.recording) {
      item.end = DateTime.now();
      await _jobs[id]?.cancel();
    }
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final item = _items[id];
    if (item == null) return;
    _timers.remove(id)?.cancel();
    await _jobs.remove(id)?.cancel();
    _items.remove(id);
    try {
      final f = File(item.path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    await _save();
    notifyListeners();
  }

  /// A finished recording as a playable, seekable local item.
  Channel playable(RecordingItem item) => item.channel.copyWith(
        id: 'rec:${item.id}',
        name: item.title,
        url: Uri.file(item.path).toString(),
        type: ContentType.movie,
        group: 'Registrazioni',
      );

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode([for (final i in _items.values) i.toJson()]),
    );
  }
}

class _Job {
  _Job(this.item, this.service);
  final RecordingItem item;
  final RecordingService service;
  http.Client? _client;
  StreamSubscription<List<int>>? _sub;
  IOSink? _sink;
  Timer? _endTimer;
  bool _cancelled = false;
  Completer<void>? _pass;

  Future<void> cancel() async {
    _cancelled = true;
    _endTimer?.cancel();
    await _sub?.cancel();
    _client?.close();
    if (!(_pass?.isCompleted ?? true)) _pass!.complete();
  }

  Future<void> run() async {
    final file = File(item.path);
    _sink = file.openWrite(mode: FileMode.append);
    _endTimer = Timer(
      item.end.difference(DateTime.now()),
      () => unawaited(cancel()),
    );
    var failures = 0;
    String? lastError;
    // Reconnects on drops until the end time, like a set-top box recorder.
    while (!_cancelled && DateTime.now().isBefore(item.end) && failures < 20) {
      try {
        _client = http.Client();
        final req = http.Request('GET', Uri.parse(item.channel.url))
          ..headers['User-Agent'] = 'StellarTV/1.0';
        final res = await _client!.send(req);
        if (res.statusCode >= 400) {
          throw HttpException('Il canale ha risposto ${res.statusCode}');
        }
        _pass = Completer<void>();
        _sub = res.stream.listen(
          (chunk) {
            _sink?.add(chunk);
            item.bytes += chunk.length;
            failures = 0;
            service._progress(item);
          },
          onDone: () {
            if (!(_pass?.isCompleted ?? true)) _pass!.complete();
          },
          onError: (Object e) {
            lastError = '$e';
            if (!(_pass?.isCompleted ?? true)) _pass!.complete();
          },
          cancelOnError: true,
        );
        await _pass!.future;
      } catch (e) {
        lastError = '$e';
      } finally {
        _client?.close();
      }
      if (_cancelled) break;
      failures++;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    _endTimer?.cancel();
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    await service._finished(
      item,
      error: failures >= 20 ? (lastError ?? 'Connessione interrotta') : null,
    );
  }
}

String formatRecordingBytes(int b) {
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) {
    return '${(b / 1024 / 1024).toStringAsFixed(0)} MB';
  }
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}
