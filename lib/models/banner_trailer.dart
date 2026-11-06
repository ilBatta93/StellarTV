/// "Trailer nel banner" of the TV Home. Pure, no I/O.
enum BannerTrailerMode { off, background, panel }

extension BannerTrailerModeInfo on BannerTrailerMode {
  String get label => switch (this) {
    BannerTrailerMode.off => 'Spento',
    BannerTrailerMode.background => 'Sullo sfondo',
    BannerTrailerMode.panel => 'Nel riquadro a destra',
  };

  String get description => switch (this) {
    BannerTrailerMode.off => 'Solo l\'immagine del titolo',
    BannerTrailerMode.background => 'Il trailer prende il posto dell\'immagine',
    BannerTrailerMode.panel => 'Una finestra sfumata accanto alle informazioni',
  };

  static BannerTrailerMode parse(Object? value) =>
      BannerTrailerMode.values.asNameMap()[value] ?? BannerTrailerMode.off;
}

enum BannerTrailerAudio { muted, together, delayed, button }

extension BannerTrailerAudioInfo on BannerTrailerAudio {
  String get label => switch (this) {
    BannerTrailerAudio.muted => 'Sempre muto',
    BannerTrailerAudio.together => 'Insieme al trailer',
    BannerTrailerAudio.delayed => 'Dopo qualche secondo',
    BannerTrailerAudio.button => 'Col pulsante',
  };

  String get description => switch (this) {
    BannerTrailerAudio.muted => 'Solo immagini',
    BannerTrailerAudio.together =>
      "L'audio sale piano, in dissolvenza, appena parte il video",
    BannerTrailerAudio.delayed =>
      'Parte muto, l\'audio arriva dopo altri $bannerAudioDelaySeconds secondi',
    BannerTrailerAudio.button =>
      'L\'audio parte fermandoti su Trailer o Guarda nel banner',
  };

  static BannerTrailerAudio parse(Object? value) =>
      BannerTrailerAudio.values.asNameMap()[value] ?? BannerTrailerAudio.button;
}

/// Seconds the remote rests on the same title before the trailer starts.
const bannerTrailerDelays = [3, 5, 8];
const bannerTrailerDefaultDelay = 5;

/// Seconds of muted trailer before the sound in [BannerTrailerAudio.delayed].
const bannerAudioDelaySeconds = 5;

int parseBannerTrailerDelay(Object? value) =>
    value is int && bannerTrailerDelays.contains(value)
    ? value
    : bannerTrailerDefaultDelay;

/// A trailer in the banner costs a web player and a video decoder: never on
/// low-memory devices or while the app is already saving memory.
bool bannerTrailerAllowed({
  required BannerTrailerMode mode,
  required bool isTv,
  required bool lowRam,
  required bool memoryPressure,
}) => mode != BannerTrailerMode.off && isTv && !lowRam && !memoryPressure;

/// Sound of a playing banner trailer: [playedFor] is how long it has been
/// playing, [onButton] whether the remote rests on Trailer or Guarda.
bool bannerTrailerAudible({
  required BannerTrailerAudio audio,
  required Duration playedFor,
  required bool onButton,
}) => switch (audio) {
  BannerTrailerAudio.muted => false,
  BannerTrailerAudio.together => true,
  BannerTrailerAudio.delayed =>
    onButton || playedFor >= const Duration(seconds: bannerAudioDelaySeconds),
  BannerTrailerAudio.button => onButton,
};

/// Volume step of the sound fade (every 90 ms, up to 100): with the sound
/// starting together with the video the fade is slower, so it never bursts
/// in at full volume.
int bannerAudioFadeStep(BannerTrailerAudio audio) =>
    audio == BannerTrailerAudio.together ? 4 : 8;
