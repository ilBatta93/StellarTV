/// What a full device backup holds: everything the app keeps.
///
/// A backup carries every preference, every secure-storage entry and every
/// file of the app's support folder (catalog, guide, ratings, subtitles,
/// caches), so a restored device starts exactly where the old one was.
/// Staying out:
/// - downloads, both the videos and their list (the user's choice);
/// - the account session and the sync markers that belong to it: a copied
///   session would be shared by two devices and the next token refresh
///   would sign one or both out. The restored device gets a session of its
///   own instead, approved from the phone (TV pairing), and rebuilds the
///   sync markers against the cloud;
/// - the Trakt sign-in of each profile and its sync markers, for the same
///   reason: Trakt rotates the sign-in at every renewal;
/// - files caught mid-write. Files past the size limits are listed as
///   skipped, largest first.
class DeviceBackupPolicy {
  const DeviceBackupPolicy._();

  static const format = 'stellartv-backup';
  static const version = 1;

  /// Secure-storage configurations the app uses (see settings_service,
  /// personal_vault and vpn_service); each is saved and restored on its own.
  static const secureStores = ['settings', 'vault', 'vpn'];

  /// Raw bytes of one file and of all files together. Files are taken from
  /// the smallest, so the limits leave out only the largest ones instead of
  /// risking memory on 1 GB TVs.
  static const maxFileBytes = 32 * 1024 * 1024;
  static const maxTotalBytes = 96 * 1024 * 1024;

  /// Preferences tied to this device's sign-in or to its downloads. They
  /// are neither saved nor overwritten by a restore.
  static const _localPrefs = {
    'offline_downloads_v1',
    'stellar_guest_mode',
    'sync_code',
    'sync_last_pull',
    'sync_last_push',
    'sync_last_saved_snapshot',
  };

  /// True when [key] is saved in and restored from a backup.
  static bool keepsPref(String key) =>
      key.isNotEmpty &&
      !key.startsWith('sb-') &&
      !key.startsWith('supabase') &&
      !key.startsWith('trakt_') &&
      !_localPrefs.contains(key);

  /// True when the secure-storage entry [key] is saved in and restored from
  /// a backup: everything except the Trakt sign-ins. The user's own service
  /// keys are kept.
  static bool keepsSecret(String key) =>
      key.isNotEmpty && !key.startsWith('trakt_session');

  /// True when the support-folder file at [relativePath] ('/' separators)
  /// belongs in a backup: anything inside the folder except downloads and
  /// files caught mid-write.
  static bool keepsFile(String relativePath) {
    final p = relativePath.replaceAll('\\', '/');
    if (p.isEmpty || p.startsWith('/') || p.split('/').contains('..')) {
      return false;
    }
    return !p.startsWith('downloads/') &&
        !p.startsWith('.restore_staging/') &&
        !p.endsWith('.tmp') &&
        !p.endsWith('.restore');
  }

  /// Preference value as stored in the backup, or null for an unknown type.
  static List<Object>? encodePref(Object? value) => switch (value) {
    final String v => ['s', v],
    final bool v => ['b', v],
    final int v => ['i', v],
    final double v => ['d', v],
    final List<String> v => ['l', v],
    final List v when v.every((e) => e is String) => [
      'l',
      v.cast<String>().toList(),
    ],
    _ => null,
  };

  /// Preference value back from the backup, or null when malformed.
  static Object? decodePref(Object? raw) {
    if (raw is! List || raw.length != 2) return null;
    final v = raw[1];
    return switch (raw[0]) {
      's' when v is String => v,
      'b' when v is bool => v,
      'i' when v is int => v,
      'd' when v is num => v.toDouble(),
      'l' when v is List && v.every((e) => e is String) =>
        v.cast<String>().toList(),
      _ => null,
    };
  }
}

/// Readable facts about a backup, shown before restoring it.
class DeviceBackupSummary {
  const DeviceBackupSummary({
    required this.created,
    required this.appVersion,
    required this.platform,
    required this.tv,
    required this.account,
    required this.prefs,
    required this.secrets,
    required this.files,
    required this.bytes,
    required this.skipped,
  });

  final DateTime? created;
  final String appVersion, platform;
  final bool tv;
  final String? account;
  final int prefs, secrets, files, bytes;
  final List<String> skipped;

  Map<String, Object?> toJson() => {
    'created': created?.toUtc().toIso8601String(),
    'app': appVersion,
    'platform': platform,
    'tv': tv,
    'account': account,
    'prefs': prefs,
    'secrets': secrets,
    'files': files,
    'bytes': bytes,
    'skipped': skipped,
  };

  /// Reads the manifest header; null when it is not a StellarTV backup this
  /// version understands.
  static DeviceBackupSummary? fromManifest(Object? raw) {
    if (raw is! Map ||
        raw['format'] != DeviceBackupPolicy.format ||
        raw['version'] is! int ||
        (raw['version'] as int) > DeviceBackupPolicy.version) {
      return null;
    }
    final s = raw['summary'];
    if (s is! Map) return null;
    int n(String k) => s[k] is int ? s[k] as int : 0;
    final created = s['created'];
    return DeviceBackupSummary(
      created: created is String ? DateTime.tryParse(created) : null,
      appVersion: s['app'] is String ? s['app'] as String : '',
      platform: s['platform'] is String ? s['platform'] as String : '',
      tv: s['tv'] == true,
      account: s['account'] is String ? s['account'] as String : null,
      prefs: n('prefs'),
      secrets: n('secrets'),
      files: n('files'),
      bytes: n('bytes'),
      skipped: s['skipped'] is List
          ? [
              for (final e in s['skipped'] as List)
                if (e is String) e,
            ]
          : const [],
    );
  }
}
