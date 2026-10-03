import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../services/sync_service.dart';

/// Loads and manages the profiles linked to this device's sync code, plus
/// which profile is currently selected on this device.
class ProfileProvider extends ChangeNotifier {
  ProfileProvider(this._service, this._sync);

  final ProfileService _service;
  final SyncService _sync;

  List<UserProfile> _items = [];
  String? _selectedId;
  bool _isLoading = false;
  bool _loaded = false;
  String? _error;

  List<UserProfile> get items => _items;
  String? get selectedId => _selectedId;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _loaded;
  String? get error => _error;

  UserProfile? get selected =>
      _items.where((e) => e.id == _selectedId).firstOrNull;

  Future<void> load() async {
    final code = await _sync.getStoredCode();
    if (code == null) {
      _items = [];
      _loaded = true;
      notifyListeners();
      return;
    }
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _service.listProfiles(code);
      _selectedId = await _service.getSelectedProfileId();
      if (_selectedId != null && !_items.any((e) => e.id == _selectedId)) {
        _selectedId = null;
        await _service.setSelectedProfileId(null);
      }
      _loaded = true;
    } catch (_) {
      _error = 'Impossibile caricare i profili. Controlla la connessione.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> select(UserProfile profile) async {
    _selectedId = profile.id;
    notifyListeners();
    await _service.setSelectedProfileId(profile.id);
  }

  /// True when a profile picker decision is still needed after launch:
  /// profiles exist but none has been chosen on this device yet.
  Future<bool> needsSelection() async {
    if (!_loaded) await load();
    return _items.isNotEmpty && _selectedId == null;
  }

  Future<UserProfile> create({
    required String name,
    required String avatarKey,
    required String avatarColor,
  }) async {
    final code = await _sync.getStoredCode();
    if (code == null) {
      throw Exception('Nessun codice di sincronizzazione configurato.');
    }
    final profile = await _service.createProfile(
      syncCode: code,
      name: name,
      avatarKey: avatarKey,
      avatarColor: avatarColor,
    );
    _items = [..._items, profile];
    notifyListeners();
    return profile;
  }

  Future<void> update(
    UserProfile profile, {
    String? name,
    String? avatarKey,
    String? avatarColor,
  }) async {
    final code = await _sync.getStoredCode();
    if (code == null) return;
    await _service.updateProfile(
      id: profile.id,
      syncCode: code,
      name: name,
      avatarKey: avatarKey,
      avatarColor: avatarColor,
    );
    _items = [
      for (final p in _items)
        if (p.id == profile.id)
          p.copyWith(name: name, avatarKey: avatarKey, avatarColor: avatarColor)
        else
          p,
    ];
    notifyListeners();
  }

  Future<void> delete(UserProfile profile) async {
    final code = await _sync.getStoredCode();
    if (code == null) return;
    try {
      await _service.deleteProfile(id: profile.id, syncCode: code);
      _items = _items.where((e) => e.id != profile.id).toList();
      if (_selectedId == profile.id) {
        _selectedId = null;
        await _service.setSelectedProfileId(null);
      }
    } catch (_) {
      _error = 'Eliminazione non riuscita. Controlla la connessione.';
    }
    notifyListeners();
  }
}
