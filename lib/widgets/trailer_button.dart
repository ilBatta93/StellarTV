import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/tmdb_item.dart';
import '../models/title_trailer.dart';
import '../providers/discover_provider.dart';
import 'tv_focusable.dart';

class TrailerButton extends StatefulWidget {
  const TrailerButton({super.key, required this.item});
  final TmdbItem item;
  @override
  State<TrailerButton> createState() => _TrailerButtonState();
}

class _TrailerButtonState extends State<TrailerButton> {
  Future<TitleTrailer?>? _trailer;
  String? _key;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(TrailerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    if (_key == widget.item.key) return;
    _key = widget.item.key;
    _trailer = context.read<DiscoverProvider>().tmdb.trailer(widget.item);
  }

  Future<void> _open(TitleTrailer trailer) async {
    try {
      if (await launchUrl(trailer.url, mode: LaunchMode.externalApplication))
        return;
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Impossibile aprire il trailer. Nessuna app compatibile disponibile.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TitleTrailer?>(
    future: _trailer,
    builder: (_, snapshot) {
      final trailer = snapshot.data;
      if (trailer == null) return const SizedBox.shrink();
      void open() {
        _open(trailer);
      }

      return TvFocusable(
        onPressed: open,
        child: OutlinedButton.icon(
          onPressed: open,
          icon: const Icon(Icons.smart_display_outlined),
          label: Text('Trailer · ${trailer.language == 'it' ? 'ITA' : 'ENG'}'),
        ),
      );
    },
  );
}
