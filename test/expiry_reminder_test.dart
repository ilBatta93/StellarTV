import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_tv/services/expiry_reminder_service.dart';

void main() {
  const s = ExpiryReminderSettings(thresholds: {7, 3, 1}, hour: 10);
  final expiry = DateTime(2026, 11, 20, 18);

  test('schedules only future thresholds at chosen hour', () {
    final plan = ExpiryPlan.schedule(expiry, s, DateTime(2026, 11, 15, 12));
    expect(plan.keys.toSet(), {3, 1});
    expect(plan[3], DateTime(2026, 11, 17, 10));
  });

  test('disabled schedules nothing', () {
    expect(
      ExpiryPlan.schedule(
        expiry,
        s.copyWith(enabled: false),
        DateTime(2026, 1, 1),
      ),
      isEmpty,
    );
  });

  test('active threshold picks smallest entered window', () {
    expect(
      ExpiryPlan.activeThreshold(expiry, s, DateTime(2026, 11, 1)),
      isNull,
    );
    expect(
      ExpiryPlan.activeThreshold(expiry, s, DateTime(2026, 11, 15, 12)),
      7,
    );
    expect(
      ExpiryPlan.activeThreshold(expiry, s, DateTime(2026, 11, 19, 20)),
      1,
    );
    expect(ExpiryPlan.activeThreshold(expiry, s, DateTime(2026, 11, 21)), 0);
  });

  test('unlimited or missing expiry parses to null', () {
    expect(ExpiryPlan.parseExpiry(null), isNull);
    expect(ExpiryPlan.parseExpiry('0'), isNull);
    expect(ExpiryPlan.parseExpiry('1790000000'), isNotNull);
  });

  test('settings roundtrip', () {
    final r = ExpiryReminderSettings.fromJson(
      s.copyWith(thresholds: {30, 1}, hour: 9).toJson(),
    );
    expect(r.thresholds, {30, 1});
    expect(r.hour, 9);
  });
}
