import 'package:flutter/material.dart';

enum PlayerEngineType {
  exo(
    'ExoPlayer',
    'Nativo Android, leggero: usato per MultiView e anteprime. '
        'Tracce audio e qualità; niente pausa della diretta',
  ),
  mediakit(
    'mpv (media-kit)',
    'Consigliato per le dirette: sottotitoli, tracce audio e ritardi. '
        'Pausa e riavvolgimento solo se il buffer locale è reale',
  );

  final String label;
  final String description;
  const PlayerEngineType(this.label, this.description);

  /// Automatic fallback: ExoPlayer ⇄ mpv.
  PlayerEngineType get other => switch (this) {
    PlayerEngineType.mediakit => PlayerEngineType.exo,
    PlayerEngineType.exo => PlayerEngineType.mediakit,
  };

  bool get supportsSubtitles => this != PlayerEngineType.exo;
  bool get supportsDelays => this == PlayerEngineType.mediakit;
  bool get supportsTimeshift => this == PlayerEngineType.mediakit;
  bool get supportsQuality => this == PlayerEngineType.exo;

  /// Declared here so a new engine opts in once and the settings screen
  /// hides the control everywhere else.
  bool get supportsReconnect => this == PlayerEngineType.mediakit;
  bool get supportsSkipFrames => this == PlayerEngineType.mediakit;
  bool get supportsAudioPassthrough => this == PlayerEngineType.mediakit;
  bool get supportsAudioTimeStretch => this == PlayerEngineType.mediakit;
  bool get supportsDropLateFrames => this == PlayerEngineType.mediakit;
  bool get supportsCacheBuffer => this == PlayerEngineType.mediakit;
  bool get supportsBackBuffer => this == PlayerEngineType.exo;
}

enum LiveStreamFormat {
  auto(
    'Automatico',
    'Flusso diretto MPEG-TS, poi HLS solo se il canale non risponde',
  ),
  ts(
    'MPEG-TS (.ts)',
    'Flusso diretto: avvio più rapido, adatto alla maggior parte dei server Xtream',
  ),
  m3u8(
    'HLS (.m3u8)',
    'Flusso a segmenti: utile con connessioni instabili o server che lo ottimizzano',
  );

  final String label;
  final String description;
  const LiveStreamFormat(this.label, this.description);
}

enum VideoFitMode {
  fit('Adatta'),
  fill('Allunga'),
  zoom('Zoom / Ritaglia'),
  ratio16x9('16:9'),
  ratio4x3('4:3'),
  ratio21x9('21:9');

  final String label;
  const VideoFitMode(this.label);
}

enum HardwareDecoding {
  auto('Automatica'),
  full('Completa'),
  decoding('Solo decodifica'),
  disabled('Disattivata (software)');

  final String label;
  const HardwareDecoding(this.label);
}

enum SubtitleSize {
  small('Piccolo', 14),
  medium('Medio', 18),
  large('Grande', 22),
  extraLarge('Molto grande', 28);

  final String label;
  final double fontSize;
  const SubtitleSize(this.label, this.fontSize);
}

enum SubtitleColor {
  white('Bianco', Colors.white),
  yellow('Giallo', Color(0xFFFFE14D)),
  green('Verde', Color(0xFF6EE7A0)),
  cyan('Azzurro', Color(0xFF7DD3FC));

  final String label;
  final Color color;
  const SubtitleColor(this.label, this.color);

  int get rgb => color.toARGB32() & 0xFFFFFF;
}

enum PlayerOrientation {
  landscape('Sempre orizzontale'),
  auto('Automatico (sensore)'),
  followVideo('Segui il formato del video');

  final String label;
  const PlayerOrientation(this.label);
}

const kPlaybackSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0];

const kLanguageOptions = <String, String>{
  'it': 'Italiano',
  'en': 'Inglese',
  'es': 'Spagnolo',
  'fr': 'Francese',
  'de': 'Tedesco',
  'pt': 'Portoghese',
  'ja': 'Giapponese',
};

class PlayerSettings {
  PlayerEngineType primaryEngine;
  bool autoFallback;
  int startTimeoutSeconds;
  LiveStreamFormat liveStreamFormat;

  HardwareDecoding hardwareDecoding;

  /// Forward cache in bytes. A value below 16 MB is a legacy millisecond
  /// slider and is migrated before it reaches the engine.
  int networkCachingMs;
  int liveCachingMs;
  int backBufferSeconds;
  bool httpReconnect;
  bool dropLateFrames;
  bool skipFrames;
  bool audioPassthrough;
  bool audioTimeStretch;
  String userAgent;

  String preferredAudioLanguage;
  String preferredSubtitleLanguage;
  bool subtitlesEnabled;
  SubtitleSize subtitleSize;
  SubtitleColor subtitleColor;
  bool subtitleBackground;
  bool subtitleBold;
  int subtitleDelayMs;
  int audioDelayMs;

  double defaultSpeed;
  VideoFitMode fitMode;
  PlayerOrientation orientation;
  bool resumePlayback;
  bool autoNextEpisode;
  int seekStepSeconds;
  int controlsHideSeconds;
  bool gesturesEnabled;
  bool doubleTapSeek;
  bool autoPip;
  bool keepScreenOn;
  bool backgroundAudio;
  bool showStats;

  PlayerSettings({
    this.primaryEngine = PlayerEngineType.mediakit,
    this.autoFallback = true,
    this.startTimeoutSeconds = 12,
    this.liveStreamFormat = LiveStreamFormat.auto,
    this.hardwareDecoding = HardwareDecoding.auto,
    this.networkCachingMs = 8192,
    this.liveCachingMs = 3000,
    this.backBufferSeconds = 60,
    this.httpReconnect = true,
    this.dropLateFrames = true,
    this.skipFrames = false,
    this.audioPassthrough = false,
    this.audioTimeStretch = true,
    this.userAgent = '',
    this.preferredAudioLanguage = 'it',
    this.preferredSubtitleLanguage = 'it',
    this.subtitlesEnabled = false,
    this.subtitleSize = SubtitleSize.medium,
    this.subtitleColor = SubtitleColor.white,
    this.subtitleBackground = true,
    this.subtitleBold = true,
    this.subtitleDelayMs = 0,
    this.audioDelayMs = 0,
    this.defaultSpeed = 1.0,
    this.fitMode = VideoFitMode.fit,
    this.orientation = PlayerOrientation.landscape,
    this.resumePlayback = true,
    this.autoNextEpisode = true,
    this.seekStepSeconds = 10,
    this.controlsHideSeconds = 4,
    this.gesturesEnabled = true,
    this.doubleTapSeek = true,
    this.autoPip = false,
    this.keepScreenOn = true,
    this.backgroundAudio = false,
    this.showStats = false,
  });

  static const int cacheMib = 1024 * 1024;

  /// TV live floor. Every other scope floors at 32 MB.
  static const int cacheFloorLiveTvBytes = 16 * cacheMib;
  static const int cacheFloorBytes = 32 * cacheMib;
  static const int cacheStepBytes = 8 * cacheMib;

  static int cacheFloor({required bool live, required bool tv}) =>
      live && tv ? cacheFloorLiveTvBytes : cacheFloorBytes;

  static int cacheCap({required bool live, required bool tv}) {
    if (live) return (tv ? 64 : 96) * cacheMib;
    return (tv ? 96 : 128) * cacheMib;
  }

  /// Millisecond sliders topped out near 10 MB, under both floors.
  static bool isLegacyCacheValue(int value) => value < cacheFloorLiveTvBytes;

  /// Legacy values keep the buffer the engine already used. Anything at or
  /// above the floor is clamped and then used as the real byte count.
  static int migrateCacheBytes(
    int stored, {
    required bool live,
    required bool tv,
  }) {
    if (isLegacyCacheValue(stored)) {
      if (live && tv) return cacheFloorLiveTvBytes;
      if (live) return 64 * cacheMib;
      if (tv) return 48 * cacheMib;
      return cacheFloorBytes;
    }
    final floor = cacheFloor(live: live, tv: tv);
    final cap = cacheCap(live: live, tv: tv);
    if (stored < floor) return floor;
    if (stored > cap) return cap;
    return stored;
  }

  static int alignCacheBytes(
    int value, {
    required bool live,
    required bool tv,
  }) {
    final floor = cacheFloor(live: live, tv: tv);
    final cap = cacheCap(live: live, tv: tv);
    final clamped = value < floor ? floor : (value > cap ? cap : value);
    final steps = ((clamped - floor) / cacheStepBytes).round();
    final aligned = floor + steps * cacheStepBytes;
    if (aligned > cap) return cap;
    if (aligned < floor) return floor;
    return aligned;
  }

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);

  factory PlayerSettings.fromJson(Map<String, dynamic> j) {
    final d = PlayerSettings();
    int i(String k, int f) => (j[k] as num?)?.toInt() ?? f;
    bool b(String k, bool f) => j[k] is bool ? j[k] as bool : f;
    String s(String k, String f) => j[k] is String ? j[k] as String : f;
    return PlayerSettings(
      // Settings saved before mpv became the default are migrated once.
      primaryEngine: j['engineV'] == 2
          ? _enum(PlayerEngineType.values, j['primaryEngine'], d.primaryEngine)
          : PlayerEngineType.mediakit,
      autoFallback: b('autoFallback', d.autoFallback),
      startTimeoutSeconds: i('startTimeoutSeconds', d.startTimeoutSeconds),
      liveStreamFormat: _enum(
        LiveStreamFormat.values,
        j['liveStreamFormat'],
        d.liveStreamFormat,
      ),
      hardwareDecoding: _enum(
        HardwareDecoding.values,
        j['hardwareDecoding'],
        d.hardwareDecoding,
      ),
      networkCachingMs: i('networkCachingMs', d.networkCachingMs),
      liveCachingMs: i('liveCachingMs', d.liveCachingMs),
      backBufferSeconds: i('backBufferSeconds', d.backBufferSeconds),
      httpReconnect: b('httpReconnect', d.httpReconnect),
      dropLateFrames: b('dropLateFrames', d.dropLateFrames),
      // The old default was on, but the engine ignored it. Keep that
      // playback until the viewer turns the control on.
      skipFrames: j['tuningV'] == 1 ? b('skipFrames', d.skipFrames) : false,
      audioPassthrough: b('audioPassthrough', d.audioPassthrough),
      audioTimeStretch: b('audioTimeStretch', d.audioTimeStretch),
      userAgent: s('userAgent', d.userAgent),
      preferredAudioLanguage: s(
        'preferredAudioLanguage',
        d.preferredAudioLanguage,
      ),
      preferredSubtitleLanguage: s(
        'preferredSubtitleLanguage',
        d.preferredSubtitleLanguage,
      ),
      subtitlesEnabled: b('subtitlesEnabled', d.subtitlesEnabled),
      subtitleSize: _enum(
        SubtitleSize.values,
        j['subtitleSize'],
        d.subtitleSize,
      ),
      subtitleColor: _enum(
        SubtitleColor.values,
        j['subtitleColor'],
        d.subtitleColor,
      ),
      subtitleBackground: b('subtitleBackground', d.subtitleBackground),
      subtitleBold: b('subtitleBold', d.subtitleBold),
      subtitleDelayMs: i('subtitleDelayMs', d.subtitleDelayMs),
      audioDelayMs: i('audioDelayMs', d.audioDelayMs),
      defaultSpeed: (j['defaultSpeed'] as num?)?.toDouble() ?? d.defaultSpeed,
      fitMode: _enum(VideoFitMode.values, j['fitMode'], d.fitMode),
      orientation: _enum(
        PlayerOrientation.values,
        j['orientation'],
        d.orientation,
      ),
      resumePlayback: b('resumePlayback', d.resumePlayback),
      autoNextEpisode: b('autoNextEpisode', d.autoNextEpisode),
      seekStepSeconds: i('seekStepSeconds', d.seekStepSeconds),
      controlsHideSeconds: i('controlsHideSeconds', d.controlsHideSeconds),
      gesturesEnabled: b('gesturesEnabled', d.gesturesEnabled),
      doubleTapSeek: b('doubleTapSeek', d.doubleTapSeek),
      autoPip: b('autoPip', d.autoPip),
      keepScreenOn: b('keepScreenOn', d.keepScreenOn),
      backgroundAudio: b('backgroundAudio', d.backgroundAudio),
      showStats: b('showStats', d.showStats),
    );
  }

  Map<String, dynamic> toJson() => {
    'primaryEngine': primaryEngine.name,
    'engineV': 2,
    'liveEngineV': 6,
    'autoFallback': autoFallback,
    'startTimeoutSeconds': startTimeoutSeconds,
    'liveStreamFormat': liveStreamFormat.name,
    'hardwareDecoding': hardwareDecoding.name,
    'networkCachingMs': networkCachingMs,
    'liveCachingMs': liveCachingMs,
    'backBufferSeconds': backBufferSeconds,
    'httpReconnect': httpReconnect,
    'dropLateFrames': dropLateFrames,
    'skipFrames': skipFrames,
    'tuningV': 1,
    'audioPassthrough': audioPassthrough,
    'audioTimeStretch': audioTimeStretch,
    'userAgent': userAgent,
    'preferredAudioLanguage': preferredAudioLanguage,
    'preferredSubtitleLanguage': preferredSubtitleLanguage,
    'subtitlesEnabled': subtitlesEnabled,
    'subtitleSize': subtitleSize.name,
    'subtitleColor': subtitleColor.name,
    'subtitleBackground': subtitleBackground,
    'subtitleBold': subtitleBold,
    'subtitleDelayMs': subtitleDelayMs,
    'audioDelayMs': audioDelayMs,
    'defaultSpeed': defaultSpeed,
    'fitMode': fitMode.name,
    'orientation': orientation.name,
    'resumePlayback': resumePlayback,
    'autoNextEpisode': autoNextEpisode,
    'seekStepSeconds': seekStepSeconds,
    'controlsHideSeconds': controlsHideSeconds,
    'gesturesEnabled': gesturesEnabled,
    'doubleTapSeek': doubleTapSeek,
    'autoPip': autoPip,
    'keepScreenOn': keepScreenOn,
    'backgroundAudio': backgroundAudio,
    'showStats': showStats,
  };
}

/// Classic player identity: many IPTV panels throttle or reject unknown
/// clients on live channels, while VLC is accepted almost everywhere.
const String kDefaultStreamUserAgent = 'VLC/3.0.20 LibVLC/3.0.20';

/// Empty or the old built-in "StellarTV/1.0" means "use the default".
String effectiveStreamUserAgent(String configured) {
  final v = configured.trim();
  return v.isEmpty || v == 'StellarTV/1.0' ? kDefaultStreamUserAgent : v;
}
