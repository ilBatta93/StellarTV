import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/app_migration_service.dart';

void main() {
  test('first install runs no cleanup, only records the build', () {
    expect(migrationAction(null, 3005002), MigrationAction.firstRun);
  });
  test('a newer installed build triggers the one-time derived-cache cleanup', () {
    expect(migrationAction(3005002, 3005003), MigrationAction.upgrade);
  });
  test('the same build never re-runs cleanup', () {
    expect(migrationAction(3005002, 3005002), MigrationAction.none);
  });
  test('a downgrade only updates the marker, without any cleanup', () {
    expect(migrationAction(3005003, 3005002), MigrationAction.downgrade);
  });
}
