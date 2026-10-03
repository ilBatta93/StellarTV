class EpgProgram {
  final String id;
  final String channelId;
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime endTime;

  EpgProgram({
    required this.id,
    required this.channelId,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
  });

  bool get isNow {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  String get timeRange {
    final startH = startTime.hour.toString().padLeft(2, '0');
    final startM = startTime.minute.toString().padLeft(2, '0');
    final endH = endTime.hour.toString().padLeft(2, '0');
    final endM = endTime.minute.toString().padLeft(2, '0');
    return '$startH:$startM - $endH:$endM';
  }
}
