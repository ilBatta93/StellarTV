import 'dart:io';

/// Focus roles must be recognised by node type (TvSearchFocusNode,
/// TvPanelScopeNode, TvEntryFocusNode...). FocusNode.debugLabel is empty
/// in release and profile builds, so a comparison with it never matches on
/// a real TV even though every debug test passes.
void check(bool condition, String rule) {
  if (!condition) throw StateError(rule);
}

void main() {
  final reads = RegExp(r'debugLabel\s*(==|!=|\?\.|\.|!)');
  final offenders = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (reads.hasMatch(lines[i])) offenders.add('${entity.path}:${i + 1}');
    }
  }
  check(
    offenders.isEmpty,
    'il codice non legge debugLabel per riconoscere un nodo: '
    '${offenders.join(', ')}',
  );
}
