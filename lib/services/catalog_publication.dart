import '../models/channel.dart';
import '../models/content_type.dart';

/// A small cooperative budget keeps remote input and Flutter frames runnable.
/// Filtering stays in the owning isolate so strict Kids evidence isn't copied.
Future<List<Channel>?> replaceCatalogSection({
  required List<Channel> current,
  required List<Channel> replacement,
  required ContentType type,
  required bool Function() stillCurrent,
}) async {
  final output = <Channel>[];
  for (var i = 0; i < current.length; i++) {
    final c = current[i];
    if (c.type != type &&
        !(type == ContentType.series && c.type == ContentType.anime)) {
      output.add(c);
    }
    if ((i + 1) % 128 == 0) {
      await Future<void>.delayed(Duration.zero);
      if (!stillCurrent()) return null;
    }
  }
  for (var i = 0; i < replacement.length; i++) {
    output.add(replacement[i]);
    if ((i + 1) % 128 == 0) {
      await Future<void>.delayed(Duration.zero);
      if (!stillCurrent()) return null;
    }
  }
  return stillCurrent() ? output : null;
}

Future<List<Channel>?> filterCatalogForPublication({
  required List<Channel> channels,
  required bool Function(Channel) allowed,
  required bool Function() stillCurrent,
  void Function(List<Channel>)? requestEvidence,
}) async {
  final output = <Channel>[];
  var started = DateTime.now();
  var evidenceStart = 0;
  for (var i = 0; i < channels.length; i++) {
    if (allowed(channels[i])) output.add(channels[i]);
    if ((i + 1) % 128 == 0 ||
        DateTime.now().difference(started).inMilliseconds >= 2) {
      if (requestEvidence != null) {
        // Evidence queue batches must remain bounded too.
        requestEvidence(channels.sublist(evidenceStart, i + 1));
        evidenceStart = i + 1;
      }
      await Future<void>.delayed(Duration.zero);
      if (!stillCurrent()) return null;
      started = DateTime.now();
    }
  }
  if (requestEvidence != null && evidenceStart < channels.length) {
    requestEvidence(channels.sublist(evidenceStart));
  }
  return stillCurrent() ? output : null;
}
