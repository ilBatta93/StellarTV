import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/audio_effects.dart';

/// What the Android audio framework offers for the player's session.
class AudioEffectsSupport {
  /// DynamicsProcessing (Android 9+): multiband EQ, compressor, limiter.
  final bool dynamics;
  final bool equalizer;
  final bool loudness;

  const AudioEffectsSupport({
    this.dynamics = false,
    this.equalizer = false,
    this.loudness = false,
  });

  static const none = AudioEffectsSupport();

  /// Night mode compresses only with DynamicsProcessing; elsewhere it raises
  /// quiet passages with LoudnessEnhancer.
  bool get compresses => dynamics;
}

/// Equalizer, dialogue boost and night mode for the full-screen player.
///
/// Android: the native side owns one audio session; mpv and ExoPlayer play
/// on it and `android.media.audiofx` effects are attached to it. Elsewhere
/// mpv applies the equalizer itself (see MediaKitEngine). The preference is
/// local to the device: it depends on its speakers.
class AudioEffectsService extends ChangeNotifier {
  AudioEffectsService._();

  static final instance = AudioEffectsService._();

  static const _key = 'player_audio_effects_v1';
  static const _channel = MethodChannel('stellartv/audio');

  AudioEffectsSettings _settings = const AudioEffectsSettings();
  AudioEffectsSettings get settings => _settings;

  Future<void>? _loading;
  int? _sessionId;
  bool _sessionAsked = false;
  AudioEffectsSupport _support = AudioEffectsSupport.none;
  AudioEffectsSupport get support => _support;

  int _players = 0;
  AudioEffectsPlan? _sent;
  Timer? _clock;

  /// Overridable in tests.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  AudioEffectsPlan get plan => AudioEffectsPlan.from(_settings, now());

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Loads the preference and, on Android, the session id, so ExoPlayer
  /// (built synchronously) finds it ready.
  Future<void> prepare() => _loading ??= _prepare();

  Future<void> _prepare() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _settings = AudioEffectsSettings.fromJson(decoded);
        }
      }
    } on FormatException {
      // Corrupt payload: keep the defaults.
    }
    await _ensureSession();
  }

  Future<void> _ensureSession() async {
    if (!_android || _sessionAsked) return;
    _sessionAsked = true;
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>('prepare');
      final id = reply?['sessionId'];
      if (id is int && id > 0) _sessionId = id;
      _support = AudioEffectsSupport(
        dynamics: reply?['dynamics'] == true,
        equalizer: reply?['equalizer'] == true,
        loudness: reply?['loudness'] == true,
      );
    } on MissingPluginException {
      // Not registered (tests, other platforms).
    } on PlatformException catch (e) {
      debugPrint('Audio effects unavailable: ${e.code}');
    }
  }

  /// Android session the full-screen player must play on, or null when
  /// effects cannot attach (mpv then filters the sound itself).
  int? get sessionId => _sessionId;

  Future<int?> loadSessionId() async {
    await prepare();
    return _sessionId;
  }

  Future<void> update(AudioEffectsSettings next) async {
    await prepare();
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
    unawaited(_push());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(next.toJson()));
    } catch (e) {
      debugPrint('Audio effects not saved: $e');
    }
  }

  /// A full-screen player started on the session. Effects attach once its
  /// audio track exists, and night mode "auto" follows the clock.
  Future<void> playerStarted() async {
    _players++;
    await prepare();
    _clock ??= Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    await _push(force: true);
  }

  Future<void> playerStopped() async {
    if (_players == 0) return;
    _players--;
    if (_players > 0) return;
    _clock?.cancel();
    _clock = null;
    _sent = null;
    await _invoke('release');
  }

  void _tick() {
    if (_sent != null && plan != _sent) {
      // Night mode "auto" crossed 22:00 or 07:00.
      notifyListeners();
      unawaited(_push());
    }
  }

  Future<void> _push({bool force = false}) async {
    if (_players == 0 || _sessionId == null) return;
    final next = plan;
    if (!force && next == _sent) return;
    _sent = next;
    await _invoke('apply', next.toChannel());
  }

  Future<void> _invoke(String method, [Object? args]) async {
    if (_sessionId == null) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Not registered.
    } on PlatformException catch (e) {
      debugPrint('Audio effects $method failed: ${e.code}');
    }
  }
}
