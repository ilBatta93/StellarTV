import 'package:logging/logging.dart';
import 'package:stellar_tv/models/device_backup_policy.dart';
import 'package:stellar_tv/models/trakt_policy.dart';

final Logger _logger = Logger('trakt_policy_check');

void check(bool result, String rule) {
  if (!result) throw StateError(rule);
  _logger.info('PASS: $rule');
}

void main() {
  final t0 = DateTime.utc(2026, 11, 1);
  check(
    !TraktPolicy.applyRemoteWatched(
      remoteAt: t0,
      locallyWatched: false,
      localChoiceAt: t0.add(const Duration(seconds: 1)),
    ),
    'a newer "not watched" choice made here is not undone by Trakt',
  );
  check(
    !TraktPolicy.applyRemoteProgress(
      remote: TraktPlayback(key: 'movie:1', progress: 0.5, pausedAt: t0),
      locallyWatched: false,
      completionPercent: 90,
      removedAt: t0.add(const Duration(seconds: 1)),
    ),
    'a title removed from the history here does not come back from Trakt',
  );
  check(
    !TraktPolicy.pushWatched(
      const TraktTarget.movie(tmdbId: 1),
      TraktRemoteState(watched: {'movie:1': t0}),
    ),
    'a manual mark never adds a second view on Trakt',
  );
  check(
    !DeviceBackupPolicy.keepsSecret('trakt_session_v1:p1') &&
        DeviceBackupPolicy.keepsSecret('service_key_trakt_client_id'),
    'the Trakt sign-in stays out of the backup, the user keys go in',
  );
  check(
    !DeviceBackupPolicy.keepsPref('trakt_outbox_v1:p1'),
    'Trakt sync markers follow the sign-in and stay out of the backup',
  );
}
