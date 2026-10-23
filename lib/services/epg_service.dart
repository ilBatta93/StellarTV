import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../models/epg_data.dart';
import 'epg_downloader.dart';
export '../models/epg_data.dart';
export 'epg_downloader.dart' show EpgRefreshDeferred, EpgDownloadException;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

import 'sync_hooks.dart';
import 'playback_work_policy.dart';

/// Downloads and parses XMLTV guides (from the playlist and from sources
/// added by hand) and keeps a local copy so the guide is ready at startup.
class EpgService {
  EpgDownloadJob? _activeJob;
  void deferActiveDownload() => _activeJob?.cancel();
  static const _usePlaylistKey = 'epg_use_playlist';
  static const _sourcesKey = 'epg_sources';
  static const _intervalKey = 'epg_refresh_minutes';
  static const _lastRunKey = 'epg_last_run';

  Future<bool> usePlaylistGuide() async =>
      (await SharedPreferences.getInstance()).getBool(_usePlaylistKey) ?? true;

  Future<void> setUsePlaylistGuide(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_usePlaylistKey, value);

  Future<List<String>> manualSources() async =>
      (await SharedPreferences.getInstance()).getStringList(_sourcesKey) ??
      const [];

  Future<void> saveManualSources(List<String> urls) async {
    await (await SharedPreferences.getInstance()).setStringList(
      _sourcesKey,
      urls,
    );
    SyncHooks.settingsChanged();
  }

  /// Default: update the guide once a day.
  Future<int> intervalMinutes() async =>
      (await SharedPreferences.getInstance()).getInt(_intervalKey) ?? 1440;

  Future<void> saveIntervalMinutes(int minutes) async {
    await (await SharedPreferences.getInstance()).setInt(_intervalKey, minutes);
    SyncHooks.settingsChanged();
  }

  Future<DateTime?> lastRun() async => DateTime.tryParse(
    (await SharedPreferences.getInstance()).getString(_lastRunKey) ?? '',
  );

  Future<void> markRun() async => (await SharedPreferences.getInstance())
      .setString(_lastRunKey, DateTime.now().toIso8601String());

  static String sourceKey(List<String> sources) =>
      sha256.convert(utf8.encode(jsonEncode(sources))).toString();

  Future<File> _cacheFile(List<String> sources) async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/stellartv_epg_v2_${sourceKey(sources)}.json');
  }

  Future<EpgData> loadCache(List<String> sources) async {
    if (sources.isEmpty) return const EpgData();
    try {
      final path = (await _cacheFile(sources)).path;
      return await Isolate.run(() {
        final file = File(path);
        if (!file.existsSync()) return const EpgData();
        final json = jsonDecode(file.readAsStringSync());
        return json is Map<String, dynamic>
            ? EpgData.fromJson(json)
            : const EpgData();
      });
    } catch (_) {
      return const EpgData();
    }
  }

  /// Downloads every source and merges them (first source wins per channel).
  /// Returns the merged guide; throws when no source could be read.
  Future<EpgData> fetch(List<String> urls) async {
    final policy = PlaybackWorkPolicy.instance;
    final cacheFile = await _cacheFile(urls);
    final staged =
        '${cacheFile.path}.${DateTime.now().microsecondsSinceEpoch}.pending';
    final job = EpgDownloadJob(List.of(urls), staged);
    _activeJob = job;
    var canceled = false;
    void cancelIfBlocked() {
      if (policy.blocksGuide) {
        canceled = true;
        job.cancel();
      }
    }

    policy.addListener(cancelIfBlocked);
    try {
      if (policy.blocksGuide) throw EpgRefreshDeferred();
      final data = await job.run();
      if (canceled || policy.blocksGuide) throw EpgRefreshDeferred();
      // Same event turn as guard: old cache survives failed/canceled downloads.
      File(staged).renameSync(cacheFile.path);
      return data;
    } finally {
      if (identical(_activeJob, job)) _activeJob = null;
      policy.removeListener(cancelIfBlocked);
      final file = File(staged);
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
