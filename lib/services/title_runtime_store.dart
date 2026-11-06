import '../models/channel.dart';
import '../models/tmdb_item.dart';
import 'catalog_rating_service.dart';
import 'title_metadata_store.dart';

/// Lengths learned from the TMDB details already fetched when a title page
/// opens. Catalog posters read them without asking TMDB once per card, so a
/// length shows only for titles whose page was opened at least once.
class TitleRuntimeStore {
  TitleRuntimeStore._();
  static final instance = TitleRuntimeStore._();

  final store = TitleMetadataStore<int>(
    fileName: 'title_runtimes_v1.json',
    ttl: const Duration(days: 365),
    encode: (v) => v,
    decode: (v) => v is num && v > 0 ? v.toInt() : null,
  );

  Future<void> load() => store.load();

  /// Minutes of a film, or the usual episode length of a series.
  void remember(TmdbItem item, int? minutes) {
    if (item.id <= 0 || minutes == null || minutes <= 0) return;
    if (store.valueOf(item.key) == minutes) return;
    store.put(item.key, minutes);
  }

  /// Stored length for a catalog title. No network.
  int? minutesOf(Channel channel) {
    final rating = CatalogRatingService.instance;
    final item = rating.itemOf(channel);
    if (item != null) return store.valueOf(item.key);
    final link = rating.linkedIdentity(channel);
    if (link == null) return null;
    return store.valueOf('${link.movie ? 'movie' : 'tv'}_${link.id}');
  }
}
