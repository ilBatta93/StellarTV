import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/widgets/tv_filter_panel.dart';
import 'package:stellar_tv/widgets/tv_wrap_navigation.dart';

void main() {
  test('filter Left/Right stays on the same row after Up', () {
    expect(TvFilterPanel.horizontalTarget(4, 7, 3, false), 3);
    expect(TvFilterPanel.horizontalTarget(3, 7, 3, false), isNull);
    expect(TvFilterPanel.horizontalTarget(5, 7, 3, true), isNull);
    expect(TvFilterPanel.horizontalTarget(6, 7, 3, true), isNull);
    final above = TvFilterPanel.verticalTarget(4, 7, 3, false);
    expect(above, 1);
    expect(TvFilterPanel.horizontalTarget(above ?? -1, 7, 3, false), 0);
  });
  test('filter panel Down/Up stay inside the panel rows', () {
    // 7 options, 3 columns: rows [0,1,2] [3,4,5] [6]
    expect(TvFilterPanel.verticalTarget(1, 7, 3, true), 4);
    expect(TvFilterPanel.verticalTarget(4, 7, 3, true), 6);
    expect(TvFilterPanel.verticalTarget(6, 7, 3, true), isNull);
    expect(TvFilterPanel.verticalTarget(4, 7, 3, false), 1);
    expect(TvFilterPanel.verticalTarget(1, 7, 3, false), isNull);
  });
  test('wrap navigation picks the nearest item of the adjacent row', () {
    const current = Rect.fromLTWH(200, 0, 100, 40);
    final rects = [
      const Rect.fromLTWH(0, 0, 150, 40),
      const Rect.fromLTWH(0, 50, 120, 40),
      const Rect.fromLTWH(130, 50, 220, 40),
      const Rect.fromLTWH(0, 100, 300, 40),
    ];
    expect(TvWrapNavigation.pick(current, rects, true), 2);
    expect(
      TvWrapNavigation.pick(const Rect.fromLTWH(0, 100, 300, 40), rects, false),
      1,
    );
    expect(
      TvWrapNavigation.pick(const Rect.fromLTWH(0, 100, 300, 40), rects, true),
      isNull,
    );
  });
}
