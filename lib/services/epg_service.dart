import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'epg_archive.dart';
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

  Future<Directory> _cacheDirectory(List<String> sources) async {
    final directory = await getApplicationSupportDirectory();
    return Directory(
      '${directory.path}${Platform.pathSeparator}stellartv_epg_v3_${sourceKey(sources)}',
    );
  }

  Future<EpgGuideSnapshot> loadCache(List<String> sources) async {
    if (sources.isEmpty) return EpgGuideSnapshot.empty;
    try {
      final support = await getApplicationSupportDirectory();
      final header = await Isolate.run(
        () => loadEpgCacheHeader(support.path, sourceKey(sources)),
      );
      if (header == null) return EpgGuideSnapshot.empty;
      return EpgGuideSnapshot.fromHeader(header);
    } catch (_) {
      return EpgGuideSnapshot.empty;
    }
  }

  /// Downloads every source and merges them (first source wins per channel).
  /// Returns the merged guide; throws when no source could be read.
  Future<EpgGuideSnapshot> fetch(List<String> urls) async {
    final policy = PlaybackWorkPolicy.instance;
    final cacheDir = await _cacheDirectory(urls);
    final staged = '${cacheDir.path}.pending';
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
    var keep = false;
    try {
      if (policy.blocksGuide) throw EpgRefreshDeferred();
      final snapshot = await job.run();
      if (canceled || policy.blocksGuide) throw EpgRefreshDeferred();
      keep = true;
      return snapshot;
    } finally {
      if (identical(_activeJob, job)) _activeJob = null;
      policy.removeListener(cancelIfBlocked);
      if (!keep) await _deleteStaged(staged);
    }
  }

  /// Replaces the live guide after the previous channel file has been closed.
  Future<void> publish(EpgGuideSnapshot snapshot, List<String> urls) async {
    final staged = snapshot.archive?.directory;
    if (staged == null) return;
    final cacheDir = await _cacheDirectory(urls);
    if (staged == cacheDir.path) return;
    if (cacheDir.existsSync()) {
      final incoming = Directory('${cacheDir.path}.incoming');
      if (incoming.existsSync()) incoming.deleteSync(recursive: true);
      Directory(staged).renameSync(incoming.path);
      cacheDir.deleteSync(recursive: true);
      incoming.renameSync(cacheDir.path);
    } else {
      Directory(staged).renameSync(cacheDir.path);
    }
    snapshot.archive?.retarget(cacheDir.path);
    final legacy = File(
      '${cacheDir.parent.path}${Platform.pathSeparator}stellartv_epg_v2_${sourceKey(urls)}.json',
    );
    if (legacy.existsSync()) legacy.deleteSync();
  }

  Future<void> discard(EpgGuideSnapshot snapshot) async {
    final staged = snapshot.archive?.directory;
    snapshot.archive?.close();
    if (staged == null) return;
    await _deleteStaged(staged);
  }

  Future<void> _deleteStaged(String path) async {
    for (final candidate in [path, '$path.part']) {
      final directory = Directory(candidate);
      final file = File(candidate);
      try {
        if (await directory.exists()) await directory.delete(recursive: true);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
