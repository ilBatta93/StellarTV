import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Notified whenever the active profile changes (history, kids filter).
  void Function(UserProfile? profile)? onSelectionChanged;
  String? _announcedId = '__none__';

  void _announce() {
    // A failed cloud read is not a deliberate profile deselection.
    if (_selectedId != null && selected == null) return;
    if (_announcedId == _selectedId) return;
    _announcedId = _selectedId;
    onSelectionChanged?.call(selected);
  }

  UserProfile? get selected =>
      _items.where((e) => e.id == _selectedId).firstOrNull;

  Future<void> load({bool silent = false}) async {
    final code = await _sync.getStoredCode();
    if (code == null) {
      _items = [];
      _loaded = true;
      notifyListeners();
      return;
    }
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }
    // Show the selection saved on this device right away (offline too).
    _selectedId ??= await _service.getSelectedProfileId();
    try {
      _items = await _service.listProfiles(code);
      _selectedId = await _service.getSelectedProfileId();
      if (_selectedId != null && !_items.any((e) => e.id == _selectedId)) {
        _selectedId = null;
        await _service.setSelectedProfileId(null);
      }
      _loaded = true;
      _cacheKids();
    } catch (_) {
      if (!silent) {
        _error = 'Impossibile caricare i profili. Controlla la connessione.';
      }
    } finally {
      _isLoading = false;
      notifyListeners();
      _announce();
    }
  }

  Future<void> select(UserProfile profile) async {
    _selectedId = profile.id;
    notifyListeners();
    _announce();
    await _service.setSelectedProfileId(profile.id);
  }

  /// Remembers which profiles are kids profiles, so the filter applies
  /// immediately at next launch even before the cloud answers.
  Future<void> _cacheKids() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('kids_profile_ids', [
      for (final p in _items)
        if (p.isKids) p.id,
    ]);
  }

  /// True when the profile saved on this device is a kids profile.
  static Future<bool> savedSelectionIsKids(ProfileService service) async {
    final prefs = await SharedPreferences.getInstance();
    final id = await service.getSelectedProfileId();
    return id != null &&
        (prefs.getStringList('kids_profile_ids') ?? const []).contains(id);
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
    bool isKids = false,
  }) async {
    // Genera il codice al primo uso, cosi la creazione non fallisce.
    final code = await _sync.ensureCode();
    final profile = await _service.createProfile(
      syncCode: code,
      name: name,
      avatarKey: avatarKey,
      avatarColor: avatarColor,
      isKids: isKids,
    );
    _items = [..._items, profile];
    _cacheKids();
    notifyListeners();
    return profile;
  }

  Future<void> update(
    UserProfile profile, {
    String? name,
    String? avatarKey,
    String? avatarColor,
    bool? isKids,
  }) async {
    final code = await _sync.getStoredCode();
    if (code == null) return;
    await _service.updateProfile(
      id: profile.id,
      syncCode: code,
      name: name,
      avatarKey: avatarKey,
      avatarColor: avatarColor,
      isKids: isKids,
    );
    _items = [
      for (final p in _items)
        if (p.id == profile.id)
          p.copyWith(
            name: name,
            avatarKey: avatarKey,
            avatarColor: avatarColor,
            isKids: isKids,
          )
        else
          p,
    ];
    _cacheKids();
    notifyListeners();
    if (profile.id == _selectedId) {
      _announcedId = '__changed__';
      _announce();
    }
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
      _announce();
    } catch (_) {
      _error = 'Eliminazione non riuscita. Controlla la connessione.';
    }
    notifyListeners();
  }
}
