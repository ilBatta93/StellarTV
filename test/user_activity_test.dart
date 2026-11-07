import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/user_activity.dart';

void main() {
  test('background work waits for a quiet remote', () async {
    final activity = UserActivity.instance..noteActivity();
    expect(activity.idleFor, lessThan(const Duration(seconds: 1)));
    final clock = Stopwatch()..start();
    await activity.waitIdle(quiet: const Duration(milliseconds: 400));
    expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(300));
    // Already quiet: no wait.
    clock.reset();
    await activity.waitIdle(quiet: const Duration(milliseconds: 100));
    expect(clock.elapsedMilliseconds, lessThan(300));
    // The cap ends the wait even under continuous use.
    clock.reset();
    await activity.waitIdle(
      quiet: const Duration(hours: 1),
      atMost: const Duration(milliseconds: 200),
    );
    expect(clock.elapsedMilliseconds, lessThan(2000));
  });
}
