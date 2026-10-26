import 'epg_program.dart';

/// Device cache contract remains p/n/t, independently of the download worker.
/// A channel index with [declaredCount] is the on-disk guide: programme
/// bodies stay in the channel file and are not part of this object.
class EpgData {
  final Map<String, List<EpgProgram>> programmes;
  final Map<String, String> displayNames;
  final DateTime? fetchedAt;
  final bool degraded;
  final int declaredCount;
  final List<String> channelIndex;
  const EpgData({
    this.programmes = const {},
    this.displayNames = const {},
    this.fetchedAt,
    this.degraded = false,
    this.declaredCount = 0,
    this.channelIndex = const [],
  });
  bool get isEmpty => programmes.isEmpty && channelIndex.isEmpty;
  List<String> get guideIds => channelIndex.isNotEmpty
      ? channelIndex
      : programmes.keys.toList(growable: false);
  int get programmeCount {
    if (channelIndex.isNotEmpty || declaredCount > 0) return declaredCount;
    return programmes.values.fold(0, (sum, list) => sum + list.length);
  }
  static EpgData fromJson(Map<String, dynamic> json) {
    final progs = <String, List<EpgProgram>>{};
    final raw = json['p'];
    if (raw is Map) {
      raw.forEach((id, list) {
        if (list is! List) return;
        progs[id.toString()] = [
          for (final e in list)
            if (e is List && e.length >= 4 && e[0] is int && e[1] is int)
              EpgProgram(
                id: '${id}_${e[0]}',
                channelId: id.toString(),
                title: e[2].toString(),
                description: e[3].toString(),
                startTime: DateTime.fromMillisecondsSinceEpoch(e[0] as int),
                endTime: DateTime.fromMillisecondsSinceEpoch(e[1] as int),
              ),
        ];
      });
    }
    final names = <String, String>{};
    final rawNames = json['n'];
    if (rawNames is Map)
      rawNames.forEach((k, v) => names[k.toString()] = v.toString());
    return EpgData(
      programmes: progs,
      displayNames: names,
      fetchedAt: DateTime.tryParse(json['t']?.toString() ?? ''),
    );
  }
}
