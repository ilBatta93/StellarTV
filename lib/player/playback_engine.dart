import 'package:flutter/widgets.dart';

import '../models/player_settings.dart';

class MediaTrack {
  final String id;
  final String label;
  final String? language;
  final String? detail;
  final bool selected;

  const MediaTrack({
    required this.id,
    required this.label,
    this.language,
    this.detail,
    this.selected = false,
  });
}

class PlaybackSnapshot {
  final bool isReady;
  final bool isPlaying;
  final bool isBuffering;
  final bool isEnded;
  final Duration position;
  final Duration duration;
  final Duration bufferedUntil;
  final Size size;
  final double speed;
  final String? error;
  final String caption;
  final bool nativeLiveSeekable;
  final Duration? nativeLiveOffset;

  const PlaybackSnapshot({
    this.isReady = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isEnded = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedUntil = Duration.zero,
    this.size = Size.zero,
    this.speed = 1.0,
    this.error,
    this.caption = '',
    this.nativeLiveSeekable = false,
    this.nativeLiveOffset,
  });

  bool get hasError => error != null;
  bool get hasVideoSize => size.width > 0 && size.height > 0;
  double get aspectRatio => hasVideoSize ? size.width / size.height : 16 / 9;
}

class PlaybackException implements Exception {
  final String message;
  const PlaybackException(this.message);
  @override
  String toString() => message;
}

abstract class PlaybackEngine extends ChangeNotifier {
  /// Renderer confirmation, null when the platform does not expose it.
  bool? get videoFrameRendered => null;

  /// True only when the stream's tracks are known and none is video
  /// (radio channels): such streams never draw a picture by design.
  bool get audioOnly => false;

  /// Opt-in diagnostics: numeric engine metrics (dropped pictures, read-ahead,
  /// clock drift). No addresses, no titles, no player messages.
  Future<Map<String, Object?>> metrics() async => const {};

  /// Optional local container chapters; unsupported engines return empty.
  Future<List<Map<String, Object?>>> chapters() async => const [];

  PlayerEngineType get type;
  PlaybackSnapshot get value;

  bool get supportsAudioTracks;
  bool get supportsSubtitleTracks;
  bool get supportsQualitySelection;
  bool get supportsDelays;

  /// Live pause/rewind from a local buffer (false = plain live only).
  bool get supportsTimeshift => false;

  /// Completes once the stream is actually playing; throws when it can't.
  /// Engines backed by a platform view only progress while [buildView] is mounted.
  Future<void> open({double initialVolume = 1});

  /// Renders the video stretched to fill its parent, whose ratio is [boxRatio].
  Widget buildView(double boxRatio);

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> seekToLive() => seekTo(value.bufferedUntil);
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double volume);
  Future<void> applyFitMode(VideoFitMode mode, double boxRatio);

  Future<List<MediaTrack>> getAudioTracks();
  Future<void> selectAudioTrack(MediaTrack track);
  Future<List<MediaTrack>> getSubtitleTracks();
  Future<void> selectSubtitleTrack(MediaTrack? track);
  Future<List<MediaTrack>> getQualityTracks();
  Future<void> selectQualityTrack(MediaTrack? track);

  Future<void> setSubtitleDelay(Duration delay);
  Future<void> setAudioDelay(Duration delay);
}

const _languageAliases = <String, List<String>>{
  'it': ['it', 'ita', 'italian', 'italiano'],
  'en': ['en', 'eng', 'english', 'inglese'],
  'es': ['es', 'spa', 'spanish', 'español', 'spagnolo'],
  'fr': ['fr', 'fra', 'fre', 'french', 'français', 'francese'],
  'de': ['de', 'deu', 'ger', 'german', 'deutsch', 'tedesco'],
  'pt': ['pt', 'por', 'portuguese', 'português', 'portoghese'],
  'ja': ['ja', 'jpn', 'japanese', 'giapponese'],
};

bool trackMatchesLanguage(MediaTrack track, String code) {
  final aliases = _languageAliases[code] ?? [code];
  final lang = track.language?.toLowerCase();
  if (lang != null && aliases.any((a) => lang == a || lang.startsWith('$a-'))) {
    return true;
  }
  final words = track.label.toLowerCase().split(RegExp(r'[^a-zà-ÿ]+'));
  return words.any(aliases.contains);
}

String describeAudio({String? codec, int? channels, int? bitrate}) {
  final parts = <String>[];
  final c = codec?.toLowerCase() ?? '';
  if (c.contains('ec-3') || c.contains('eac3')) {
    parts.add(c.contains('joc') ? 'Dolby Atmos' : 'Dolby Digital Plus');
  } else if (c.contains('ac-3') || c.contains('ac3')) {
    parts.add('Dolby Digital');
  } else if (c.contains('ac-4') || c.contains('ac4')) {
    parts.add('Dolby AC-4');
  } else if (c.contains('dts')) {
    parts.add('DTS');
  } else if (c.contains('mp4a') || c.contains('aac')) {
    parts.add('AAC');
  } else if (c.contains('opus')) {
    parts.add('Opus');
  } else if (c.isNotEmpty) {
    parts.add(c.toUpperCase());
  }
  if (channels != null) {
    parts.add(switch (channels) {
      1 => 'Mono',
      2 => 'Stereo',
      6 => '5.1',
      8 => '7.1',
      _ => '$channels canali',
    });
  }
  if (bitrate != null && bitrate > 0) parts.add('${bitrate ~/ 1000} kbps');
  return parts.join(' · ');
}

String describeVideo({String? codec, int? bitrate, double? frameRate}) {
  final parts = <String>[];
  final c = codec?.toLowerCase() ?? '';
  if (c.startsWith('dvh') || c.startsWith('dva')) {
    parts.add('Dolby Vision');
  } else if (c.startsWith('hvc') || c.startsWith('hev') || c.contains('hevc')) {
    parts.add('HEVC');
  } else if (c.startsWith('av01')) {
    parts.add('AV1');
  } else if (c.startsWith('vp09') || c.contains('vp9')) {
    parts.add('VP9');
  } else if (c.startsWith('avc')) {
    parts.add('H.264');
  }
  if (frameRate != null && frameRate > 0) parts.add('${frameRate.round()} fps');
  if (bitrate != null && bitrate > 0) {
    parts.add('${(bitrate / 1000000).toStringAsFixed(1)} Mbps');
  }
  return parts.join(' · ');
}

String languageName(String? code) {
  if (code == null || code.isEmpty || code == 'und') return 'Sconosciuta';
  final lower = code.toLowerCase().split('-').first;
  final key =
      _languageAliases.entries
          .where((e) => e.value.contains(lower))
          .firstOrNull
          ?.key ??
      lower;
  return kLanguageOptions[key] ?? code.toUpperCase();
}
