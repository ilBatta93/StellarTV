import 'package:flutter/foundation.dart';

/// Lets services that save preferences notify the cloud sync without
/// depending on it. The app wires [onSettingsChanged] to an instant push.
class SyncHooks {
  SyncHooks._();

  static VoidCallback? onSettingsChanged;

  static void settingsChanged() => onSettingsChanged?.call();
}
