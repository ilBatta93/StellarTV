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

  /// Name changes reload right away when the vault brings them; only
  /// table-only edits (avatar, color, kids flag, profiles added from the
  /// site) rely on this periodic reread.
  static const refreshAge = Duration(minutes: 30);
  DateTime? _fetchedAt;
  bool _namesPending = false;

  /// Rereads the table after an automatic cloud pull, at most every
  /// [refreshAge] unless a plain name is still waiting to leave the table.
  Future<void> refreshIfStale({DateTime? now}) async {
    final at = _fetchedAt;
    if (!_namesPending &&
        at != null &&
        (now ?? DateTime.now()).difference(at) < refreshAge) {
      return;
    }
    await load(silent: true);
  }

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
      _items = await _withNames(code, await _service.listProfiles(code));
      _fetchedAt = DateTime.now();
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

  /// Names live in the encrypted vault; the table keeps an empty
  /// placeholder. A plain name still found in the table (old app, or an
  /// account without encrypted data) is adopted into the vault and cleared
  /// from the table only after a confirmed encrypted save that includes it.
  Future<List<UserProfile>> _withNames(
    String code,
    List<UserProfile> rows,
  ) async {
    final vault = await _sync.recoveryKey() != null;
    var events = await _service.nameEvents();
    final saved = await _sync.lastSavedSnapshot();
    final out = <UserProfile>[];
    var pending = false;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final event = events[row.id] is Map
          ? Map<String, dynamic>.from(events[row.id] as Map)
          : null;
      final encrypted = event?['deleted'] == true
          ? null
          : event?['name'] as String?;
      if (vault && row.name.isNotEmpty) {
        var cleared = false;
        if (encrypted != row.name) {
          await _service.recordName(row.id, name: row.name);
          events = await _service.nameEvents();
        } else {
          final at = DateTime.tryParse(event?['watched']?.toString() ?? '');
          if (saved != null && at != null && saved.isAfter(at)) {
            try {
              await _service.clearTableName(id: row.id, syncCode: code);
              cleared = true;
            } catch (_) {
              /* Retried at the next load; the name is safe in the vault. */
            }
          }
        }
        if (!cleared) pending = true;
      }
      final shown = row.name.isNotEmpty
          ? row.name
          : (encrypted != null && encrypted.isNotEmpty)
          ? encrypted
          : 'Profilo ${i + 1}';
      out.add(shown == row.name ? row : row.copyWith(name: shown));
    }
    _namesPending = pending;
    return out;
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
    final vault = await _sync.recoveryKey() != null;
    final created = await _service.createProfile(
      syncCode: code,
      // With encrypted data the name never reaches the table.
      name: vault ? '' : name,
      avatarKey: avatarKey,
      avatarColor: avatarColor,
      isKids: isKids,
    );
    await _service.recordName(created.id, name: name);
    final profile = created.copyWith(name: name);
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
    final vault = await _sync.recoveryKey() != null;
    if (name != null) await _service.recordName(profile.id, name: name);
    await _service.updateProfile(
      id: profile.id,
      syncCode: code,
      name: name == null ? null : (vault ? '' : name),
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
      await _service.recordName(profile.id, deleted: true);
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
