import '../widgets/ui_scale.dart';

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
import '../widgets/tv_wrap_navigation.dart';
import '../widgets/tv_text_field.dart';

/// Which kind of result the user wants to see.
enum SearchFilter { all, live, movie, series }

extension SearchFilterLabel on SearchFilter {
  String get label => switch (this) {
    SearchFilter.all => 'Tutto',
    SearchFilter.live => 'Diretta',
    SearchFilter.movie => 'Film',
    SearchFilter.series => 'Serie TV',
  };

  bool showsLocal(ContentType type) => switch (this) {
    SearchFilter.all => true,
    SearchFilter.live => type == ContentType.live,
    SearchFilter.movie => type == ContentType.movie,
    SearchFilter.series =>
      type == ContentType.series || type == ContentType.anime,
  };

  bool get showsCatalogMovies =>
      this == SearchFilter.all || this == SearchFilter.movie;
  bool get showsCatalogSeries =>
      this == SearchFilter.all || this == SearchFilter.series;
}

/// Search page in the same style as the Home: large title, rounded search
/// field, quick filters and horizontal rows navigable with the remote.
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
  int? _localStamp;
  String? _computedFor;
  int _localToken = 0;
  bool _localPending = false;
  SearchFilter _filter = SearchFilter.all;

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
    } catch (_) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _tmdbResults = [];
        _tmdbError = 'Catalogo non raggiungibile. Riprova tra poco.';
        _searchingTmdb = false;
      });
    }
  }

  /// One indexed lookup per debounced query. The scan stays off the UI isolate.
  void _loadLocal(AppProvider app) {
    final query = _localQuery;
    final token = ++_localToken;
    if (query.length < 2) {
      _localPending = false;
      return;
    }
    _localPending = true;
    unawaited(() async {
      final found = await app.searchCatalog(query);
      if (!mounted || token != _localToken) return;
      _localStamp = app.searchStamp;
      setState(() {
        _local = found;
        _localPending = false;
      });
    }());
    // Scheduling the index bumps the stamp before the next frame.
    _localStamp = app.searchStamp;
  }

  void _clear() {
    _controller.clear();
    _onChanged('');
  }

  @override
  Widget build(BuildContext context) => UiScale(builder: _buildContent);

  Widget _buildContent(BuildContext context) {
    final app = context.watch<AppProvider>();
    final stamp = app.searchStamp;
    if (_localStamp != stamp || _computedFor != _localQuery) {
      final queryChanged = _computedFor != _localQuery;
      _localStamp = stamp;
      _computedFor = _localQuery;
      if (queryChanged) _local = const {};
      _loadLocal(app);
    }
    final tv = DeviceTypeService.isTv;
    final side = tv ? 32.0 : 16.0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cerca'),
        toolbarHeight: tv ? 64 : 60,
        titleSpacing: tv ? 16 : 8,
      ),
      body: SafeArea(
        top: false,
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(side, 4, side, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: tv ? 760 : 720),
                      child: _SearchField(
                        controller: _controller,
                        query: _query,
                        onChanged: _onChanged,
                        onClear: _clear,
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _FilterBar(
                  value: _filter,
                  padding: side,
                  onChanged: (f) => setState(() => _filter = f),
                ),
              ),
              if (_query.length < 2)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.search_rounded,
                    title: 'Cerca film, serie TV e canali',
                    message: 'Scrivi almeno due lettere: cerco nella tua lista e nel catalogo.',
                  ),
                )
              else
                ..._results(app),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _results(AppProvider app) {
    final allowed = _tmdbResults.where(app.isTmdbAllowed).toList();
    final movies = allowed.where((t) => t.isMovie).toList();
    final series = allowed.where((t) => !t.isMovie).toList();
    final sections = [
      (ContentType.live, 'Canali in diretta'),
      (ContentType.movie, 'Film nella tua lista'),
      (ContentType.series, 'Serie TV nella tua lista'),
      (ContentType.anime, 'Animazione nella tua lista'),
    ];
    final rows = <Widget>[];
    for (final (type, label) in sections) {
      final found = _local[type] ?? const <Channel>[];
      if (found.isEmpty || !_filter.showsLocal(type)) continue;
      rows.add(
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: label,
                subtitle: found.length == 1
                    ? '1 risultato'
                    : '${found.length} risultati',
              ),
              _ChannelRow(channels: found.take(30).toList(), type: type),
            ],
          ),
        ),
      );
    }
    void catalog(String title, List<TmdbItem> items) {
      if (items.isEmpty) return;
      rows.add(
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: title, subtitle: 'Dal catalogo'),
              HorizontalRow(
                height: tmdbPosterRowHeight(context),
                spacing: DeviceTypeService.isTv ? 20 : 12,
                itemCount: items.length,
                itemBuilder: (context, i) => TmdbPosterCard(
                  item: items[i],
                  onTap: () => openTmdbItem(context, items[i]),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_filter.showsCatalogMovies) catalog('Film', movies);
    if (_filter.showsCatalogSeries) catalog('Serie TV', series);

    final wantsCatalog =
        _filter.showsCatalogMovies || _filter.showsCatalogSeries;
    if ((_searchingTmdb && wantsCatalog) || (_localPending && rows.isEmpty)) {
      rows.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      );
    } else if (rows.isEmpty) {
      rows.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Nessun risultato',
            message: _tmdbError ?? 'Prova con un altro titolo o cambia filtro.',
          ),
        ),
      );
    }
    return rows;
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tv = DeviceTypeService.isTv;
    final radius = BorderRadius.circular(tv ? 16 : 12);
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: color, width: width),
    );
    return TvTextField(
      controller: controller,
      clearable: tv,
      autofocus: !tv,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Film, serie TV, canali…',
        filled: true,
        fillColor: AppColors.surface,
        isDense: !tv,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: tv ? 18 : 12,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: tv ? 26 : 20,
          color: AppColors.textSecondary,
        ),
        suffixIcon: query.isEmpty || tv
            ? null
            : IconButton(
                tooltip: 'Cancella',
                icon: const Icon(Icons.cancel_rounded, size: 18),
                color: AppColors.textMuted,
                onPressed: onClear,
              ),
        border: border(AppColors.clear, 0),
        enabledBorder: border(AppColors.clear, 0),
        focusedBorder: border(AppColors.primary, tv ? 3 : 1.5),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.value,
    required this.padding,
    required this.onChanged,
  });

  final SearchFilter value;
  final double padding;
  final ValueChanged<SearchFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final tv = DeviceTypeService.isTv;
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, tv ? 16 : 12, padding, 0),
      child: TvWrapNavigation(
        child: Wrap(
          spacing: tv ? 12 : 8,
          runSpacing: 8,
          children: [
            for (final f in SearchFilter.values)
              ChoiceChip(
                label: Text(f.label),
                selected: f == value,
                showCheckmark: false,
                onSelected: (_) => onChanged(f),
                labelStyle: TextStyle(
                  fontSize: tv ? 16 : 13,
                  fontWeight: FontWeight.w600,
                  color: f == value
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surface,
                side: BorderSide(color: AppColors.clear),
                shape: const StadiumBorder(),
                padding: EdgeInsets.symmetric(
                  horizontal: tv ? 14 : 8,
                  vertical: tv ? 8 : 2,
                ),
              ),
          ],
        ),
      ),
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
