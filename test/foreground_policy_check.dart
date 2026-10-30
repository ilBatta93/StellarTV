import 'package:logging/logging.dart';
import 'package:stellar_tv/services/foreground_policy.dart';
import 'package:stellar_tv/services/playback_work_policy.dart';

final Logger _logger = Logger('foreground_policy_check');

void check(bool result, String rule) {
  if (!result) throw StateError(rule);
  _logger.info('PASS: $rule');
}

void main() {
  final p = ForegroundPolicy.instance;
  final work = PlaybackWorkPolicy();
  var events = 0;
  void changed() => events++;
  p.addListener(changed);
  check(p.active, 'visible resumed app permits work');
  p.setResumed(false);
  check(
    !p.active && work.blocksCloud && work.blocksGuide && !work.hasPlayback,
    'background blocks remote work without inventing playback',
  );
  p.setResumed(false);
  check(
    events == 1,
    'duplicate lifecycle state cannot start extra resume work',
  );
  p.setDisplayAvailable(false);
  p.setResumed(true);
  check(!p.active, 'resumed lifecycle cannot override TV-off signal');
  p.setDisplayAvailable(true);
  check(p.active && events == 2, 'screen return resumes once');
  final player = Object();
  work.update(player, cloudBlocked: true);
  p.setResumed(false);
  p.setResumed(true);
  check(
    work.blocksCloud && work.blocksGuide,
    'foreground return does not release playing video protection',
  );
  work.remove(player);
  check(
    !work.blocksCloud && !work.blocksGuide,
    'last video close releases foreground work',
  );
  p.removeListener(changed);
  final count = events;
  p.setResumed(false);
  check(events == count, 'removed listener stays silent');
  p.setResumed(true);
}
