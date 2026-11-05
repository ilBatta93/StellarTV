import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/content_type.dart';
import 'stream_address.dart';

/// A video player app installed on the device (VLC, MX Player, ...).
class ExternalPlayer {
  final String package;
  final String label;
  const ExternalPlayer({required this.package, required this.label});
}

/// What the external player reported when it closed. Players that return
/// nothing (or the activity lost while away) give null fields.
class ExternalPlaybackResult {
  final Duration? position;
  final Duration? duration;
  final bool completed;
  const ExternalPlaybackResult({
    this.position,
    this.duration,
    this.completed = false,
  });
}

/// Hands films and episodes to a player app chosen by the user (Android
/// only). The choice stays on this device: it names an installed package.
class ExternalPlayerService extends ChangeNotifier {
  ExternalPlayerService._();
  static final instance = ExternalPlayerService._();

  static const _channel = MethodChannel('stellartv/player');
  static const _enabledKey = 'external_player_enabled';
  static const _packageKey = 'external_player_package';
  static const _labelKey = 'external_player_label';

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _enabled = false;
  ExternalPlayer? _player;
  Future<void>? _loading;

  /// Every film and episode goes to [player] instead of the built-in one.
  bool get enabled => supported && _enabled && _player != null;
  ExternalPlayer? get player => _player;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    final package = prefs.getString(_packageKey);
    if (package != null && package.isNotEmpty) {
      _player = ExternalPlayer(
        package: package,
        label: prefs.getString(_labelKey) ?? package,
      );
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  Future<void> setPlayer(ExternalPlayer player) async {
    _player = player;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_packageKey, player.package);
    await prefs.setString(_labelKey, player.label);
  }

  /// Live channels keep the built-in player (instant zapping, EPG, no
  /// history); offline copies are files only this app can read.
  static bool canPlay(Channel channel) =>
      channel.type != ContentType.live &&
      !channel.isSeriesFolder &&
      (channel.url.startsWith('http://') ||
          channel.url.startsWith('https://') ||
          StreamAddress.needsResolve(channel.url));

  Future<List<ExternalPlayer>> installed() async {
    if (!supported) return const [];
    try {
      final raw = await _channel.invokeListMethod<Map>('externalPlayers');
      return [
        for (final m in raw ?? const <Map>[])
          if (m['package'] is String)
            ExternalPlayer(
              package: m['package'] as String,
              label: (m['label'] as String?) ?? m['package'] as String,
            ),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Opens [channel] in the chosen player and waits until it closes.
  /// Throws [PlatformException] when the player cannot be started.
  Future<ExternalPlaybackResult> play(
    Channel channel, {
    required String userAgent,
    Duration? startAt,
  }) async {
    final player = _player;
    if (player == null) {
      throw PlatformException(code: 'no_player');
    }
    final url = await StreamAddress.resolve(channel.url);
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'openExternal',
      {
        'url': url,
        'package': player.package,
        'title': channel.name,
        'positionMs': startAt?.inMilliseconds ?? 0,
        'userAgent': userAgent,
      },
    );
    Duration? ms(Object? v) =>
        v is num && v > 0 ? Duration(milliseconds: v.toInt()) : null;
    return ExternalPlaybackResult(
      position: ms(raw?['position']),
      duration: ms(raw?['duration']),
      completed: raw?['completed'] == true,
    );
  }
}
