import 'package:logging/logging.dart';
import 'package:stellar_tv/services/live_preview_policy.dart';

final Logger _logger = Logger('live_preview_policy_check');

void main() {
  void check(bool condition, String name) {
    if (!condition) throw StateError(name);
  }

  check(
    livePreviewMustWait(
      guideReady: false,
      guideLoading: false,
      catalogLoading: false,
    ),
    'Cold guide startup cannot open preview',
  );
  check(
    livePreviewMustWait(
      guideReady: true,
      guideLoading: true,
      catalogLoading: false,
    ),
    'Guide download cannot be cancelled by preview',
  );
  check(
    livePreviewMustWait(
      guideReady: true,
      guideLoading: false,
      catalogLoading: true,
    ),
    'Catalog download cannot be blocked by preview',
  );
  check(
    !livePreviewMustWait(
      guideReady: true,
      guideLoading: false,
      catalogLoading: false,
    ),
    'Settled guide resumes normal preview',
  );
  _logger.info('PASS: 4 live preview loading rules');
}
