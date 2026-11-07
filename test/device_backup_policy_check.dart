import 'package:logging/logging.dart';
import 'package:stellar_tv/models/device_backup_policy.dart';

final Logger _logger = Logger('device_backup_policy_check');

void check(bool result, String rule) {
  if (!result) throw StateError(rule);
  _logger.info('PASS: $rule');
}

void main() {
  const p = DeviceBackupPolicy.keepsPref;
  check(
    !p('sb-dzojklhnwdjcrmkbepft-auth-token'),
    'a session is never copied: two devices sharing it would sign out',
  );
  check(
    !p('sync_code') && !p('sync_last_saved_snapshot'),
    'sync markers follow the session, so a restored device resyncs',
  );
  check(!p('offline_downloads_v1'), 'nothing about downloads enters a backup');
  check(
    p('xtream_server') && p('kids_pin') && p('vpn_enabled_v1'),
    'source, child PIN and VPN choices are part of the backup',
  );
  check(
    !DeviceBackupPolicy.keepsSecret('trakt_session_v1:p1') &&
        !p('trakt_outbox_v1:p1') &&
        DeviceBackupPolicy.keepsSecret('xtream_username'),
    'a Trakt sign-in is never copied: Trakt rotates it at every renewal',
  );
  const f = DeviceBackupPolicy.keepsFile;
  check(!f('downloads/x.mp4'), 'downloaded videos stay out of the backup');
  check(
    !f('../shared_prefs/x.xml') && !f('/data/x'),
    'a restored path never leaves the support folder',
  );
  check(f('json_cache/a.json'), 'support-folder files are part of the backup');
  check(
    DeviceBackupPolicy.secureStores.length == 3,
    'every secure-storage configuration is saved',
  );
}
