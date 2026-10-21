import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_update_service.dart';
import 'image_cache_service.dart';

/// What the post-update safety net must do on this launch.
enum MigrationAction { firstRun, none, upgrade, downgrade }

/// Pure decision, kept separate so tests pin the rules exactly.
MigrationAction migrationAction(int? storedBuild, int currentBuild) {
  if (storedBuild == null) return MigrationAction.firstRun;
  if (currentBuild > storedBuild) return MigrationAction.upgrade;
  if (currentBuild < storedBuild) return MigrationAction.downgrade;
  return MigrationAction.none;
}

/// Post-update safety net. Runs once per installed build, before any service
/// starts, and may only clear data the app can rebuild by itself. It never
/// touches credentials, history, favorites, profiles, settings or the vault,
/// and a failure here must never block startup.
class AppMigrationService {
  AppMigrationService._();

  static const _markerKey = 'app_last_run_build';

  /// Local preference keys retired from the app and safe to drop on upgrade.
  /// Never list credentials, history, favorites, profiles or settings here.
  static const _retiredKeys = <String>[];

  static Future<void> run() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_markerKey);
      final current = AppUpdateService.currentBuild;
      final action = migrationAction(stored, current);
      if (action == MigrationAction.upgrade) {
        await _clearDerivedCaches();
        for (final key in _retiredKeys) {
          await prefs.remove(key);
        }
      }
      await prefs.setInt(_markerKey, current);
    } catch (e) {
      // Cleanup is best-effort: the app must open even if it fails. The
      // marker stays unset on error so the next launch retries.
      debugPrint('AppMigrationService: $e');
    }
  }

  /// Posters and backdrops are re-downloaded on demand; entries written by an
  /// older version can only waste space or show outdated artwork.
  static Future<void> _clearDerivedCaches() async {
    try {
      await AppImageCache.manager.emptyCache();
    } catch (e) {
      debugPrint('AppMigrationService image cache: $e');
    }
    try {
      await DefaultCacheManager().emptyCache();
    } catch (e) {
      debugPrint('AppMigrationService default cache: $e');
    }
  }
}
