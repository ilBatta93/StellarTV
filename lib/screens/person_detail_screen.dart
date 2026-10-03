import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tmdb_item.dart';
import '../models/tmdb_person.dart';
import '../navigation/app_routes.dart';
import '../providers/discover_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_row.dart';

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
      final details = await tmdb.personDetails(widget.person.id);
      final credits = await tmdb.personCredits(widget.person.id);
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
                    Image.network(
                      person.profileUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _headerFallback(person),
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
                  Text(person.name,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (person.knownForCount > 0)
                        _Chip(label: '${person.knownForCount} contenuti'),
                      if (person.birthday != null &&
                          person.birthday!.isNotEmpty)
                        _Chip(label: 'Nato il ${_formatDate(person.birthday!)}'),
                      if (person.placeOfBirth != null &&
                          person.placeOfBirth!.isNotEmpty)
                        _Chip(label: person.placeOfBirth!),
                    ],
                  ),
                  if (person.biography != null &&
                      person.biography!.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Biografia',
                        style: Theme.of(context).textTheme.titleMedium),
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
                    Text('Interpreta: ${widget.person.character}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
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
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final item = _credits[i];
                    return TmdbPosterCard(
                      item: item,
                      onTap: () => openTmdbItem(context, item),
                    );
                  },
                  childCount: _credits.length,
                ),
              ),
            ),
          ],
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
      child: Text(label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    );
  }
}
