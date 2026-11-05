import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/services/player_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('ogni profilo ha il suo punto di ripresa', () async {
    final settings = PlayerSettingsService();
    const url = 'https://example.invalid/film';
    await settings.saveResumePosition(
      url,
      const Duration(minutes: 40),
      profileId: 'adulto',
    );
    expect(
      await settings.getResumePosition(url, profileId: 'adulto'),
      const Duration(minutes: 40),
    );
    expect(await settings.getResumePosition(url, profileId: 'altro'), isNull);
    expect(await settings.getResumePosition(url), isNull);
  });
}
