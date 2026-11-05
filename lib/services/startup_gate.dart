import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Holds the heavy, non-essential loads of a launch (ratings, identities,
/// facets, segments) until the intro has played and the first screen is up.
/// Decoding tens of MB of JSON in parallel isolates during the intro made it
/// slow and jerky on the TV: those isolates share the heap with the UI
/// isolate, so their collections pause its frames, and they take every core
/// the raster thread needs.
class StartupGate {
  StartupGate._();

  static var _open = Completer<void>();
  static Timer? _fallback;

  /// Tests run without an intro, so the gate starts open there unless a
  /// test of the gate itself turns this off.
  @visibleForTesting
  static bool openInTests = Platform.environment.containsKey('FLUTTER_TEST');

  /// Longest wait, should the intro never report its end.
  @visibleForTesting
  static Duration fallback = const Duration(seconds: 8);

  static bool get isOpen => _open.isCompleted || openInTests;

  /// Lets the held loads start. Safe to call more than once.
  static void open() {
    _fallback?.cancel();
    if (!_open.isCompleted) _open.complete();
  }

  /// Completes once [open] is called, or after [fallback] at the latest.
  static Future<void> wait() {
    if (isOpen) return Future.value();
    _fallback ??= Timer(fallback, open);
    return _open.future;
  }

  @visibleForTesting
  static void reset() {
    _fallback?.cancel();
    _fallback = null;
    _open = Completer<void>();
  }
}
