import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_tv/services/settings_service.dart';

class _FakeKeychain implements CredentialKeychain {
  final values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('keychain');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  late _FakeKeychain keychain;

  setUp(() {
    keychain = _FakeKeychain();
    SettingsService.useKeychain = true;
    SettingsService.keychain = keychain;
  });

  tearDown(() {
    SettingsService.useKeychain = false;
    SettingsService.keychain = const SecureCredentialKeychain();
  });

  test('Access data in preferences moves to the Keychain', () async {
    SharedPreferences.setMockInitialValues({
      'xtream_server': 'http://sorgente.test',
      'xtream_username': 'utente',
      'xtream_password': 'segreto',
    });
    final creds = await SettingsService().getXtreamCredentials();
    expect(creds?['password'], 'segreto');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('xtream_password'), isNull);
    expect(prefs.getString('xtream_server'), isNull);
    expect(keychain.values['xtream_password'], 'segreto');
    expect(
      (await SettingsService().getXtreamCredentials())?['server'],
      'http://sorgente.test',
    );
  });

  test('A failing Keychain keeps the preference copy', () async {
    SharedPreferences.setMockInitialValues({
      'xtream_server': 'http://sorgente.test',
      'xtream_username': 'utente',
      'xtream_password': 'segreto',
    });
    keychain.failWrites = true;
    final creds = await SettingsService().getXtreamCredentials();
    expect(creds?['username'], 'utente');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('xtream_password'), 'segreto');
  });

  test('A Keychain copy left by an uninstall is not used', () async {
    SharedPreferences.setMockInitialValues({});
    keychain.values.addAll({
      'xtream_server': 'http://vecchia.test',
      'xtream_username': 'vecchio',
      'xtream_password': 'vecchia',
    });
    expect(await SettingsService().getXtreamCredentials(), isNull);
    expect(keychain.values, isEmpty);
  });

  test('Saving and clearing use the Keychain only', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.setXtreamCredentials(
      server: 'http://sorgente.test',
      username: 'utente',
      password: 'segreto',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('xtream_password'), isNull);
    expect((await settings.getXtreamCredentials())?['password'], 'segreto');
    await settings.clearCredentials();
    expect(keychain.values, isEmpty);
    expect(await settings.getXtreamCredentials(), isNull);
  });
}
