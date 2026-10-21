import 'dart:io';

/// Standalone regression checks: dart run test/no_remote_signout_check.dart.
void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
  for (final file in files) {
    final source = file.readAsStringSync();
    if (source.contains('RemoteSignoutService') ||
        source.contains('session_signout_requests') ||
        source.contains('remote_signout_service.dart')) {
      throw StateError('Remote signout request path restored: ${file.path}');
    }
  }
  print('PASS: native app contains no remote signout request path');
  final sync = File('lib/providers/sync_provider.dart').readAsStringSync();
  if (!sync.contains('Future<void> signOut(') ||
      !sync.contains('await _sync.signOut();')) {
    throw StateError('Explicit account signout must remain available');
  }
  print('PASS: explicit account signout remains available');
}
