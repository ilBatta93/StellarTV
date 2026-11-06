/// "Trailer nel banner" of the TV Home. Pure, no I/O.
enum BannerTrailerMode { off, background, panel, scene }

extension BannerTrailerModeInfo on BannerTrailerMode {
  String get label => switch (this) {
    BannerTrailerMode.off => 'Spento',
    BannerTrailerMode.background => 'Sullo sfondo',
    BannerTrailerMode.panel => 'Nel riquadro a destra',
    BannerTrailerMode.scene => "Nell'immagine di scena",
  };

  String get description => switch (this) {
    BannerTrailerMode.off => 'Solo l\'immagine del titolo',
    BannerTrailerMode.background => 'Il trailer prende il posto dell\'immagine',
    BannerTrailerMode.panel => 'Una finestra grande accanto alle informazioni',
    BannerTrailerMode.scene =>
      'Nella copertina selezionata delle liste, quando si apre la scena',
  };

  /// The trailer plays inside the selected cover, not in the banner.
  bool get inScene => this == BannerTrailerMode.scene;

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

/// A trailer costs a web player and a video decoder: TV only, never on
/// devices Android itself marks as low on memory. Memory pressure does not
/// switch it off: it stops the trailer playing, and the next title the
/// remote rests on starts again.
bool bannerTrailerAllowed({
  required BannerTrailerMode mode,
  required bool isTv,
  required bool lowRam,
}) => mode != BannerTrailerMode.off && isTv && !lowRam;

/// Seconds a requested trailer may take to start before the web player is
/// rebuilt and the title tried once more.
const bannerTrailerWatchdogSeconds = 15;

/// "Nel riquadro a destra": a 16:9 window as tall as the banner allows
/// ([bannerHeight] minus [margin] above and below), at most [maxShare] of
/// the width so the title and plot keep their room.
({double width, double height}) trailerPanelSize({
  required double bannerWidth,
  required double bannerHeight,
  double margin = 10,
  double maxShare = 0.46,
}) {
  var height = bannerHeight - 2 * margin;
  if (height <= 0 || bannerWidth <= 0) return (width: 0, height: 0);
  var width = height * 16 / 9;
  final widest = bannerWidth * maxShare;
  if (width > widest) {
    width = widest;
    height = width * 9 / 16;
  }
  return (width: width, height: height);
}

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
