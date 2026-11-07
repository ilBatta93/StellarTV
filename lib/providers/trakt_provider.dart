import 'dart:async';
import 'dart:isolate';

import 'package:flutter/widgets.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/series_details.dart';
import '../models/tmdb_item.dart';
import '../models/trakt_policy.dart';
import '../services/catalog_rating_service.dart';
import '../services/history_signals.dart';
import '../services/playback_work_policy.dart';
import '../services/service_keys.dart';
import '../services/title_facet_index.dart';
import '../services/title_matching.dart';
import '../services/tmdb_service.dart';
import '../services/trakt_client.dart';
import '../services/trakt_store.dart';
import 'app_provider.dart';
import 'history_provider.dart';

/// Two-way link between the watch history of the selected profile and its
/// Trakt account.
///
/// - Here -> Trakt: views marked by hand, finished views, pause points and
///   "now watching" (scrobble). Changes wait on the device while offline.
/// - Trakt -> here: views and pause points of titles found in the catalog.
///   Movies are applied at every sync; episodes when their series page is
///   loaded (the source lists episodes only then), and right away for the
///   most recent paused episodes.
/// - Live channels, kids profiles and removals from "Continua a guardare"
///   never reach Trakt.
class TraktProvider extends ChangeNotifier with WidgetsBindingObserver {
  TraktProvider(this._app, this._history, {TraktClient? client})
    : _client = client ?? TraktClient();

  final AppProvider _app;
  final HistoryProvider _history;
  final TraktClient _client;
  final TraktStore _store = const TraktStore();
  final _tmdb = TmdbService();

  String? _profileId;
  int _epoch = 0;
  TraktSession? _session;
  TraktRemoteState _remote = TraktRemoteState();
  bool _syncing = false;
  bool _scrobble = true;
  String? _error;
  DateTime? _lastSync;
  StreamSubscription<HistorySignal>? _signals;
  Timer? _flushTimer;
  bool _disposed = false;

  /// Catalog matches of Trakt titles in this session (`movie:<id>` and
  /// `tv:<id>` -> catalog channels; empty when none).
  final Map<String, List<Channel>> _matches = {};

  /// Trakt identity of each catalog id met in this session.
  final Map<String, TraktTarget?> _targets = {};
  final Map<String, DateTime> _lastPause = {};
  final Map<String, DateTime> _lastFinished = {};
  final Set<String> _seriesOpened = {};

  bool get connected => _session != null;
  String get user => _session?.user ?? '';
  bool get ownKeys => _session?.own ?? false;
  bool get syncing => _syncing;
  bool get scrobble => _scrobble;
  String? get error => _error;
  DateTime? get lastSync => _lastSync;

  /// Kids profiles stay out of Trakt.
  bool get allowed => !_app.kidsMode;

  Future<void> init() async {
    await ServiceKeys.instance.load();
    _scrobble = await _store.scrobbleEnabled();
    _signals = HistorySignals.stream.listen(_onSignal);
    _app.onSeriesDetails = _onSeriesDetails;
    WidgetsBinding.instance.addObserver(this);
    await switchProfile(_history.profileId);
  }

  /// Loads the Trakt link of [profileId] (each profile links its own).
  Future<void> switchProfile(String? profileId) async {
    _epoch++;
    final epoch = _epoch;
    _profileId = profileId;
    _session = null;
    _remote = TraktRemoteState();
    _targets.clear();
    _seriesOpened.clear();
    _error = null;
    final session = await _store.session(profileId);
    final remote = session == null
        ? TraktRemoteState()
        : await _store.remote(profileId);
    final last = await _store.lastSync(profileId);
    if (epoch != _epoch) return;
    _session = session;
    _remote = remote;
    _lastSync = last;
    _notify();
    if (session != null && allowed) {
      // Startup stays smooth: the first sync waits a little.
      Future.delayed(const Duration(seconds: 8), () {
        if (epoch == _epoch) unawaited(sync());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !connected) return;
    final last = _lastSync;
    if (last == null ||
        DateTime.now().difference(last) > const Duration(minutes: 15)) {
      unawaited(sync());
    }
  }

  Future<void> setScrobble(bool value) async {
    _scrobble = value;
    await _store.setScrobbleEnabled(value);
    _notify();
  }

  // ---------------------------------------------------------------- sign-in

  Future<TraktDeviceCode> startConnect() => _client.startDevice();

  /// One poll of the sign-in shown on screen. On approval the profile is
  /// linked and a full sync starts.
  Future<TraktPollState> pollConnect(TraktDeviceCode code) async {
    final profile = _profileId, epoch = _epoch;
    final (state, session) = await _client.pollDevice(code);
    if (state != TraktPollState.ok || session == null) return state;
    var linked = session;
    try {
      final settings = await _client.call(session, 'GET', '/users/settings');
      final u = settings is Map ? settings['user'] : null;
      final name = u is Map ? u['username'] : null;
      if (name is String) linked = session.copyWith(user: name);
    } catch (_) {}
    if (epoch != _epoch) return TraktPollState.error;
    await _store.clear(profile);
    await _store.saveSession(profile, linked);
    _session = linked;
    _remote = TraktRemoteState();
    _error = null;
    _notify();
    unawaited(sync(force: true));
    return TraktPollState.ok;
  }

  /// Unlinks this profile: the sign-in is revoked and every Trakt record on
  /// the device is forgotten. The history here stays as it is.
  Future<void> disconnect() async {
    final session = _session;
    _epoch++;
    _session = null;
    _remote = TraktRemoteState();
    _lastSync = null;
    _error = null;
    _notify();
    if (session != null) await _client.revoke(session);
    await _store.clear(_profileId);
  }

  Future<void> _signedOut() async {
    _session = null;
    _error = 'Accesso a Trakt scaduto: collegalo di nuovo';
    await _store.saveSession(_profileId, null);
    _notify();
  }

  Future<TraktSession?> _ready() async {
    var session = _session;
    if (session == null) return null;
    if (session.needsRefresh(DateTime.now())) {
      final profile = _profileId;
      session = await _client.refresh(session);
      if (profile != _profileId) return null;
      await _store.saveSession(profile, session);
      _session = session;
    }
    return session;
  }

  Future<Object?> _call(
    String method,
    String path, {
    Object? body,
    bool raw = false,
  }) async {
    var session = await _ready();
    if (session == null) throw const TraktException('Trakt non collegato');
    try {
      return await _client.call(session, method, path, body: body, raw: raw);
    } on TraktException catch (e) {
      if (!e.signedOut) rethrow;
      // An early expiry: one renewal, then the call again.
      try {
        session = await _client.refresh(session);
        await _store.saveSession(_profileId, session);
        _session = session;
      } on TraktException catch (r) {
        if (r.signedOut) await _signedOut();
        rethrow;
      }
      return _client.call(session, method, path, body: body, raw: raw);
    }
  }

  // ------------------------------------------------------------ here -> Trakt

  void _onSignal(HistorySignal signal) {
    if (!connected || !allowed || signal.profileId != _profileId) return;
    unawaited(_handleSignal(signal));
  }

  Future<void> _handleSignal(HistorySignal signal) async {
    final channel = signal.channel ?? _app.channelById(signal.contentId);
    if (channel == null || channel.type == ContentType.live) return;
    final target = await _targetOf(channel);
    if (target == null || !connected) return;
    final percent = TraktPolicy.percent(signal.position, signal.duration);
    switch (signal.kind) {
      case HistorySignalKind.started:
        if (_scrobble) await _scrobbleCall('start', target, percent);
      case HistorySignalKind.paused:
        if (!_scrobble || percent < 1) return;
        final last = _lastPause[target.key];
        if (last != null &&
            signal.at.difference(last) < const Duration(seconds: 30)) {
          return;
        }
        _lastPause[target.key] = signal.at;
        await _scrobbleCall('pause', target, percent);
      case HistorySignalKind.completed:
        final last = _lastFinished[target.key];
        if (last != null &&
            signal.at.difference(last) < const Duration(minutes: 30)) {
          return;
        }
        _lastFinished[target.key] = signal.at;
        // Stop from 80% counts the view on Trakt and clears its pause
        // point; when it cannot be sent, the view waits in the queue.
        final sent =
            _scrobble &&
            await _scrobbleCall(
              'stop',
              target,
              percent < TraktPolicy.finishedPercent
                  ? TraktPolicy.finishedPercent
                  : percent,
            );
        if (!sent) await _enqueue(TraktPending(target, true, signal.at));
        _remote.watched[target.key] = signal.at;
        _remote.playback.remove(target.key);
      case HistorySignalKind.markedWatched:
        if (!TraktPolicy.pushWatched(target, _remote)) return;
        _remote.watched[target.key] = signal.at;
        await _enqueue(TraktPending(target, true, signal.at));
      case HistorySignalKind.markedUnwatched:
        _remote.watched.remove(target.key);
        _remote.playback.remove(target.key);
        await _enqueue(TraktPending(target, false, signal.at));
    }
  }

  Future<bool> _scrobbleCall(
    String action,
    TraktTarget target,
    double percent,
  ) async {
    try {
      await _call(
        'POST',
        '/scrobble/$action',
        body: TraktPolicy.scrobbleBody(target, percent),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _enqueue(TraktPending item) async {
    final profile = _profileId;
    final pending = await _store.pending(profile)
      ..add(item);
    await _store.savePending(profile, TraktPolicy.compact(pending));
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 3), () => unawaited(_flush()));
  }

  bool _flushing = false;
  Future<void> _flush() async {
    if (_flushing || !connected) return;
    _flushing = true;
    final profile = _profileId;
    try {
      final pending = TraktPolicy.compact(await _store.pending(profile));
      if (pending.isEmpty) return;
      final adds = pending.where((p) => p.watched).toList();
      final removes = pending.where((p) => !p.watched).toList();
      if (adds.isNotEmpty) {
        await _call(
          'POST',
          '/sync/history',
          body: TraktPolicy.historyBody([
            for (final p in adds) (target: p.target, at: p.at),
          ]),
        );
      }
      if (removes.isNotEmpty) {
        await _call(
          'POST',
          '/sync/history/remove',
          body: TraktPolicy.historyBody([
            for (final p in removes) (target: p.target, at: null),
          ]),
        );
      }
      if (profile != _profileId) return;
      // Choices queued while sending stay for the next round.
      final sent = {for (final p in pending) p.toJson().toString()};
      final left = (await _store.pending(profile))
          .where((p) => !sent.contains(p.toJson().toString()))
          .toList();
      await _store.savePending(profile, left);
    } catch (_) {
      // Kept in the queue: sent at the next sync.
    } finally {
      _flushing = false;
    }
  }

  /// Trakt identity of a catalog title: TMDB id joined by the catalog,
  /// then the IMDb id, then a TMDB search by name.
  Future<TraktTarget?> _targetOf(Channel c) async {
    if (_targets.containsKey(c.id)) return _targets[c.id];
    TraktTarget? target;
    final ratings = CatalogRatingService.instance;
    if (c.type == ContentType.movie) {
      final link = ratings.linkedIdentity(c);
      if (link != null && link.movie) {
        target = TraktTarget.movie(tmdbId: link.id);
      } else {
        final imdb = ratings.imdbIdOf(c);
        if (imdb != null) {
          target = TraktTarget.movie(imdbId: imdb);
        } else {
          final item = await _tmdb.findByTitle(c.name, isMovie: true);
          if (item != null) target = TraktTarget.movie(tmdbId: item.id);
        }
      }
    } else {
      final numbers = TraktPolicy.episodeNumbers(c.season, c.episode, c.name);
      if (numbers != null) {
        int? show;
        final own = ratings.linkedIdentity(c);
        if (own != null && !own.movie) show = own.id;
        final folderKey = c.seriesKey ?? '';
        final folder = folderKey.isEmpty
            ? null
            : _app.seriesFolderFor(folderKey, wait: false);
        if (show == null && folder != null) {
          final link = ratings.linkedIdentity(folder);
          if (link != null && !link.movie) show = link.id;
        }
        if (show == null) {
          final item = await _tmdb.findByTitle(
            c.displaySeriesName,
            isMovie: false,
          );
          show = item?.id;
        }
        if (show != null) {
          target = TraktTarget.episode(
            tmdbId: show,
            season: numbers.season,
            episode: numbers.episode,
          );
        }
      }
    }
    _targets[c.id] = target;
    return target;
  }

  // ------------------------------------------------------------ Trakt -> here

  /// Sends queued changes, downloads what changed on Trakt and applies it.
  Future<void> sync({bool force = false}) async {
    if (_syncing || !connected || !allowed) return;
    if (PlaybackWorkPolicy.instance.blocksGuide) return;
    final profile = _profileId, epoch = _epoch;
    _syncing = true;
    _notify();
    try {
      await _flush();
      final activity = TraktActivity.parse(
        await _call('GET', '/sync/last_activities'),
      );
      final stored = await _store.activity(profile);
      var fresh = false;
      if (force || !activity.sameAs(stored) || _remote.isEmpty) {
        final movies = await _call('GET', '/sync/watched/movies', raw: true);
        final shows = await _call('GET', '/sync/watched/shows', raw: true);
        final playback = await _call(
          'GET',
          '/sync/playback?extended=full',
          raw: true,
        );
        if (epoch != _epoch) return;
        // Decoded and parsed off the UI isolate: the TV stays smooth.
        final remote = await Isolate.run(
          () => TraktPolicy.parseRemoteText(
            movies as String?,
            shows as String?,
            playback as String?,
          ),
        );
        if (epoch != _epoch) return;
        _remote = remote;
        await _store.saveRemote(profile, _remote);
        await _store.saveActivity(profile, activity);
        fresh = true;
      }
      if (epoch != _epoch) return;
      await _applyMovies(epoch);
      if (fresh || _seriesOpened.isEmpty) await _openPausedSeries(epoch);
      _lastSync = DateTime.now();
      await _store.saveLastSync(profile, _lastSync);
      _error = null;
    } on TraktException catch (e) {
      if (epoch == _epoch && connected) _error = e.message;
    } catch (_) {
      if (epoch == _epoch && connected) {
        _error = 'Sincronizzazione non riuscita';
      }
    } finally {
      if (epoch == _epoch) {
        _syncing = false;
        _notify();
      }
    }
  }

  Future<void> _applyMovies(int epoch) async {
    final views = <String, DateTime>{};
    var lookups = 0;
    for (final e in _remote.watched.entries.toList()) {
      if (!e.key.startsWith('movie:')) continue;
      final id = int.tryParse(e.key.substring(6));
      if (id == null) continue;
      // Network lookups (TMDB title in Italian) are capped per sync.
      final known = _matches.containsKey('movie:$id');
      final channels = await _catalogFor(
        id,
        movie: true,
        network: lookups < 80,
      );
      if (!known) lookups++;
      if (epoch != _epoch) return;
      for (final c in channels) {
        if (TraktPolicy.applyRemoteWatched(
          remoteAt: e.value,
          locallyWatched: _history.isWatched(c.id),
          localChoiceAt: _history.manualChoiceAt(c.id),
        )) {
          views[c.id] = e.value;
        }
      }
    }
    await _history.applyRemoteWatched(views);
    for (final p in _remote.playback.values.toList()) {
      if (!p.key.startsWith('movie:')) continue;
      final id = int.tryParse(p.key.substring(6));
      if (id == null) continue;
      final channels = await _catalogFor(id, movie: true, network: true);
      if (epoch != _epoch || channels.isEmpty) continue;
      await _applyProgress(channels.first, p, null);
    }
  }

  Future<void> _applyProgress(
    Channel c,
    TraktPlayback p,
    Duration? known,
  ) async {
    final entry = _history.entryFor(c.id);
    if (!TraktPolicy.applyRemoteProgress(
      remote: p,
      locallyWatched: _history.isWatched(c.id),
      completionPercent: _history.watchedPercent,
      localAt: entry?.lastWatchedAt,
      removedAt: _history.removedAt(c.id),
    )) {
      return;
    }
    final duration = (entry != null && entry.duration > Duration.zero)
        ? entry.duration
        : known ?? p.runtime;
    if (duration == null || duration <= Duration.zero) return;
    await _history.applyRemoteProgress(
      c,
      Duration(milliseconds: (duration.inMilliseconds * p.progress).round()),
      duration,
      p.pausedAt,
    );
  }

  /// Loads the pages of the series with the most recent paused episodes,
  /// so they show up in "Continua a guardare" without opening them.
  Future<void> _openPausedSeries(int epoch) async {
    final paused =
        _remote.playback.values.where((p) => p.key.startsWith('tv:')).toList()
          ..sort((a, b) => b.pausedAt.compareTo(a.pausedAt));
    final shows = <int>{};
    for (final p in paused) {
      final id = int.tryParse(p.key.split(':')[1]);
      if (id != null) shows.add(id);
      if (shows.length >= 8) break;
    }
    for (final id in shows) {
      final series = await _catalogFor(id, movie: false, network: true);
      if (epoch != _epoch) return;
      if (series.isEmpty || _seriesOpened.contains(series.first.id)) continue;
      try {
        // The page load calls _onSeriesDetails, which applies the views.
        await _app.loadSeriesDetails(series.first);
      } catch (_) {}
    }
  }

  void _onSeriesDetails(SeriesDetails details) {
    if (!connected || !allowed || _remote.isEmpty) return;
    unawaited(_applySeries(details));
  }

  Future<void> _applySeries(SeriesDetails details) async {
    final series = details.series;
    _seriesOpened.add(series.id);
    final show = await _showIdOf(series);
    if (show == null) return;
    final views = <String, DateTime>{};
    for (final ep in details.allEpisodes) {
      final key = 'tv:$show:${ep.season}:${ep.number}';
      final at = _remote.watched[key];
      final id = ep.channel.id;
      if (at != null &&
          TraktPolicy.applyRemoteWatched(
            remoteAt: at,
            locallyWatched: _history.isWatched(id),
            localChoiceAt: _history.manualChoiceAt(id),
          )) {
        views[id] = at;
      }
    }
    await _history.applyRemoteWatched(
      views,
      seriesId: series.seriesKey ?? series.id,
    );
    for (final ep in details.allEpisodes) {
      final p = _remote.playback['tv:$show:${ep.season}:${ep.number}'];
      if (p != null) await _applyProgress(ep.channel, p, ep.duration);
    }
  }

  /// TMDB id of a catalog series: the catalog's own link, else a show
  /// watched on Trakt with the same name and year.
  Future<int?> _showIdOf(Channel series) async {
    final link = CatalogRatingService.instance.linkedIdentity(series);
    if (link != null && !link.movie) return link.id;
    final mine = parseTitle(series.displaySeriesName);
    final name = normalizeTitle(mine.title);
    if (name.isEmpty) return null;
    for (final e in _remote.showTitles.entries) {
      final theirs = parseTitle(e.value);
      if (normalizeTitle(theirs.title) != name) continue;
      if (mine.year != null &&
          theirs.year != null &&
          mine.year != theirs.year) {
        continue;
      }
      return int.tryParse(e.key.substring(3));
    }
    return null;
  }

  /// Catalog titles for a TMDB id: titles the catalog already joined to it,
  /// then the Italian TMDB title, then the name Trakt uses. Movies include
  /// every quality copy.
  Future<List<Channel>> _catalogFor(
    int id, {
    required bool movie,
    required bool network,
  }) async {
    final mediaKey = movie ? 'movie:$id' : 'tv:$id';
    final cached = _matches[mediaKey];
    if (cached != null) return cached;
    final type = movie ? 'movie' : 'tv';
    TmdbItem item(String title, String year) => TmdbItem(
      id: id,
      mediaType: type,
      title: title,
      overview: '',
      posterPath: null,
      backdropPath: null,
      voteAverage: 0,
      popularity: 0,
      releaseDate: year,
    );
    Channel? found;
    for (final key in TitleFacetIndex.instance.titleKeysForMedia(mediaKey)) {
      final parts = key.split(':');
      if (parts.length < 3) continue;
      found = _app.findChannelFor(
        item(parts[1], parts[2] == 'unknown' ? '' : parts[2]),
      );
      if (found != null) break;
    }
    if (found == null && network) {
      try {
        final italian = await _tmdb.itemById(id, movie: movie);
        if (italian != null) found = _app.findChannelFor(italian);
      } catch (_) {}
    }
    if (found == null) {
      final name = movie
          ? _remote.movieTitles[mediaKey]
          : _remote.showTitles[mediaKey];
      if (name != null) {
        final parsed = parseTitle(name);
        found = _app.findChannelFor(item(parsed.title, parsed.year ?? ''));
      }
    }
    if (found == null && !network) return const [];
    final out = found == null
        ? const <Channel>[]
        : movie
        ? _app.movieVersions(found)
        : [found];
    return _matches[mediaKey] = out;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _signals?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_app.onSeriesDetails == _onSeriesDetails) _app.onSeriesDetails = null;
    super.dispose();
  }
}
