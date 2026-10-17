/// Clear device state even if a cleanup step fails; never delete cloud rows.
Future<void> logoutFromSettings({
  required Future<void> Function() signOut,
  required Future<void> Function() resetGuest,
  required Future<void> Function() clearPlaylist,
}) async {
  Object? failure;
  for (final action in [signOut, resetGuest, clearPlaylist]) {
    try {
      await action();
    } catch (error) {
      failure ??= error;
    }
  }
  if (failure != null) throw failure;
}
