/// Independent playlist progress. No guessed download percentages.
enum CatalogLoadPhase { idle, queued, loading, ready, cached, failed }

class CatalogLoadState {
  final CatalogLoadPhase phase;
  final bool hasContent;
  final String? error;
  const CatalogLoadState({
    this.phase = CatalogLoadPhase.idle,
    this.hasContent = false,
    this.error,
  });
  bool get isPending =>
      phase == CatalogLoadPhase.queued || phase == CatalogLoadPhase.loading;
  String get label => switch (phase) {
    CatalogLoadPhase.idle => '',
    CatalogLoadPhase.queued => hasContent ? 'Pronta · in attesa' : 'In attesa',
    CatalogLoadPhase.loading => hasContent ? 'Aggiornamento' : 'Caricamento',
    CatalogLoadPhase.ready => 'Pronta',
    CatalogLoadPhase.cached => 'Copia salvata',
    CatalogLoadPhase.failed => 'Non disponibile',
  };
}
