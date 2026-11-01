import 'dart:math' as math;

/// Centre frequencies (Hz) of the five bands the viewer adjusts. They match
/// the classic Android Equalizer, the fallback on devices without
/// DynamicsProcessing.
const kEqBandCenters = <double>[60, 230, 910, 3600, 14000];

const kEqBandLabels = <String>[
  '60 Hz',
  '230 Hz',
  '910 Hz',
  '3,6 kHz',
  '14 kHz',
];

const kEqMinDb = -12;
const kEqMaxDb = 12;

enum EqPreset {
  flat('Neutro', [0, 0, 0, 0, 0]),
  cinema('Cinema', [4, 1, 0, 2, 3]),
  music('Musica', [3, 1, -1, 1, 3]),
  bass('Bassi potenti', [7, 4, 0, 0, 0]),
  treble('Alti brillanti', [0, 0, 0, 3, 6]),
  custom('Personalizzato', [0, 0, 0, 0, 0]);

  final String label;
  final List<int> gains;
  const EqPreset(this.label, this.gains);
}

enum DialogBoost {
  off('Spento', 'Audio originale'),
  light('Lieve', 'Voci più presenti, bassi appena ridotti'),
  strong('Forte', 'Voci in primo piano, per stanze rumorose o TV piccole');

  final String label;
  final String description;
  const DialogBoost(this.label, this.description);
}

enum NightMode {
  off('Spenta', 'Dinamica originale'),
  on('Sempre attiva', 'Esplosioni e musica più basse, voci più alte'),
  auto('Automatica di notte', 'Si attiva da sola dalle 22 alle 7');

  final String label;
  final String description;
  const NightMode(this.label, this.description);
}

class AudioEffectsSettings {
  final EqPreset preset;

  /// Gains in dB for [kEqBandCenters], used by [EqPreset.custom].
  final List<int> customGains;
  final DialogBoost dialog;
  final NightMode night;

  const AudioEffectsSettings({
    this.preset = EqPreset.flat,
    this.customGains = const [0, 0, 0, 0, 0],
    this.dialog = DialogBoost.off,
    this.night = NightMode.off,
  });

  static const nightStartHour = 22;
  static const nightEndHour = 7;

  List<int> get eqGains =>
      preset == EqPreset.custom ? customGains : preset.gains;

  bool nightActiveAt(DateTime now) => switch (night) {
    NightMode.off => false,
    NightMode.on => true,
    NightMode.auto => now.hour >= nightStartHour || now.hour < nightEndHour,
  };

  /// True when any setting changes the sound at some time of day.
  bool get anyEnabled =>
      night != NightMode.off ||
      dialog != DialogBoost.off ||
      eqGains.any((g) => g != 0);

  AudioEffectsSettings copyWith({
    EqPreset? preset,
    List<int>? customGains,
    DialogBoost? dialog,
    NightMode? night,
  }) => AudioEffectsSettings(
    preset: preset ?? this.preset,
    customGains: customGains ?? this.customGains,
    dialog: dialog ?? this.dialog,
    night: night ?? this.night,
  );

  /// Custom curve with one band moved; picking a band starts from the
  /// curve currently heard, so a preset can be fine-tuned.
  AudioEffectsSettings withBand(int index, int gain) {
    final gains = List<int>.of(eqGains);
    gains[index] = gain.clamp(kEqMinDb, kEqMaxDb);
    return copyWith(preset: EqPreset.custom, customGains: gains);
  }

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);

  factory AudioEffectsSettings.fromJson(Map<String, dynamic> j) {
    const d = AudioEffectsSettings();
    final raw = j['customGains'];
    final gains = raw is List && raw.length == kEqBandCenters.length
        ? [
            for (final g in raw)
              (g is num ? g.round() : 0).clamp(kEqMinDb, kEqMaxDb),
          ]
        : d.customGains;
    return AudioEffectsSettings(
      preset: _enum(EqPreset.values, j['preset'], d.preset),
      customGains: gains,
      dialog: _enum(DialogBoost.values, j['dialog'], d.dialog),
      night: _enum(NightMode.values, j['night'], d.night),
    );
  }

  Map<String, dynamic> toJson() => {
    'preset': preset.name,
    'customGains': customGains,
    'dialog': dialog.name,
    'night': night.name,
  };

  @override
  bool operator ==(Object other) =>
      other is AudioEffectsSettings &&
      other.preset == preset &&
      other.dialog == dialog &&
      other.night == night &&
      _sameList(other.customGains, customGains);

  @override
  int get hashCode =>
      Object.hash(preset, dialog, night, Object.hashAll(customGains));
}

bool _sameList(List<num> a, List<num> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What the native effects and mpv receive, computed from the settings at a
/// given time. Pure, so the sound curves are testable without a device.
class AudioEffectsPlan {
  /// Upper edge (Hz) of each DynamicsProcessing pre-EQ band. Finer than the
  /// five viewer bands, so the speech range (1–4 kHz) is shaped on its own.
  static const preEqCutoffs = <double>[
    90,
    180,
    355,
    710,
    1400,
    2800,
    5600,
    20000,
  ];

  static const _maxGainDb = 15.0;

  // Speech sits in 1–4 kHz; rumble and effects below ~150 Hz mask it.
  static const _dialogPreEq = {
    DialogBoost.light: [-3.0, -2, -1, 0, 1, 3, 2, 0],
    DialogBoost.strong: [-6.0, -4, -2, 0, 2, 5, 4, 1],
  };
  static const _dialogEq5 = {
    DialogBoost.light: [-3.0, -1, 1, 3, 0],
    DialogBoost.strong: [-6.0, -2, 2, 5, 1],
  };

  /// Gains (dB) at [kEqBandCenters].
  final List<double> eqGains;

  /// Gains (dB) for [preEqCutoffs].
  final List<double> preEqGains;

  /// Night mode: multiband compression and make-up gain.
  final bool compress;

  /// Effective dialog boost (night mode implies at least [DialogBoost.light]).
  final DialogBoost dialog;

  const AudioEffectsPlan({
    required this.eqGains,
    required this.preEqGains,
    required this.compress,
    required this.dialog,
  });

  static const off = AudioEffectsPlan(
    eqGains: [0, 0, 0, 0, 0],
    preEqGains: [0, 0, 0, 0, 0, 0, 0, 0],
    compress: false,
    dialog: DialogBoost.off,
  );

  factory AudioEffectsPlan.from(AudioEffectsSettings s, DateTime now) {
    final night = s.nightActiveAt(now);
    final dialog = night && s.dialog == DialogBoost.off
        ? DialogBoost.light
        : s.dialog;
    final user = [for (final g in s.eqGains) g.toDouble()];
    final eq5 = [
      for (var i = 0; i < user.length; i++)
        _clamp(user[i] + (_dialogEq5[dialog]?[i] ?? 0)),
    ];
    final preEq = <double>[];
    var lower = 20.0;
    for (var i = 0; i < preEqCutoffs.length; i++) {
      final upper = preEqCutoffs[i];
      final centre = math.sqrt(lower * upper);
      preEq.add(
        _clamp(userGainAt(user, centre) + (_dialogPreEq[dialog]?[i] ?? 0)),
      );
      lower = upper;
    }
    return AudioEffectsPlan(
      eqGains: eq5,
      preEqGains: preEq,
      compress: night,
      dialog: dialog,
    );
  }

  static double _clamp(double v) => v.clamp(-_maxGainDb, _maxGainDb);

  /// Viewer curve at [hz], interpolated on a log-frequency scale between the
  /// five band centres and flat beyond the outer ones.
  static double userGainAt(List<double> gains, double hz) {
    if (hz <= kEqBandCenters.first) return gains.first;
    if (hz >= kEqBandCenters.last) return gains.last;
    for (var i = 0; i < kEqBandCenters.length - 1; i++) {
      final lo = kEqBandCenters[i], hi = kEqBandCenters[i + 1];
      if (hz <= hi) {
        final t = (math.log(hz) - math.log(lo)) / (math.log(hi) - math.log(lo));
        return gains[i] + (gains[i + 1] - gains[i]) * t;
      }
    }
    return gains.last;
  }

  bool get active =>
      compress || eqGains.any((g) => g != 0) || preEqGains.any((g) => g != 0);

  /// mpv downmix centre level: raises the dialogue channel when a 5.1 track
  /// is mixed down to stereo. Null keeps mpv's default (-3 dB).
  double? get centerMixLevel => switch (dialog) {
    DialogBoost.off => null,
    DialogBoost.light => 1.0,
    DialogBoost.strong => 1.41,
  };

  /// LoudnessEnhancer gain (mB) for devices without DynamicsProcessing.
  int get loudnessGainMb => compress
      ? 600
      : dialog == DialogBoost.strong
      ? 300
      : 0;

  Map<String, Object> toChannel() => {
    'active': active,
    'preEqCutoffs': preEqCutoffs,
    'preEqGains': preEqGains,
    'eqCenters': kEqBandCenters,
    'eqGains': eqGains,
    'compress': compress,
    'loudnessGainMb': loudnessGainMb,
  };

  @override
  bool operator ==(Object other) =>
      other is AudioEffectsPlan &&
      other.compress == compress &&
      other.dialog == dialog &&
      _sameList(other.eqGains, eqGains) &&
      _sameList(other.preEqGains, preEqGains);

  @override
  int get hashCode => Object.hash(
    compress,
    dialog,
    Object.hashAll(eqGains),
    Object.hashAll(preEqGains),
  );
}
