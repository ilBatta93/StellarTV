/// Credential edit sequence: authenticate before writing, publish the complete
/// credential set immediately, then refresh through the existing catalog path.
class XtreamEditResult {
  const XtreamEditResult(this.saved, this.synced);
  final bool saved;
  final bool synced;
}

Future<XtreamEditResult> saveXtreamEdit({
  required Future<bool> Function() authenticate,
  required Future<void> Function() persist,
  required Future<bool> Function() sync,
  required Future<void> Function() reload,
}) async {
  if (!await authenticate()) return const XtreamEditResult(false, false);
  await persist();
  var synced = false;
  try {
    synced = await sync();
  } catch (_) {
    /* Device copy remains valid. */
  }
  await reload();
  return XtreamEditResult(true, synced);
}
