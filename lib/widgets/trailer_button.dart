import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/trailer_screen.dart';
import '../models/tmdb_item.dart';
import '../models/title_trailer.dart';
import '../providers/discover_provider.dart';
import 'tv_focusable.dart';

class TrailerButton extends StatefulWidget {
  const TrailerButton({super.key, required this.item});
  final TmdbItem item;

  /// Test seam: replaces the in-app trailer page.
  @visibleForTesting
  static Future<void> Function(BuildContext, TitleTrailer)? opener;
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

  Future<void> _open(TitleTrailer trailer) =>
      TrailerButton.opener?.call(context, trailer) ??
      Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => TrailerScreen(trailer: trailer)),
  );

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
          label: Text('Trailer · ${trailer.badge}'),
        ),
      );
    },
  );
}
