import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/content_type.dart';
import '../models/tmdb_item.dart';
import '../models/tmdb_person.dart';
import '../navigation/app_routes.dart';
import '../providers/app_provider.dart';
import '../providers/discover_provider.dart';
import '../services/catalog_builder.dart';
import '../theme/app_theme.dart';
import '../screens/catalog_page.dart' show pickVariant;
import '../screens/person_detail_screen.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_row.dart';

class TitleDetailScreen extends StatefulWidget {
  final TmdbItem? item;
  final Channel? channel;

  const TitleDetailScreen({super.key, this.item, this.channel})
      : assert(item != null || channel != null);

  @override
  State<TitleDetailScreen> createState() => _TitleDetailScreenState();
}

class _TitleDetailScreenState extends State<TitleDetailScreen> {
  TmdbItem? _item;
  List<TmdbItem> _similar = [];
  List<TmdbPerson> _cast = [];
  List<Channel> _variants = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _load();
  }

  Future<void> _load() async {
    final tmdb = context.read<DiscoverProvider>().tmdb;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var item = _item;
      final channel = widget.channel;
      if (item == null && channel != null) {
        item = await tmdb.findByTitle(channel.name,
            isMovie: channel.type == ContentType.movie);
      }
      final similar =
          item == null ? <TmdbItem>[] : await tmdb.recommendations(item);
      final cast = item == null
          ? <TmdbPerson>[]
          : await tmdb.cast(item);
      if (!mounted) return;
      setState(() {
        _item = item;
        _similar = similar.take(20).toList();
        _cast = cast.take(20).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final item = _item;
    final playable =
        widget.channel ?? (item == null ? null : app.findChannelFor(item));
    final variants = _findVariants(app, item);
    final title = item?.title ?? widget.channel!.name;
    final image = item?.backdropUrl ?? widget.channel?.logo;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            backgroundColor: AppColors.background,
            actions: [
              if (playable != null)
                IconButton(
                  tooltip: 'Preferiti',
                  icon: Icon(
                    app.favoriteIds.contains(playable.id)
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: app.favoriteIds.contains(playable.id)
                        ? AppColors.primary
                        : AppColors.textPrimary,
                  ),
                  onPressed: () => app.toggleFavorite(playable),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(url: image),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x8009090D),
                          Colors.transparent,
                          AppColors.background
                        ],
                        stops: [0, 0.4, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  _Meta(item: item, channel: widget.channel),
                  const SizedBox(height: 16),
                  _Actions(
                      item: item,
                      playable: playable,
                      variants: variants),
                  if (item != null && item.overview.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Trama',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(item.overview,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildCast()),
          SliverToBoxAdapter(child: _buildSimilar()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  /// All playlist copies of this title (different qualities/categories).
  List<Channel> _findVariants(AppProvider app, TmdbItem? item) {
    if (item != null) {
      final found = app.findChannelFor(item);
      if (found != null) return app.variantsFor(found);
    }
    final channel = widget.channel;
    if (channel != null) return app.variantsFor(channel);
    return const [];
  }

  Widget _buildCast() {
    if (_cast.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Cast', subtitle: 'Tocca un attore per saperne di più'),
        HorizontalRow(
          height: 160,
          itemCount: _cast.length,
          itemBuilder: (context, i) {
            final person = _cast[i];
            return Pressable(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PersonDetailScreen(person: person)),
              ),
              child: SizedBox(
                width: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(48),
                        child: person.profileUrl.isNotEmpty
                            ? Image.network(
                                person.profileUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    _castFallback(person),
                              )
                            : _castFallback(person),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (person.character != null)
                      Text(
                        person.character!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _castFallback(TmdbPerson person) => Container(
        color: AppColors.card,
        alignment: Alignment.center,
        child: Text(
          person.name.isNotEmpty ? person.name[0].toUpperCase() : '?',
          style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 24,
              fontWeight: FontWeight.w700),
        ),
      );

  Widget _buildSimilar() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: AppColors.warning, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_error!,
                    style: Theme.of(context).textTheme.bodyMedium)),
            TextButton(onPressed: _load, child: const Text('Riprova')),
          ],
        ),
      );
    }
    if (_similar.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
            title: 'Titoli simili', subtitle: 'Potrebbero piacerti anche'),
        HorizontalRow(
          height: 210,
          itemCount: _similar.length,
          itemBuilder: (context, i) => TmdbPosterCard(
            item: _similar[i],
            onTap: () => openTmdbItem(context, _similar[i]),
          ),
        ),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  final TmdbItem? item;
  final Channel? channel;

  const _Meta({required this.item, required this.channel});

  @override
  Widget build(BuildContext context) {
    final isMovie = item?.isMovie ?? channel?.type == ContentType.movie;
    final chips = <Widget>[
      _Chip(label: isMovie ? 'Film' : 'Serie TV'),
      if (item != null && item!.year.isNotEmpty) _Chip(label: item!.year),
      if (item != null && item!.voteAverage > 0)
        RatingBadge(value: item!.voteAverage),
      if (channel != null) _Chip(label: channel!.group),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    );
  }
}

class _Actions extends StatelessWidget {
  final TmdbItem? item;
  final Channel? playable;
  final List<Channel> variants;

  const _Actions({
    required this.item,
    required this.playable,
    required this.variants,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final inList = item != null && app.isTmdbFavorite(item!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (playable != null)
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Guarda ora'),
            onPressed: () => _play(context),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: AppColors.textSecondary, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Questo titolo non è presente nella tua playlist.',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        if (variants.length > 1) ...[
          const SizedBox(height: 8),
          const Text('Versioni disponibili',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in variants)
                ActionChip(
                  label: Text(
                    CatalogBuilder.qualityLabel(v.name) ??
                        (v.group != playable!.group ? v.group : 'STD'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => openChannel(context, v),
                ),
            ],
          ),
        ],
        if (item != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: Icon(inList ? Icons.check_rounded : Icons.add_rounded),
            label: Text(inList ? 'Nella mia lista' : 'Aggiungi alla mia lista'),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  inList ? AppColors.success : AppColors.textPrimary,
              side: BorderSide(
                  color: inList ? AppColors.success : AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => app.toggleTmdbFavorite(item!),
          ),
        ],
        if (playable != null && playable!.type != ContentType.live) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Disponibile nella tua playlist: ${playable!.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _play(BuildContext context) async {
    if (playable == null) return;
    final entry = CatalogEntry(
        primary: playable!,
        variants: variants.isEmpty ? [playable!] : variants);
    final channel = await pickVariant(context, entry);
    if (channel == null || !context.mounted) return;
    openChannel(context, channel);
  }
}
