import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The user's own keys for external services, used instead of the ones
/// StellarTV provides. They stay in this device's secure storage (the same
/// store as the source access, so the phone backup carries them) and never
/// reach the cloud.
class ServiceKeys extends ChangeNotifier {
  ServiceKeys._();
  static final instance = ServiceKeys._();

  // Same options as settings_service.dart: device_backup.dart reads it.
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const _traktId = 'service_key_trakt_client_id';
  static const _traktSecret = 'service_key_trakt_client_secret';

  String _traktClientId = '';
  String _traktClientSecret = '';
  bool _loaded = false;

  String get traktClientId => _traktClientId;
  String get traktClientSecret => _traktClientSecret;

  /// True when the user entered their own Trakt app. The secret is
  /// optional: Trakt apps created since October 2026 have none.
  bool get traktOwn => _traktClientId.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    try {
      _traktClientId = (await _storage.read(key: _traktId))?.trim() ?? '';
      _traktClientSecret =
          (await _storage.read(key: _traktSecret))?.trim() ?? '';
    } catch (_) {
      // Unreadable store (keystore reset): StellarTV's keys stay in use.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Saves the user's Trakt app; an empty Client ID goes back to
  /// StellarTV's.
  Future<void> setTrakt(String clientId, String clientSecret) async {
    final id = clientId.trim();
    final secret = id.isEmpty ? '' : clientSecret.trim();
    if (id.isEmpty) {
      await _storage.delete(key: _traktId);
    } else {
      await _storage.write(key: _traktId, value: id);
    }
    if (secret.isEmpty) {
      await _storage.delete(key: _traktSecret);
    } else {
      await _storage.write(key: _traktSecret, value: secret);
    }
    _traktClientId = id;
    _traktClientSecret = secret;
    notifyListeners();
  }
}
