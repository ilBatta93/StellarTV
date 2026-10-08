import '../services/image_cache_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tmdb_item.dart';
import '../models/tmdb_person.dart';
import '../navigation/app_routes.dart';
import '../providers/discover_provider.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_row.dart';
import '../services/device_type_service.dart';
import '../widgets/tv_detail_backdrop.dart';
import '../widgets/tv_focusable.dart';

class PersonDetailScreen extends StatefulWidget {
  final TmdbPerson person;

  const PersonDetailScreen({super.key, required this.person});

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  TmdbPerson? _details;
  List<TmdbItem> _credits = [];
  bool _loading = true;
  String? _error;
  bool _bioExpanded = false;
  final _tvScroll = ScrollController();

  @override
  void dispose() {
    _tvScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tmdb = context.read<DiscoverProvider>().tmdb;
      final detailsFuture = tmdb.personDetails(widget.person.id);
      final creditsFuture = tmdb.personCredits(widget.person.id);
      final details = await detailsFuture;
      final credits = await creditsFuture;
      if (!mounted) return;
      setState(() {
        _details = details ?? widget.person;
        _credits = credits;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossibile caricare i contenuti di questo attore.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = _details ?? widget.person;
    final credits = _credits
        .where(context.watch<AppProvider>().isTmdbAllowed)
        .toList();

    if (DeviceTypeService.isTv) return _buildTv(person, credits);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            backgroundColor: AppColors.background,
            leading: const BackButton(),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (person.profileUrl.isNotEmpty)
                    CachedNetworkImage(
                      cacheManager: AppImageCache.manager,
                      imageUrl: person.profileUrl.replaceFirst(
                        '/w342',
                        '/w780',
                      ),
                      memCacheWidth: 720,
                      fadeInDuration: const Duration(milliseconds: 150),
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => _headerFallback(person),
                    )
                  else
                    _headerFallback(person),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x8009090D),
                          Colors.transparent,
                          AppColors.background,
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
                  Text(
                    person.name,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (person.knownForCount > 0)
                        _Chip(label: '${person.knownForCount} contenuti'),
                      if (person.birthday != null &&
                          person.birthday!.isNotEmpty)
                        _Chip(
                          label: 'Nato il ${_formatDate(person.birthday!)}',
                        ),
                      if (person.placeOfBirth != null &&
                          person.placeOfBirth!.isNotEmpty)
                        _Chip(label: person.placeOfBirth!),
                    ],
                  ),
                  if (person.biography != null &&
                      person.biography!.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Biografia',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      person.biography!,
                      maxLines: _bioExpanded ? null : 4,
                      overflow: _bioExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _bioExpanded = !_bioExpanded),
                      child: Text(_bioExpanded ? 'Mostra meno' : 'Leggi tutto'),
                    ),
                  ],
                  if (widget.person.character != null &&
                      widget.person.character!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Interpreta: ${widget.person.character}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_loading)
            SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.error_outline_rounded,
                title: _error!,
                message: 'Controlla la connessione e riprova.',
                action: ElevatedButton.icon(
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Riprova'),
                  onPressed: _load,
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Contenuti con ${person.name}',
                subtitle: 'Disponibili nel catalogo TMDB',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 140,
                  childAspectRatio: 0.58,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final item = credits[i];
                  return TmdbPosterCard(
                    item: item,
                    onTap: () => openTmdbItem(context, item),
                  );
                }, childCount: credits.length),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTv(TmdbPerson person, List<TmdbItem> credits) {
    final backdrop = credits
        .where((item) => item.backdropPath != null)
        .firstOrNull;
    final birthday = person.birthday;
    final place = person.placeOfBirth;
    final biography = person.biography;
    return TvDetailBackdrop(
      image: backdrop?.backdropUrl,
      child: Stack(
        children: [
          CustomScrollView(
            controller: _tvScroll,
            cacheExtent: 1200,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 0, 0),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: TvFocusable(
                      autofocus: true,
                      onFocusChange: (focused) {
                        if (!focused) return;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _tvScroll.hasClients) {
                            _tvScroll.animateTo(
                              0,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                            );
                          }
                        });
                      },
                      onPressed: () => Navigator.pop(context),
                      child: const BackButton(),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    32,
                    TvDetailBackdrop.topSpace(context),
                    32,
                    24,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 128,
                          height: 176,
                          child: PosterImage(
                            url: person.profileUrl,
                            fallbackIcon: Icons.person_outline_rounded,
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              person.name,
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _Chip(label: '${credits.length} contenuti'),
                                if (birthday != null && birthday.isNotEmpty)
                                  _Chip(
                                    label: 'Nato il ${_formatDate(birthday)}',
                                  ),
                                if (place != null && place.isNotEmpty)
                                  _Chip(label: place),
                              ],
                            ),
                            if (biography != null &&
                                biography.trim().isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                biography,
                                maxLines: _bioExpanded ? null : 4,
                                overflow: _bioExpanded
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              TvFocusable(
                                focusedScale: 1,
                                onPressed: () => setState(
                                  () => _bioExpanded = !_bioExpanded,
                                ),
                                child: TextButton(
                                  onPressed: () => setState(
                                    () => _bioExpanded = !_bioExpanded,
                                  ),
                                  child: Text(
                                    _bioExpanded
                                        ? 'Mostra meno'
                                        : 'Leggi tutto',
                                  ),
                                ),
                              ),
                            ],
                            if (widget.person.character?.isNotEmpty ==
                                true) ...[
                              const SizedBox(height: 8),
                              Text('Interpreta: ${widget.person.character}'),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                SliverToBoxAdapter(
                  child: TvFocusable(
                    onPressed: _load,
                    child: TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Riprova'),
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
                    child: Text(
                      'Contenuti con ${person.name}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 132,
                          childAspectRatio: 0.6,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => TmdbPosterCard(
                        width: double.infinity,
                        item: credits[i],
                        onTap: () => openTmdbItem(context, credits[i]),
                      ),
                      childCount: credits.length,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerFallback(TmdbPerson person) => Container(
    color: AppColors.card,
    child: Center(
      child: Text(
        person.name.isNotEmpty ? person.name[0].toUpperCase() : '?',
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 48,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  String _formatDate(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
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
      child: Text(
        label,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    );
  }
}
