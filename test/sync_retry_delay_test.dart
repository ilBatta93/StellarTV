import 'package:flutter_test/flutter_test.dart';
import '../lib/providers/sync_provider.dart';

void main() {
  test('failed cloud saves back off instead of retrying in a loop', () {
    expect(SyncProvider.retryDelay(1), const Duration(seconds: 5));
    expect(SyncProvider.retryDelay(2), const Duration(seconds: 10));
    expect(SyncProvider.retryDelay(4), const Duration(seconds: 40));
    expect(SyncProvider.retryDelay(20), const Duration(minutes: 10));
  });
}
