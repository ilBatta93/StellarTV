import 'package:logging/logging.dart';
import 'package:stellar_tv/player/tv_playback_shortcuts.dart';

final Logger _logger = Logger('tv_playback_shortcuts_check');

void expectEqual(Object? actual, Object? expected, String rule) {
  if (actual != expected) throw StateError('$rule: $actual != $expected');
}

void main() {
  TvHiddenAction action(
    TvHiddenKey key, {
    bool live = false,
    bool repeat = false,
    bool intro = false,
    bool outro = false,
  }) => tvHiddenAction(
    key,
    live: live,
    repeat: repeat,
    intro: intro,
    outro: outro,
  );
  expectEqual(
    action(TvHiddenKey.ok),
    TvHiddenAction.pauseAndControls,
    'OK pauses and reveals',
  );
  expectEqual(
    action(TvHiddenKey.ok, live: true),
    TvHiddenAction.pauseAndControls,
    'Live OK uses existing pause',
  );
  expectEqual(
    action(TvHiddenKey.ok, intro: true),
    TvHiddenAction.skipIntro,
    'Intro has priority',
  );
  expectEqual(
    action(TvHiddenKey.ok, outro: true),
    TvHiddenAction.outro,
    'Outro has priority',
  );
  expectEqual(action(TvHiddenKey.up), TvHiddenAction.info, 'VOD up info');
  expectEqual(
    action(TvHiddenKey.down),
    TvHiddenAction.quickPanel,
    'VOD down panel',
  );
  expectEqual(
    action(TvHiddenKey.up, live: true),
    TvHiddenAction.previousChannel,
    'Live up previous',
  );
  expectEqual(
    action(TvHiddenKey.down, live: true),
    TvHiddenAction.nextChannel,
    'Live down next',
  );
  for (final key in TvHiddenKey.values) {
    expectEqual(
      action(key, repeat: true),
      TvHiddenAction.none,
      'No repeated VOD action $key',
    );
    expectEqual(
      action(key, live: true, repeat: true),
      TvHiddenAction.none,
      'No repeated live action $key',
    );
  }
  expectEqual(
    remainingPlaybackTime(
      const Duration(minutes: 10),
      const Duration(minutes: 2),
      2,
    ),
    const Duration(minutes: 4),
    'End estimate respects speed',
  );
  expectEqual(
    remainingPlaybackTime(Duration.zero, Duration.zero, 1),
    null,
    'No invented duration',
  );
  expectEqual(
    remainingPlaybackTime(
      const Duration(seconds: 10),
      const Duration(seconds: 11),
      1,
    ),
    Duration.zero,
    'No negative remaining time',
  );
  _logger.info('PASS: 17 playback shortcut and remaining-time checks');
}
