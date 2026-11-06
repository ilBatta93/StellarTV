import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vpn_config_policy.dart';

enum VpnState { off, connecting, connected, error }

/// Optional personal VPN (WireGuard, Android only). The tunnel runs inside
/// the app through the native `stellartv/vpn` channel.
///
/// The configuration holds a private key: it stays in the device secure
/// storage, never in preferences, cloud or logs. The NordVPN access key is
/// used once to read the WireGuard key and is not stored.
class VpnService extends ChangeNotifier {
  VpnService._();

  static final instance = VpnService._();

  static const _channel = MethodChannel('stellartv/vpn');
  static const _storage = FlutterSecureStorage();
  static const _configKey = 'vpn_config_v1';
  static const _enabledKey = 'vpn_enabled_v1';
  static const _appOnlyKey = 'vpn_app_only_v1';
  static const _labelKey = 'vpn_label_v1';
  static const _sourceKey = 'vpn_source_v1';
  static const _countryKey = 'vpn_country_v1';

  /// `nord` (built from the access key) or `file` (pasted configuration).
  static const sourceNord = 'nord';
  static const sourceFile = 'file';

  static bool get supported => !kIsWeb && Platform.isAndroid;

  String? _config;
  bool _enabled = false;
  bool _appOnly = true;
  String? _label;
  String? _source;
  int? _countryId;
  VpnState _state = VpnState.off;
  String? _problem;

  bool get configured => _config != null;
  bool get enabled => _enabled;
  bool get appOnly => _appOnly;
  String? get label => _label;
  String? get source => _source;
  int? get countryId => _countryId;
  VpnState get state => _state;

  /// Last error, in Italian, for the user.
  String? get problem => _problem;

  /// Set when the VPN was enabled but did not start at launch: the splash
  /// asks the user before going on.
  String? startupProblem;

  /// Reads the saved setup and, when enabled, starts the tunnel before the
  /// app opens any connection. Never throws and never waits more than ~12 s.
  Future<void> install() async {
    if (!supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? false;
      _appOnly = prefs.getBool(_appOnlyKey) ?? true;
      _label = prefs.getString(_labelKey);
      _source = prefs.getString(_sourceKey);
      _countryId = prefs.getInt(_countryKey);
      _config = await _storage.read(key: _configKey);
    } catch (e) {
      debugPrint('VPN: setup not readable');
    }
    if (!_enabled || _config == null) return;
    final ok = await connect(interactive: false).timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        _set(VpnState.error, 'La VPN non ha risposto in tempo');
        return false;
      },
    );
    if (!ok) startupProblem = _problem ?? 'Connessione non riuscita';
  }

  /// Starts the tunnel. With [interactive] Android may ask the user to allow
  /// the VPN (once per installation).
  Future<bool> connect({bool interactive = true}) async {
    final config = _config;
    if (!supported || config == null) return false;
    _set(VpnState.connecting, null);
    try {
      await _channel.invokeMethod<void>('connect', {
        'config': config,
        'appOnly': _appOnly,
        'interactive': interactive,
      });
      final handshake = await _waitHandshake();
      if (!handshake) {
        _set(
          VpnState.error,
          'Il server VPN non risponde: controlla la configurazione '
          'o scegli un altro server',
        );
        return false;
      }
      startupProblem = null;
      _set(VpnState.connected, null);
      return true;
    } on PlatformException catch (e) {
      _set(VpnState.error, _message(e.code));
      return false;
    } catch (_) {
      _set(VpnState.error, 'Connessione non riuscita');
      return false;
    }
  }

  Future<void> disconnect() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('disconnect');
    } catch (_) {}
    _set(VpnState.off, null);
  }

  /// A handshake proves the server accepted the key. Keepalive starts one
  /// right away, so a few seconds are enough.
  Future<bool> _waitHandshake() async {
    for (var i = 0; i < 16; i++) {
      final s = await stats();
      if ((s?['handshake'] ?? 0) > 0) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// `{handshake: epoch ms, rx: bytes, tx: bytes}` of the running tunnel.
  Future<Map<String, int>?> stats() async {
    if (!supported) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('stats');
      if (raw == null) return null;
      return raw.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
    } catch (_) {
      return null;
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _prefs((p) => p.setBool(_enabledKey, value));
    notifyListeners();
    if (value) {
      await connect();
    } else {
      await disconnect();
    }
  }

  Future<void> setAppOnly(bool value) async {
    _appOnly = value;
    await _prefs((p) => p.setBool(_appOnlyKey, value));
    notifyListeners();
    if (_state == VpnState.connected) await connect();
  }

  /// Saves a pasted WireGuard configuration. Throws [FormatException].
  Future<void> saveFile(String text) async {
    final summary = VpnConfigPolicy.parse(text);
    await _save(
      config: text.trim(),
      label: summary.endpoint.split(':').first,
      source: sourceFile,
      countryId: null,
    );
  }

  /// NordVPN setup: the access key (Nord Account > manual setup) gives the
  /// WireGuard private key; then the best server of [countryId] is chosen
  /// (`null`: the best one overall). Throws [VpnSetupException].
  Future<void> setupNord(String accessKey, {int? countryId}) async {
    final key = await _nordPrivateKey(accessKey.trim());
    await _useNordServer(key, countryId);
  }

  /// New NordVPN server with the key already saved.
  Future<void> changeNordCountry(int? countryId) async {
    final config = _config;
    if (config == null) return;
    final key = VpnConfigPolicy.parse(config).privateKey;
    await _useNordServer(key, countryId);
  }

  Future<List<NordCountry>> nordCountries() async {
    final res = await _get(
      Uri.parse('https://api.nordvpn.com/v1/servers/countries'),
    );
    return VpnConfigPolicy.nordCountries(jsonDecode(res.body));
  }

  /// Public address the app is seen from, for the "check" button:
  /// `(ip, place, protected)`. NordVPN answers for any connection.
  Future<({String ip, String place, bool protected})?> checkAddress() async {
    try {
      final res = await _get(
        Uri.parse('https://api.nordvpn.com/v1/helpers/ips/insights'),
      );
      final data = jsonDecode(res.body);
      if (data is! Map || data['ip'] is! String) return null;
      final place = [
        data['city'],
        data['country'],
      ].whereType<String>().join(', ');
      return (
        ip: data['ip'] as String,
        place: place,
        protected: data['protected'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Removes everything: the tunnel stops and the key is deleted.
  Future<void> forget() async {
    await disconnect();
    _config = null;
    _label = null;
    _source = null;
    _countryId = null;
    _enabled = false;
    try {
      await _storage.delete(key: _configKey);
    } catch (_) {}
    await _prefs((p) async {
      await p.remove(_labelKey);
      await p.remove(_sourceKey);
      await p.remove(_countryKey);
      await p.setBool(_enabledKey, false);
    });
    notifyListeners();
  }

  Future<String> _nordPrivateKey(String accessKey) async {
    if (accessKey.isEmpty) {
      throw const VpnSetupException('Inserisci il token di accesso NordVPN');
    }
    final auth = base64.encode(utf8.encode('token:$accessKey'));
    final res = await _get(
      Uri.parse('https://api.nordvpn.com/v1/users/services/credentials'),
      headers: {'Authorization': 'Basic $auth'},
    );
    final data = jsonDecode(res.body);
    final key = data is Map ? data['nordlynx_private_key'] : null;
    if (key is! String || !VpnConfigPolicy.isKey(key)) {
      throw const VpnSetupException(
        'NordVPN non ha restituito la chiave: verifica che il tuo '
        'account NordVPN sia attivo',
      );
    }
    return key;
  }

  Future<void> _useNordServer(String privateKey, int? countryId) async {
    final query = {
      'filters[servers_technologies][identifier]': 'wireguard_udp',
      'limit': '1',
      if (countryId != null) 'filters[country_id]': '$countryId',
    };
    final res = await _get(
      Uri.https('api.nordvpn.com', '/v1/servers/recommendations', query),
    );
    final server = VpnConfigPolicy.nordServer(jsonDecode(res.body));
    if (server == null) {
      throw const VpnSetupException(
        'Nessun server disponibile in questo paese: scegline un altro',
      );
    }
    await _save(
      config: VpnConfigPolicy.nordConfig(
        privateKey: privateKey,
        server: server,
      ),
      label: server.label,
      source: sourceNord,
      countryId: countryId,
    );
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) async {
    final http.Response res;
    try {
      res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const VpnSetupException(
        'NordVPN non raggiungibile: controlla la connessione',
      );
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const VpnSetupException(
        'Token non valido o scaduto: generane uno nuovo dal tuo account '
        'NordVPN',
      );
    }
    if (res.statusCode != 200) {
      throw VpnSetupException('NordVPN ha risposto ${res.statusCode}');
    }
    return res;
  }

  Future<void> _save({
    required String config,
    required String label,
    required String source,
    required int? countryId,
  }) async {
    await _storage.write(key: _configKey, value: config);
    _config = config;
    _label = label;
    _source = source;
    _countryId = countryId;
    await _prefs((p) async {
      await p.setString(_labelKey, label);
      await p.setString(_sourceKey, source);
      if (countryId == null) {
        await p.remove(_countryKey);
      } else {
        await p.setInt(_countryKey, countryId);
      }
    });
    notifyListeners();
    // A new server replaces the running tunnel.
    if (_enabled || _state == VpnState.connected) await connect();
  }

  Future<void> _prefs(Future<void> Function(SharedPreferences) write) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (_) {}
  }

  void _set(VpnState state, String? problem) {
    _state = state;
    _problem = problem;
    notifyListeners();
  }

  static String _message(String code) => switch (code) {
    'permission' =>
      'Serve il permesso VPN: apri le impostazioni VPN e premi Connetti',
    'denied' => 'Permesso VPN non concesso',
    'config' => 'Configurazione WireGuard non valida',
    'always_on' =>
      'Un\'altra app VPN è impostata come sempre attiva su questo '
          'dispositivo: disattivala dalle impostazioni di Android',
    _ => 'Connessione VPN non riuscita',
  };
}

class VpnSetupException implements Exception {
  const VpnSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}
