import 'dart:async';

import '../models/channel.dart';

enum HistorySignalKind {
  /// Playback of a title started.
  started,

  /// Playback paused or closed before the end.
  paused,

  /// Playback reached the completion share.
  completed,

  /// Marked watched by hand.
  markedWatched,

  /// Marked not watched by hand.
  markedUnwatched,
}

class HistorySignal {
  const HistorySignal({
    required this.kind,
    required this.contentId,
    required this.profileId,
    required this.at,
    this.channel,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });
  final HistorySignalKind kind;
  final String contentId;
  final String? profileId;
  final DateTime at;
  final Channel? channel;
  final Duration position;
  final Duration duration;
}

/// Changes made by the user to the watch history, for services that mirror
/// it elsewhere (Trakt). Changes applied from those services are not sent
/// here, so nothing loops back.
class HistorySignals {
  const HistorySignals._();
  static final _controller = StreamController<HistorySignal>.broadcast();
  static Stream<HistorySignal> get stream => _controller.stream;
  static void emit(HistorySignal signal) {
    if (_controller.hasListener) _controller.add(signal);
  }
}
