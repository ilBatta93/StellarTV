import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/tmdb_item.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../providers/discover_provider.dart';
import '../services/device_type_service.dart';
import '../theme/app_theme.dart';
import '../widgets/channel_card.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_row.dart';
import '../widgets/tv_text_field.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<TmdbItem> _tmdbResults = [];
  bool _searchingTmdb = false;
  String? _tmdbError;
  int _requestId = 0;
  Timer? _localDebounce;
  String _localQuery = '';
  Map<ContentType, List<Channel>> _local = const {};
  Object? _localSource;

  @override
  void dispose() {
    _debounce?.cancel();
    _localDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _query = value.trim());
    _localDebounce?.cancel();
    _localDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _localQuery = _query);
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _searchTmdb);
  }

  Future<void> _searchTmdb() async {
    final query = _query;
    final id = ++_requestId;
    if (query.length < 2) {
      setState(() {
        _tmdbResults = [];
        _tmdbError = null;
        _searchingTmdb = false;
      });
      return;
    }
    setState(() => _searchingTmdb = true);
    try {
      final results = await context.read<DiscoverProvider>().tmdb.search(query);
      if (!mounted || id != _requestId) return;
      setState(() {
        _tmdbResults = results;
        _tmdbError = null;
        _searchingTmdb = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _tmdbResults = [];
        _tmdbError = e.toString();
        _searchingTmdb = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    if (_localSource != app.allChannels || _computedFor != _localQuery) {
      _computeLocal(app);
    }
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TvTextField(
            controller: _controller,
            clearable: DeviceTypeService.isTv,
            autofocus: !DeviceTypeService.isTv,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'Cerca canali, film e serie',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                    ),
            ),
          ),
        ),
      ),
      body: _query.isEmpty
          ? const EmptyState(
              icon: Icons.manage_search_rounded,
              title: 'Cerca ovunque',
              message:
                  'Trova canali in diretta, film e serie nella tua playlist e in tutto il catalogo.',
            )
          : _buildResults(app),
    );
  }

  String? _computedFor;

  /// Playlist results are computed once per (debounced) query, not on
  /// every keystroke / rebuild.
  void _computeLocal(AppProvider app) {
    _localSource = app.allChannels;
    _computedFor = _localQuery;
    _local = {
      for (final type in const [
        ContentType.live,
        ContentType.movie,
        ContentType.series,
        ContentType.anime,
      ])
        type: _localQuery.length < 2 && _localQuery.isNotEmpty
            ? const <Channel>[]
            : app.searchChannels(_localQuery, type: type),
    };
  }

  Widget _buildResults(AppProvider app) {
    final tmdbResults = _tmdbResults.where(app.isTmdbAllowed).toList();
    final sections = [
      (ContentType.live, 'TV in Diretta'),
      (ContentType.movie, 'Film nella tua playlist'),
      (ContentType.series, 'Serie TV nella tua playlist'),
      (ContentType.anime, 'Anime nella tua playlist'),
    ];
    final local = _local;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        for (final (type, label) in sections)
          if ((local[type] ?? const []).isNotEmpty) ...[
            SectionHeader(
              title: label,
              subtitle: '${local[type]!.length} risultati',
            ),
            _ChannelRow(channels: local[type]!.take(30).toList(), type: type),
          ],
        const SectionHeader(
          title: 'Dal catalogo',
          subtitle: 'Film e serie da TMDB',
        ),
        if (_searchingTmdb)
          Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          )
        else if (_tmdbError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _tmdbError!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else if (tmdbResults.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Nessun titolo trovato nel catalogo.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              childAspectRatio: 0.58,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
            itemCount: tmdbResults.length,
            itemBuilder: (context, i) => TmdbPosterCard(
              item: tmdbResults[i],
              width: double.infinity,
              onTap: () => openTmdbItem(context, tmdbResults[i]),
            ),
          ),
      ],
    );
  }
}

class _ChannelRow extends StatelessWidget {
  final List<Channel> channels;
  final ContentType type;

  const _ChannelRow({required this.channels, required this.type});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final isLive = type == ContentType.live;
    return HorizontalRow(
      height: isLive ? 150 : 196,
      itemCount: channels.length,
      itemBuilder: (context, i) {
        final c = channels[i];
        return SizedBox(
          width: isLive ? 128 : 112,
          child: ChannelCard(
            channel: c,
            isFavorite: app.favoriteIds.contains(c.id),
            onTap: () => openChannel(context, c),
            onFavoriteTap: () => app.toggleFavorite(c),
          ),
        );
      },
    );
  }
}
