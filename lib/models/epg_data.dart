import 'epg_program.dart';

/// Device cache contract remains p/n/t, independently of the download worker.
class EpgData {
  final Map<String, List<EpgProgram>> programmes;
  final Map<String, String> displayNames;
  final DateTime? fetchedAt;
  const EpgData({
    this.programmes = const {},
    this.displayNames = const {},
    this.fetchedAt,
  });
  bool get isEmpty => programmes.isEmpty;
  int get programmeCount =>
      programmes.values.fold(0, (sum, list) => sum + list.length);
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
