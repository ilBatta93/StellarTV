import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../services/external_player_service.dart';
import 'settings_tiles.dart';
import 'tv_focusable.dart';

/// Lists the player apps installed on the device. Returns null when none is
/// installed or the sheet is dismissed. Nothing is stored.
Future<ExternalPlayer?> pickInstalledPlayer(
  BuildContext context, {
  String title = 'Apri con',
}) async {
  final service = ExternalPlayerService.instance;
  final players = await service.installed();
  if (!context.mounted) return null;
  if (players.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Nessun player video installato. Installa ad esempio VLC o '
          'Just Player dallo store',
        ),
      ),
    );
    return null;
  }
  final current = players.firstWhere(
    (p) => p.package == service.player?.package,
    orElse: () => players.first,
  );
  return pickOption<ExternalPlayer>(
    context,
    title: title,
    options: players,
    current: current,
    label: (p) => p.label,
  );
}

/// Settings: picks the player app and stores the choice.
Future<ExternalPlayer?> chooseExternalPlayer(BuildContext context) async {
  final picked = await pickInstalledPlayer(context, title: 'Player esterno');
  if (picked != null) await ExternalPlayerService.instance.setPlayer(picked);
  return picked;
}

/// "Apri con …" on a title page or an episode: every press asks which app
/// to use and never stores the answer. When the external player is already
/// the default it offers the built-in one instead. [onPlay] receives the
/// app picked, or null for the built-in player.
class ExternalPlayButton extends StatelessWidget {
  const ExternalPlayButton({
    super.key,
    required this.channel,
    required this.onPlay,
    this.style,
    this.compact = false,
    this.focusNode,
  });

  final Channel channel;
  final ValueChanged<ExternalPlayer?> onPlay;
  final ButtonStyle? style;

  /// Icon only, with the label as tooltip (episode cards).
  final bool compact;
  final FocusNode? focusNode;

  /// Whether the button renders anything for [channel] on this device.
  static bool shows(Channel channel) =>
      ExternalPlayerService.instance.supported &&
      ExternalPlayerService.canPlay(channel);

  @override
  Widget build(BuildContext context) {
    final service = ExternalPlayerService.instance;
    if (!shows(channel)) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final external = !service.enabled;
        final label = !external ? 'Player interno' : 'Apri con…';
        Future<void> press() async {
          if (!external) return onPlay(null);
          final picked = await pickInstalledPlayer(context);
          if (picked != null) onPlay(picked);
        }

        final icon = Icon(
          external ? Icons.open_in_new_rounded : Icons.play_circle_outline,
        );
        return TvFocusable(
          focusNode: focusNode,
          onPressed: press,
          child: compact
              ? IconButton(
                  tooltip: label,
                  onPressed: press,
                  style: style,
                  icon: icon,
                )
              : OutlinedButton.icon(
                  onPressed: press,
                  style: style,
                  icon: icon,
                  label: Text(label),
                ),
        );
      },
    );
  }
}
