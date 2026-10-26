import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'xtream_service.dart';
import 'stream_slot_policy.dart';

/// User choices for subscription-expiry reminders (synced with the cloud as a
/// regular setting under [ExpiryReminderService.settingsKey]).
@immutable
class ExpiryReminderSettings {
  static const allThresholds = [30, 14, 7, 3, 1];
  final bool enabled;
  final Set<int> thresholds;
  final int hour;

  const ExpiryReminderSettings({
    this.enabled = true,
    this.thresholds = const {7, 3, 1},
    this.hour = 10,
  });

  ExpiryReminderSettings copyWith({bool? enabled, Set<int>? thresholds, int? hour}) =>
      ExpiryReminderSettings(
        enabled: enabled ?? this.enabled,
        thresholds: thresholds ?? this.thresholds,
        hour: hour ?? this.hour,
      );

  Map<String, dynamic> toJson() =>
      {'enabled': enabled, 'days': (thresholds.toList()..sort()), 'hour': hour};

  factory ExpiryReminderSettings.fromJson(Map<String, dynamic> j) {
    final days = (j['days'] as List?)
        ?.map((e) => (e as num).toInt())
        .where(allThresholds.contains)
        .toSet();
    return ExpiryReminderSettings(
      enabled: j['enabled'] as bool? ?? true,
      thresholds: days ?? const {7, 3, 1},
      hour: ((j['hour'] as num?)?.toInt() ?? 10).clamp(0, 23),
    );
  }
}

/// Pure scheduling logic, kept separate so it can be unit tested.
class ExpiryPlan {
  /// Reminder instants still in the future, keyed by threshold (days).
  static Map<int, DateTime> schedule(
    DateTime expiry,
    ExpiryReminderSettings s,
    DateTime now,
  ) {
    if (!s.enabled) return const {};
    final out = <int, DateTime>{};
    for (final d in s.thresholds) {
      final day = DateTime(expiry.year, expiry.month, expiry.day)
          .subtract(Duration(days: d));
      var when = DateTime(day.year, day.month, day.day, s.hour);
      if (when.isAfter(expiry)) when = expiry.subtract(const Duration(hours: 1));
      if (when.isAfter(now)) out[d] = when;
    }
    return out;
  }

  /// Smallest selected threshold the expiry has already entered, or null.
  static int? activeThreshold(
    DateTime expiry,
    ExpiryReminderSettings s,
    DateTime now,
  ) {
    if (!s.enabled || s.thresholds.isEmpty) return null;
    final left = expiry.difference(now);
    if (left.isNegative) return 0;
    final days = (left.inHours / 24).ceil();
    final hit = s.thresholds.where((t) => days <= t).toList()..sort();
    return hit.isEmpty ? null : hit.first;
  }

  /// Parses Xtream `user_info.exp_date` (unix seconds); null when unlimited.
  static DateTime? parseExpiry(Object? raw) {
    final n = int.tryParse('${raw ?? ''}'.trim());
    if (n == null || n <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(n * 1000);
  }
}

/// Local reminders before the Xtream subscription expires: system
/// notifications (also with the app closed) plus an in-app banner, which is
/// the reliable channel on Google TV where notifications are often hidden.
class ExpiryReminderService extends ChangeNotifier {
  ExpiryReminderService._();
  static final instance = ExpiryReminderService._();

  static const settingsKey = 'expiry_reminders_v1';
  static const _stateKey = 'expiry_reminder_state_v1';
  static const _baseId = 7100;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _pluginReady = false;
  ExpiryReminderSettings _settings = const ExpiryReminderSettings();
  DateTime? _expiry;
  bool _knownUnlimited = false;
  DateTime? _lastCheck;
  String _account = '';
  final Set<String> _dismissed = {};
  bool _checking = false;

  ExpiryReminderSettings get settings => _settings;
  DateTime? get expiry => _expiry;

  /// True when the provider answered but gave no expiry date (unlimited).
  bool get providerHasNoDate => _knownUnlimited;

  int? get activeThreshold => _expiry == null
      ? null
      : ExpiryPlan.activeThreshold(_expiry!, _settings, DateTime.now());

  bool get showBanner {
    final t = activeThreshold;
    return t != null && !_dismissed.contains(_bannerKey(t));
  }

  String _bannerKey(int t) =>
      '${_account.hashCode}:${_expiry?.millisecondsSinceEpoch}:$t';

  Future<void> load() async {
    await StreamSlotPolicy.instance.load();
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(settingsKey);
      _settings = raw == null
          ? const ExpiryReminderSettings()
          : ExpiryReminderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
    try {
      final raw = prefs.getString(_stateKey);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _account = j['account'] as String? ?? '';
        _expiry = ExpiryPlan.parseExpiry(j['exp']);
        _knownUnlimited = j['unlimited'] as bool? ?? false;
        final last = j['last'] as int?;
        _lastCheck = last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
        _dismissed.addAll((j['dismissed'] as List? ?? const []).cast<String>());
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _stateKey,
      jsonEncode({
        'account': _account,
        'exp': _expiry == null ? null : _expiry!.millisecondsSinceEpoch ~/ 1000,
        'unlimited': _knownUnlimited,
        'last': _lastCheck?.millisecondsSinceEpoch,
        'dismissed': _dismissed.toList(),
      }),
    );
  }

  Future<void> updateSettings(ExpiryReminderSettings s) async {
    _settings = s;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(settingsKey, jsonEncode(s.toJson()));
    if (s.enabled) await _requestPermission();
    await _reschedule();
  }

  /// Called after settings are restored from the cloud.
  Future<void> reloadSettings() async {
    await load();
    await _reschedule();
  }

  void dismissBanner() {
    final t = activeThreshold;
    if (t == null) return;
    _dismissed.add(_bannerKey(t));
    notifyListeners();
    unawaited(_saveState());
  }

  /// Feeds an already-fetched `player_api.php` answer (account screen).
  Future<void> applyAccountInfo(String account, Map<String, dynamic> info) async {
    final user = info['user_info'];
    if (user is! Map) return;
    await StreamSlotPolicy.instance.remember(user['max_connections']);
    final exp = ExpiryPlan.parseExpiry(user['exp_date']);
    if (account != _account || exp != _expiry) {
      // Renewal or account change: stale "later" choices no longer apply.
      _dismissed.clear();
    }
    _account = account;
    _expiry = exp;
    _knownUnlimited = exp == null;
    _lastCheck = DateTime.now();
    notifyListeners();
    await _saveState();
    await _reschedule();
  }

  /// Refreshes the expiry from the provider at most every 12 hours unless
  /// [force]; never throws (no network ⇒ keeps the saved date).
  Future<void> check(Map<String, String>? credentials, {bool force = false}) async {
    if (credentials == null) {
      if (_expiry != null || _account.isNotEmpty) {
        _expiry = null;
        _account = '';
        _knownUnlimited = false;
        notifyListeners();
        await _saveState();
        await _cancelAll();
      }
      return;
    }
    final account = '${credentials['server']}|${credentials['username']}';
    final fresh = account == _account &&
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < const Duration(hours: 12);
    if ((fresh && !force) || _checking) {
      if (fresh) await _reschedule();
      return;
    }
    _checking = true;
    try {
      final info = await XtreamService().accountInfo(
        server: credentials['server']!,
        username: credentials['username']!,
        password: credentials['password']!,
      );
      await applyAccountInfo(account, info);
    } catch (_) {
      // Offline or provider error: keep the last known date.
    } finally {
      _checking = false;
    }
  }

  Future<bool> _ensurePlugin() async {
    if (_pluginReady) return true;
    if (kIsWeb) return false;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _pluginReady = true;
    } catch (e) {
      debugPrint('Notifiche non disponibili: $e');
    }
    return _pluginReady;
  }

  Future<void> _requestPermission() async {
    if (!await _ensurePlugin()) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
    } catch (_) {}
  }

  Future<void> _cancelAll() async {
    if (!await _ensurePlugin()) return;
    for (final d in ExpiryReminderSettings.allThresholds) {
      try {
        await _plugin.cancel(_baseId + d);
      } catch (_) {}
    }
  }

  Future<void> _reschedule() async {
    await _cancelAll();
    final exp = _expiry;
    if (exp == null || !_pluginReady) return;
    final plan = ExpiryPlan.schedule(exp, _settings, DateTime.now());
    if (plan.isEmpty) return;
    await _requestPermission();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'xtream_expiry',
        'Scadenza abbonamento',
        channelDescription: 'Promemoria prima della scadenza della playlist',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    for (final e in plan.entries) {
      final body = e.key == 1
          ? 'Il tuo abbonamento scade domani.'
          : 'Il tuo abbonamento scade tra ${e.key} giorni.';
      try {
        await _plugin.zonedSchedule(
          _baseId + e.key,
          'StellarTV · Abbonamento in scadenza',
          body,
          tz.TZDateTime.from(e.value.toUtc(), tz.UTC),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (err) {
        debugPrint('Promemoria non programmato: $err');
      }
    }
  }

  /// Startup entry: loads state, prepares notifications and checks the date.
  Future<void> start(Map<String, String>? credentials) async {
    await load();
    await _ensurePlugin();
    await check(credentials);
  }
}
