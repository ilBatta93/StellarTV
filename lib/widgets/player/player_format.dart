String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String formatSpeed(double speed) => speed == 1.0
    ? 'Normale'
    : '${speed.toString().replaceAll(RegExp(r'\.0$'), '')}x';

String formatDelay(Duration d) {
  final ms = d.inMilliseconds;
  if (ms == 0) return 'Nessuno';
  final sign = ms > 0 ? '+' : '-';
  return '$sign${(ms.abs() / 1000).toStringAsFixed(2)} s';
}
