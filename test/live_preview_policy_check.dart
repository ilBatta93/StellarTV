import '../lib/services/live_preview_policy.dart';

void main() {
  void check(bool condition, String name) {
    if (!condition) throw StateError(name);
  }
  check(livePreviewMustWait(guideReady: false, guideLoading: false,
      catalogLoading: false), 'Cold guide startup cannot open preview');
  check(livePreviewMustWait(guideReady: true, guideLoading: true,
      catalogLoading: false), 'Guide download cannot be cancelled by preview');
  check(livePreviewMustWait(guideReady: true, guideLoading: false,
      catalogLoading: true), 'Catalog download cannot be blocked by preview');
  check(!livePreviewMustWait(guideReady: true, guideLoading: false,
      catalogLoading: false), 'Settled guide resumes normal preview');
  print('PASS: 4 live preview loading rules');
}