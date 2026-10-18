import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/sync_service.dart';

void main() {
  test('auth tokens and PKCE state never sync between devices', () {
    for (final key in [
      'sb-project-auth-token',
      'supabase.auth.token',
      'supabase.auth.refreshToken',
      'sb-project-auth-token-code-verifier',
    ]) {
      expect(SyncService.isSyncedKey(key), isFalse, reason: key);
    }
    expect(SyncService.isSyncedKey('xtream_password'), isTrue);
  });

  test('player and look settings are synced to the cloud', () {
    expect(SyncService.isSyncedKey('player_settings_v1_liveTv'), isTrue);
    expect(SyncService.isSyncedKey('ui_catalog_view'), isTrue);
    expect(SyncService.isSyncedKey('ui_text_scale'), isTrue);
  });

  test('caches and device state stay on the device', () {
    expect(SyncService.isSyncedKey('discover_cache_v1'), isFalse);
    expect(SyncService.isSyncedKey('offline_downloads_v1'), isFalse);
    expect(SyncService.isSyncedKey('stellar_guest_mode'), isFalse);
    expect(SyncService.isSyncedKey('local_watch_history__abc'), isFalse);
  });
}
