import 'package:flutter/material.dart';

import '../widgets/apple_page_scaffold.dart';

import '../models/player_settings.dart';
import '../services/native_player_bridge.dart';
import '../services/device_type_service.dart';
import '../services/player_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/player/player_format.dart';
import '../widgets/player/video_surface.dart';
import '../widgets/settings_tiles.dart';
import '../widgets/tv_focusable.dart';

class PlayerSettingsScreen extends StatefulWidget {
  const PlayerSettingsScreen({super.key, this.scope});
  final PlayerSettingsScope? scope;

  @override
  State<PlayerSettingsScreen> createState() => _PlayerSettingsScreenState();
}

class _PlayerSettingsScreenState extends State<PlayerSettingsScreen> {
  final _service = PlayerSettingsService();
  PlayerSettings? _s;
  DeviceMediaCapabilities? _caps;

  @override
  void initState() {
    super.initState();
    _load();
  }

  PlayerSettingsScope get _scope => DeviceTypeService.isTv
      ? widget.scope ?? PlayerSettingsScope.shared
      : PlayerSettingsScope.shared;
  bool _mpv(PlayerSettings s) => s.primaryEngine == PlayerEngineType.mediakit;
  bool _mpvOrMdk(PlayerSettings s) => _mpv(s);

  bool get _live => _scope == PlayerSettingsScope.liveTv;
  bool get _tvProfile => DeviceTypeService.isTv && widget.scope != null;

  Future<void> _load() async {
    if (DeviceTypeService.isTv && widget.scope == null) return;
    final settings = await _service.load(scope: _scope);
    final caps = await NativePlayerBridge.instance.getCapabilities();
    if (!mounted) return;
    setState(() {
      _s = settings;
      _caps = caps;
    });
  }

  void _update(void Function(PlayerSettings s) change) {
    final s = _s;
    if (s == null) return;
    setState(() => change(s));
    _service.save(s, scope: _scope);
  }

  Future<void> _pick<T>(
    String title,
    List<T> options,
    T current,
    String Function(T) label,
    void Function(PlayerSettings, T) apply, {
    String? Function(T)? detail,
  }) async {
    final picked = await pickOption<T>(
      context,
      title: title,
      options: options,
      current: current,
      label: label,
      detail: detail,
    );
    if (picked != null) _update((s) => apply(s, picked));
  }

  String _mb(double bytes) => '${(bytes / (1024 * 1024)).round()} MB';

  Widget _cacheSlider(PlayerSettings s, {required bool live}) {
    final tv = DeviceTypeService.isTv;
    final min = PlayerSettings.cacheFloor(live: live, tv: tv).toDouble();
    final max = PlayerSettings.cacheCap(live: live, tv: tv).toDouble();
    final stored = live ? s.liveCachingMs : s.networkCachingMs;
    final value = PlayerSettings.migrateCacheBytes(
      stored,
      live: live,
      tv: tv,
    ).toDouble();
    return SettingsSliderTile(
      icon: live ? Icons.live_tv_rounded : Icons.cloud_download_outlined,
      title: live ? 'Buffer dirette' : 'Buffer video',
      subtitle: 'Minimo ${_mb(min)}. Sopra questo valore cambia la cache reale',
      badge: 'mpv',
      value: value,
      min: min,
      max: max,
      divisions: ((max - min) / PlayerSettings.cacheStepBytes).round(),
      format: _mb,
      onChanged: (v) => _update((s) {
        final bytes = PlayerSettings.alignCacheBytes(
          v.round(),
          live: live,
          tv: tv,
        );
        if (live) {
          s.liveCachingMs = bytes;
        } else {
          s.networkCachingMs = bytes;
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (DeviceTypeService.isTv && widget.scope == null) {
      return const _PlayerProfilesHub();
    }
    return ApplePageScaffold(
      title: _tvProfile
          ? (_live ? 'Dirette TV' : 'Video e raccolte')
          : 'Player video',
      body: s == null
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                ..._engineSection(s),
                ..._playbackSection(s),
                ..._audioSection(s),
                ..._subtitleSection(s),
                if (_mpvOrMdk(s)) ..._videoSection(s),
                ..._networkSection(s),
                ..._systemSection(s),
                _capabilitiesSection(),
                _resetSection(),
              ],
            ),
    );
  }

  List<Widget> _engineSection(PlayerSettings s) => [
    SettingsSection(
      title: 'Motore di riproduzione',
      description:
          'Se il motore principale non riesce ad aprire un canale, l\'app prova '
          'prima gli altri formati del canale e poi il motore di riserva. '
          'Anteprima e MultiView partono con ExoPlayer e passano a mpv se serve. '
          'Le opzioni qui sotto cambiano in base al motore scelto.',
      children: [
        SettingsValueTile(
          icon: Icons.memory_rounded,
          title: 'Motore predefinito',
          value: s.primaryEngine.label,
          onTap: () => _pick(
            'Motore predefinito',
            PlayerEngineType.values,
            s.primaryEngine,
            (e) => e.label,
            (s, v) => s.primaryEngine = v,
            detail: (e) => e.description,
          ),
        ),
        _EngineFeatures(engine: s.primaryEngine),
        if (!_tvProfile || _live)
          SettingsValueTile(
            icon: Icons.stream_rounded,
            title: 'Formato flusso dirette',
            subtitle: 'Per i contenuti in diretta',
            value: s.liveStreamFormat.label,
            onTap: () => _pick(
              'Formato flusso dirette',
              LiveStreamFormat.values,
              s.liveStreamFormat,
              (f) => f.label,
              (s, v) => s.liveStreamFormat = v,
              detail: (f) => f.description,
            ),
          ),
        SettingsSwitchTile(
          icon: Icons.swap_horiz_rounded,
          title: 'Cambio automatico del motore',
          subtitle:
              'Prova ${s.primaryEngine.other.label} se ${s.primaryEngine.label} fallisce',
          value: s.autoFallback,
          onChanged: (v) => _update((s) => s.autoFallback = v),
        ),
        SettingsSliderTile(
          icon: Icons.timer_outlined,
          title: 'Attesa massima all\'avvio',
          subtitle: 'Dopo questo tempo senza immagine si considera il tentativo fallito',
          value: s.startTimeoutSeconds.toDouble(),
          min: 5,
          max: 30,
          divisions: 25,
          format: (v) => '${v.round()} s',
          onChanged: (v) => _update((s) => s.startTimeoutSeconds = v.round()),
        ),
      ],
    ),
  ];

  List<Widget> _playbackSection(PlayerSettings s) => [
    SettingsSection(
      title: 'Riproduzione',
      children: [
        if (!_live)
          SettingsSwitchTile(
            icon: Icons.skip_next_rounded,
            title: 'Passa automaticamente al prossimo episodio',
            subtitle: 'Disattiva per scegliere manualmente quando proseguire. Si sincronizza con le preferenze comuni.',
            value: s.autoNextEpisode,
            onChanged: (v) {
              _update((s) => s.autoNextEpisode = v);
              _service.setAutoNextEpisode(v);
            },
          ),
        if (!_tvProfile || !_live)
          SettingsValueTile(
            icon: Icons.speed_rounded,
            title: 'Velocità predefinita',
            subtitle: 'Per i video; le dirette restano a velocità normale',
            value: formatSpeed(s.defaultSpeed),
            onTap: () => _pick(
              'Velocità predefinita',
              kPlaybackSpeeds,
              s.defaultSpeed,
              formatSpeed,
              (s, v) => s.defaultSpeed = v,
            ),
          ),
        SettingsValueTile(
          icon: Icons.aspect_ratio_rounded,
          title: 'Formato immagine',
          value: s.fitMode.label,
          onTap: () => _pick(
            'Formato immagine',
            VideoFitMode.values,
            s.fitMode,
            (m) => m.label,
            (s, v) => s.fitMode = v,
          ),
        ),
        if (!_tvProfile)
          SettingsValueTile(
            icon: Icons.screen_rotation_rounded,
            title: 'Orientamento',
            value: s.orientation.label,
            onTap: () => _pick(
              'Orientamento',
              PlayerOrientation.values,
              s.orientation,
              (o) => o.label,
              (s, v) => s.orientation = v,
            ),
          ),
        if (!_tvProfile || !_live)
          SettingsSwitchTile(
            icon: Icons.history_rounded,
            title: 'Riprendi da dove avevi lasciato',
            subtitle: 'Per i contenuti registrati',
            value: s.resumePlayback,
            onChanged: (v) => _update((s) => s.resumePlayback = v),
          ),
        SettingsValueTile(
          icon: Icons.fast_forward_rounded,
          title: 'Salto avanti / indietro',
          value: '${s.seekStepSeconds} s',
          onTap: () => _pick(
            'Salto avanti / indietro',
            const [5, 10, 15, 30, 60],
            s.seekStepSeconds,
            (v) => '$v secondi',
            (s, v) => s.seekStepSeconds = v,
          ),
        ),
        SettingsValueTile(
          icon: Icons.visibility_off_outlined,
          title: 'Nascondi comandi dopo',
          value: s.controlsHideSeconds == 0
              ? 'Mai'
              : '${s.controlsHideSeconds} s',
          onTap: () => _pick(
            'Nascondi comandi dopo',
            const [2, 3, 4, 6, 8, 0],
            s.controlsHideSeconds,
            (v) => v == 0 ? 'Mai' : '$v secondi',
            (s, v) => s.controlsHideSeconds = v,
          ),
        ),
        if (!_tvProfile)
          SettingsSwitchTile(
            icon: Icons.swipe_rounded,
            title: 'Gesti a schermo',
            subtitle: 'Scorri a sinistra per la luminosità, a destra per il volume, in orizzontale per avanzare',
            value: s.gesturesEnabled,
            onChanged: (v) => _update((s) => s.gesturesEnabled = v),
          ),
        if (!_tvProfile)
          SettingsSwitchTile(
            icon: Icons.touch_app_outlined,
            title: 'Doppio tocco per saltare',
            subtitle:
                'Ai lati per andare avanti o indietro, al centro per pausa',
            value: s.doubleTapSeek,
            onChanged: (v) => _update((s) => s.doubleTapSeek = v),
          ),
      ],
    ),
  ];

  List<Widget> _audioSection(PlayerSettings s) => [
    SettingsSection(
      title: 'Audio',
      children: [
        SettingsValueTile(
          icon: Icons.record_voice_over_outlined,
          title: 'Lingua audio preferita',
          value: kLanguageOptions[s.preferredAudioLanguage],
          onTap: () => _pick(
            'Lingua audio preferita',
            kLanguageOptions.keys.toList(),
            s.preferredAudioLanguage,
            (c) => kLanguageOptions[c]!,
            (s, v) => s.preferredAudioLanguage = v,
          ),
        ),
        if (s.primaryEngine.supportsAudioPassthrough)
          SettingsSwitchTile(
            icon: Icons.surround_sound_outlined,
            title: 'Passthrough Dolby / DTS',
            subtitle: 'Invia l\'audio originale a soundbar o ricevitore compatibili tramite HDMI',
            badge: 'mpv',
            value: s.audioPassthrough,
            onChanged: (v) => _update((s) => s.audioPassthrough = v),
          ),
        if (s.primaryEngine.supportsAudioTimeStretch)
          SettingsSwitchTile(
            icon: Icons.graphic_eq_rounded,
            title: 'Mantieni il tono a velocità diverse',
            subtitle: 'Evita voci troppo acute o gravi quando cambi velocità',
            badge: 'mpv',
            value: s.audioTimeStretch,
            onChanged: (v) => _update((s) => s.audioTimeStretch = v),
          ),
        if (s.primaryEngine.supportsDelays)
          SettingsSliderTile(
            icon: Icons.sync_rounded,
            title: 'Ritardo audio predefinito',
            badge: 'mpv',
            value: s.audioDelayMs.toDouble(),
            min: -2000,
            max: 2000,
            divisions: 80,
            format: (v) => formatDelay(Duration(milliseconds: v.round())),
            onChanged: (v) => _update((s) => s.audioDelayMs = v.round()),
          ),
      ],
    ),
  ];

  List<Widget> _subtitleSection(PlayerSettings s) => [
    SettingsSection(
      title: 'Sottotitoli',
      description: 'I sottotitoli incorporati vengono mostrati con mpv.',
      children: [
        _SubtitlePreview(settings: s),
        if (_mpvOrMdk(s))
          SettingsSwitchTile(
            icon: Icons.subtitles_outlined,
            badge: 'mpv',
            title: 'Attiva automaticamente',
            subtitle: 'Seleziona i sottotitoli nella lingua preferita quando disponibili',
            value: s.subtitlesEnabled,
            onChanged: (v) => _update((s) => s.subtitlesEnabled = v),
          ),
        SettingsValueTile(
          icon: Icons.translate_rounded,
          title: 'Lingua sottotitoli',
          value: kLanguageOptions[s.preferredSubtitleLanguage],
          onTap: () => _pick(
            'Lingua sottotitoli',
            kLanguageOptions.keys.toList(),
            s.preferredSubtitleLanguage,
            (c) => kLanguageOptions[c]!,
            (s, v) => s.preferredSubtitleLanguage = v,
          ),
        ),
        SettingsValueTile(
          icon: Icons.format_size_rounded,
          title: 'Dimensione testo',
          value: s.subtitleSize.label,
          onTap: () => _pick(
            'Dimensione testo',
            SubtitleSize.values,
            s.subtitleSize,
            (v) => v.label,
            (s, v) => s.subtitleSize = v,
          ),
        ),
        SettingsValueTile(
          icon: Icons.format_color_text_rounded,
          title: 'Colore testo',
          value: s.subtitleColor.label,
          onTap: () => _pick(
            'Colore testo',
            SubtitleColor.values,
            s.subtitleColor,
            (v) => v.label,
            (s, v) => s.subtitleColor = v,
          ),
        ),
        SettingsSwitchTile(
          icon: Icons.rectangle_outlined,
          title: 'Sfondo scuro',
          value: s.subtitleBackground,
          onChanged: (v) => _update((s) => s.subtitleBackground = v),
        ),
        SettingsSwitchTile(
          icon: Icons.format_bold_rounded,
          title: 'Grassetto',
          value: s.subtitleBold,
          onChanged: (v) => _update((s) => s.subtitleBold = v),
        ),
        if (s.primaryEngine.supportsDelays)
          SettingsSliderTile(
            icon: Icons.av_timer_rounded,
            title: 'Ritardo sottotitoli predefinito',
            badge: 'mpv',
            value: s.subtitleDelayMs.toDouble(),
            min: -5000,
            max: 5000,
            divisions: 100,
            format: (v) => formatDelay(Duration(milliseconds: v.round())),
            onChanged: (v) => _update((s) => s.subtitleDelayMs = v.round()),
          ),
      ],
    ),
  ];

  List<Widget> _videoSection(PlayerSettings s) => [
    SettingsSection(
      title: 'Video e decodifica',
      description: 'HDR10, HLG e Dolby Vision vengono riprodotti tramite la decodifica hardware del dispositivo, se lo schermo li supporta.',
      children: [
        if (_mpvOrMdk(s))
          SettingsValueTile(
            icon: Icons.developer_board_rounded,
            title: 'Decodifica hardware',
            badge: 'mpv',
            value: s.hardwareDecoding.label,
            onTap: () => _pick(
              'Decodifica hardware',
              HardwareDecoding.values,
              s.hardwareDecoding,
              (v) => v.label,
              (s, v) => s.hardwareDecoding = v,
              detail: (v) => switch (v) {
                HardwareDecoding.auto =>
                  'Consigliata: sceglie il metodo migliore',
                HardwareDecoding.full => 'Massime prestazioni e supporto HDR',
                HardwareDecoding.decoding => 'Compatibile con più dispositivi',
                HardwareDecoding.disabled =>
                  'Usa il processore: più lento, risolve artefatti',
              },
            ),
          ),
        if (s.primaryEngine.supportsDropLateFrames && !_live)
          SettingsSwitchTile(
            icon: Icons.slow_motion_video_rounded,
            title: 'Scarta fotogrammi in ritardo',
            subtitle: 'Solo con decodifica software di un film: tiene audio e video in sincrono',
            badge: 'mpv',
            value: s.dropLateFrames,
            onChanged: (v) => _update((s) => s.dropLateFrames = v),
          ),
        if (s.primaryEngine.supportsSkipFrames)
          SettingsSwitchTile(
            icon: Icons.skip_next_outlined,
            title: 'Salta fotogrammi',
            subtitle: 'Riduce gli scatti con flussi pesanti (4K, HEVC)',
            badge: 'mpv',
            value: s.skipFrames,
            onChanged: (v) => _update((s) => s.skipFrames = v),
          ),
      ],
    ),
  ];

  List<Widget> _networkSection(PlayerSettings s) => [
    SettingsSection(
      title: 'Rete e buffer',
      description: 'Valori più alti riducono le interruzioni su connessioni instabili ma aumentano il tempo di avvio.',
      children: [
        if (s.primaryEngine.supportsCacheBuffer && (!_tvProfile || !_live))
          _cacheSlider(s, live: false),
        if (s.primaryEngine.supportsCacheBuffer && (!_tvProfile || _live))
          _cacheSlider(s, live: true),
        if (s.primaryEngine.supportsBackBuffer)
          SettingsSliderTile(
            icon: Icons.replay_circle_filled_outlined,
            title: 'Buffer all\'indietro',
            subtitle: 'Secondi già visti tenuti in memoria per tornare indietro subito',
            badge: 'ExoPlayer',
            value: s.backBufferSeconds.toDouble(),
            min: 0,
            max: 120,
            divisions: 24,
            format: (v) => '${v.round()} s',
            onChanged: (v) => _update((s) => s.backBufferSeconds = v.round()),
          ),
        if (s.primaryEngine.supportsReconnect)
          SettingsSwitchTile(
            icon: Icons.wifi_protected_setup_rounded,
            title: 'Riconnessione automatica',
            subtitle: 'Riprova da solo se il flusso si interrompe',
            badge: 'mpv',
            value: s.httpReconnect,
            onChanged: (v) => _update((s) => s.httpReconnect = v),
          ),
        SettingsValueTile(
          icon: Icons.badge_outlined,
          title: 'User agent personalizzato',
          subtitle: 'Alcuni servizi richiedono un identificativo specifico',
          value:
              effectiveStreamUserAgent(s.userAgent) == kDefaultStreamUserAgent
              ? 'Predefinito (VLC)'
              : s.userAgent,
          onTap: _editUserAgent,
        ),
      ],
    ),
  ];

  List<Widget> _systemSection(PlayerSettings s) => [
    SettingsSection(
      title: 'Sistema',
      children: [
        SettingsSwitchTile(
          icon: Icons.picture_in_picture_alt_rounded,
          title: 'Picture-in-Picture automatico',
          subtitle: 'Continua a guardare in una finestra quando esci dall\'app (Android)',
          value: s.autoPip,
          onChanged: (v) => _update((s) => s.autoPip = v),
        ),
        SettingsSwitchTile(
          icon: Icons.light_mode_outlined,
          title: 'Schermo sempre acceso',
          value: s.keepScreenOn,
          onChanged: (v) => _update((s) => s.keepScreenOn = v),
        ),
        SettingsSwitchTile(
          icon: Icons.headphones_rounded,
          title: 'Audio in background',
          subtitle: 'Non mette in pausa quando esci dall\'app. Android potrebbe comunque interrompere l\'audio dopo un po\'',
          value: s.backgroundAudio,
          onChanged: (v) => _update((s) => s.backgroundAudio = v),
        ),
        SettingsSwitchTile(
          icon: Icons.analytics_outlined,
          title: 'Statistiche per nerd',
          subtitle: 'Mostra risoluzione, buffer e motore durante la visione',
          value: s.showStats,
          onChanged: (v) => _update((s) => s.showStats = v),
        ),
      ],
    ),
  ];

  Widget _capabilitiesSection() {
    final caps = _caps ?? DeviceMediaCapabilities.unknown;
    final known = caps.decoders.isNotEmpty;
    return SettingsSection(
      title: 'Compatibilità del dispositivo',
      description: known
          ? 'Formati che questo dispositivo può decodificare in hardware.'
          : 'Informazioni disponibili solo su Android.',
      children: [
        if (known) ...[
          SettingsValueTile(
            icon: Icons.hdr_on_rounded,
            title: 'HDR dello schermo',
            value: caps.hdrFormats.isEmpty
                ? 'Non supportato'
                : caps.hdrFormats.join(', '),
          ),
          for (final e in caps.decoders.entries)
            TvFocusable(
              onPressed: () {},
              focusedScale: 1,
              child: ListTile(
                dense: true,
                leading: Icon(
                  e.value
                      ? Icons.check_circle_rounded
                      : Icons.remove_circle_outline_rounded,
                  color: e.value ? AppColors.success : AppColors.textMuted,
                  size: 20,
                ),
                title: Text(e.key, style: const TextStyle(fontSize: 14)),
                trailing: Text(
                  e.value ? 'Supportato' : 'Via software / no',
                  style: TextStyle(
                    color: e.value ? AppColors.success : AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ] else
          const SettingsValueTile(
            icon: Icons.info_outline_rounded,
            title: 'Nessun dato disponibile',
          ),
      ],
    );
  }

  Widget _resetSection() => SettingsSection(
    title: 'Ripristino',
    children: [
      SettingsValueTile(
        icon: Icons.bookmark_remove_outlined,
        title: 'Cancella posizioni salvate',
        onTap: () async {
          await _service.clearResumePositions();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Posizioni di visione cancellate'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
      SettingsValueTile(
        icon: Icons.restart_alt_rounded,
        title: 'Ripristina impostazioni predefinite',
        color: AppColors.error,
        onTap: _confirmReset,
      ),
    ],
  );

  Future<void> _editUserAgent() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _UserAgentDialog(initial: _s?.userAgent ?? ''),
    );
    if (result != null) _update((s) => s.userAgent = result);
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Ripristinare le impostazioni?'),
        content: Text(
          _tvProfile
              ? 'Le impostazioni di questa categoria torneranno ai valori iniziali.'
              : 'Tutte le impostazioni del player torneranno ai valori iniziali.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Ripristina',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.reset(scope: _scope);
    await _load();
  }
}

class _SubtitlePreview extends StatelessWidget {
  final PlayerSettings settings;
  const _SubtitlePreview({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF0F2027)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 16),
      child: SubtitleCaption(
        text: 'Anteprima dei sottotitoli',
        settings: settings,
      ),
    );
  }
}

class _UserAgentDialog extends StatefulWidget {
  const _UserAgentDialog({required this.initial});

  final String initial;

  @override
  State<_UserAgentDialog> createState() => _UserAgentDialogState();
}

class _UserAgentDialogState extends State<_UserAgentDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('User agent'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, value) in const [
            ('Predefinito (VLC)', ''),
            ('Android (okhttp)', 'okhttp/4.12.0'),
            ('Compatibilità estesa', 'IPTVSmartersPro'),
          ])
            TextButton(
              autofocus: value.isEmpty,
              onPressed: () => Navigator.pop(context, value),
              child: Text(label),
            ),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: 'Oppure scrivine uno personalizzato',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Salva'),
        ),
      ],
    );
  }
}

/// What the selected engine can do, so the settings below make sense.
class _EngineFeatures extends StatelessWidget {
  const _EngineFeatures({required this.engine});
  final PlayerEngineType engine;

  @override
  Widget build(BuildContext context) {
    final items = <(String, bool)>[
      ('Tracce audio', true),
      ('Sottotitoli incorporati', engine.supportsSubtitles),
      ('Scelta qualità', engine.supportsQuality),
      ('Ritardo audio e sottotitoli', engine.supportsDelays),
      (
        'Pausa e riavvolgimento diretta',
        engine.supportsTimeshift && !DeviceTypeService.isTv,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (label, ok) in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: ok
                    ? AppColors.primary.withValues(alpha: 0.14)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: ok
                      ? AppColors.primary.withValues(alpha: 0.5)
                      : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    ok ? Icons.check_rounded : Icons.remove_rounded,
                    size: 14,
                    color: ok ? AppColors.primary : AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: ok ? AppColors.textPrimary : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// TV entry page of "Player video": two large tvOS-style cards, one per
/// profile, each showing the engine and the main choices at a glance.
class _PlayerProfilesHub extends StatefulWidget {
  const _PlayerProfilesHub();

  @override
  State<_PlayerProfilesHub> createState() => _PlayerProfilesHubState();
}

class _PlayerProfilesHubState extends State<_PlayerProfilesHub> {
  final _service = PlayerSettingsService();
  PlayerSettings? _live;
  PlayerSettings? _vod;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final live = await _service.load(scope: PlayerSettingsScope.liveTv);
    final vod = await _service.load(scope: PlayerSettingsScope.filmSeriesTv);
    if (!mounted) return;
    setState(() {
      _live = live;
      _vod = vod;
    });
  }

  Future<void> _open(PlayerSettingsScope scope) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerSettingsScreen(scope: scope)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final live = _live;
    final vod = _vod;
    return ApplePageScaffold(
      title: 'Player video',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 20),
            child: Text(
              'Dirette e video usano impostazioni separate: scegli un profilo da modificare.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 15),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ProfileCard(
                  autofocus: true,
                  icon: Icons.live_tv_rounded,
                  title: 'Dirette TV',
                  caption: 'Canali, anteprima e guida',
                  settings: live,
                  lines: live == null
                      ? const []
                      : [
                          ('Motore', live.primaryEngine.label),
                          ('Formato flusso', live.liveStreamFormat.label),
                          ('Immagine', live.fitMode.label),
                          (
                            'Motore di riserva',
                            live.autoFallback ? 'Attivo' : 'Spento',
                          ),
                        ],
                  onPressed: () => _open(PlayerSettingsScope.liveTv),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _ProfileCard(
                  icon: Icons.movie_filter_rounded,
                  title: 'Video e raccolte',
                  caption: 'On demand, episodi e download',
                  settings: vod,
                  lines: vod == null
                      ? const []
                      : [
                          ('Motore', vod.primaryEngine.label),
                          ('Velocità', formatSpeed(vod.defaultSpeed)),
                          (
                            'Riprendi visione',
                            vod.resumePlayback ? 'Attivo' : 'Spento',
                          ),
                          ('Salto', '${vod.seekStepSeconds} s'),
                        ],
                  onPressed: () => _open(PlayerSettingsScope.filmSeriesTv),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.icon,
    required this.title,
    required this.caption,
    required this.settings,
    required this.lines,
    required this.onPressed,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String caption;
  final PlayerSettings? settings;
  final List<(String, String)> lines;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final engine = settings?.primaryEngine;
    return TvFocusable(
      autofocus: autofocus,
      focusedScale: 1.03,
      borderRadius: BorderRadius.circular(22),
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        caption,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
            if (engine != null) ...[
              const SizedBox(height: 16),
              Text(
                engine.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (settings == null)
              Center(child: CircularProgressIndicator(color: AppColors.primary))
            else
              for (final (k, v) in lines)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppColors.border, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          k,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Text(
                        v,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
