import 'package:flutter/material.dart';
import '../widgets/apple_page_scaffold.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/expiry_reminder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_tiles.dart';

/// Settings for the local reminders before the Xtream subscription expires.
class ExpiryReminderScreen extends StatelessWidget {
  const ExpiryReminderScreen({super.key});

  static String _date(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final svc = ExpiryReminderService.instance;
    return ApplePageScaffold(
      title: 'Promemoria scadenza',
      body: ListenableBuilder(
        listenable: svc,
        builder: (context, _) {
          final s = svc.settings;
          final exp = svc.expiry;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SettingsSection(
                title: 'Abbonamento',
                children: [
                  SettingsValueTile(
                    icon: Icons.event_outlined,
                    title: 'Scadenza',
                    value: exp != null
                        ? _date(exp)
                        : svc.providerHasNoDate
                        ? 'Data non fornita dal provider'
                        : 'Non ancora verificata',
                  ),
                  SettingsValueTile(
                    icon: Icons.refresh_rounded,
                    title: 'Verifica ora',
                    subtitle: 'Chiede di nuovo la data al provider',
                    onTap: () => svc.check(
                      context.read<AppProvider>().xtreamCredentials,
                      force: true,
                    ),
                  ),
                ],
              ),
              SettingsSection(
                title: 'Promemoria',
                description:
                    'Notifica sul dispositivo e avviso nella Home prima della scadenza.',
                children: [
                  SettingsSwitchTile(
                    icon: Icons.notifications_active_outlined,
                    title: 'Promemoria attivi',
                    value: s.enabled,
                    onChanged: (v) =>
                        svc.updateSettings(s.copyWith(enabled: v)),
                  ),
                  for (final d in ExpiryReminderSettings.allThresholds)
                    SettingsSwitchTile(
                      icon: Icons.schedule_rounded,
                      title: d == 1 ? '1 giorno prima' : '$d giorni prima',
                      value: s.thresholds.contains(d),
                      onChanged: (v) => svc.updateSettings(
                        s.copyWith(
                          thresholds: {...s.thresholds}
                            ..remove(d)
                            ..addAll(v ? [d] : []),
                        ),
                      ),
                    ),
                  SettingsValueTile(
                    icon: Icons.alarm_rounded,
                    title: 'Orario notifica',
                    value: '${s.hour.toString().padLeft(2, '0')}:00',
                    subtitle: 'Premi per cambiare',
                    onTap: () =>
                        svc.updateSettings(s.copyWith(hour: (s.hour + 1) % 24)),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  'Ogni promemoria arriva una sola volta. Se rinnovi, le date si aggiornano da sole.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
