import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../services/external_player_service.dart';
import 'settings_tiles.dart';
import 'tv_focusable.dart';

/// Lists the player apps installed on the device and stores the choice.
/// Returns null when none is installed or the sheet is dismissed.
Future<ExternalPlayer?> chooseExternalPlayer(BuildContext context) async {
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
  final picked = await pickOption<ExternalPlayer>(
    context,
    title: 'Player esterno',
    options: players,
    current: current,
    label: (p) => p.label,
  );
  if (picked != null) await service.setPlayer(picked);
  return picked;
}

/// "Apri con …" on a title page. When the external player is already
/// the default it offers the built-in one instead. [onPlay] receives the
/// player to use (true = external).
class ExternalPlayButton extends StatelessWidget {
  const ExternalPlayButton({
    super.key,
    required this.channel,
    required this.onPlay,
    this.style,
  });

  final Channel channel;
  final ValueChanged<bool> onPlay;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final service = ExternalPlayerService.instance;
    if (!service.supported || !ExternalPlayerService.canPlay(channel)) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final external = !service.enabled;
        final label = !external
            ? 'Player interno'
            : 'Apri con ${service.player?.label ?? 'player esterno'}';
        Future<void> press() async {
          if (external && service.player == null) {
            if (await chooseExternalPlayer(context) == null) return;
          }
          onPlay(external);
        }

        return TvFocusable(
          onPressed: press,
          child: OutlinedButton.icon(
            onPressed: press,
            style: style,
            icon: Icon(
              external ? Icons.open_in_new_rounded : Icons.play_circle_outline,
            ),
            label: Text(label),
          ),
        );
      },
    );
  }
}
