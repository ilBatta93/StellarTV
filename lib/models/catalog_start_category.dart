import 'content_type.dart';

/// Which category Diretta, Film and Serie TV open on.
enum CatalogStartKind { last, newest, watched, all, group }

/// The opening category of one catalog tab. [group] is a category label
/// from the user's source: it stays on the device, never in the cloud.
class CatalogStartCategory {
  const CatalogStartCategory(this.kind, [this.group]);

  final CatalogStartKind kind;
  final String? group;

  /// Diretta keeps opening where it was left; Film and Serie TV on the
  /// latest additions, as before the choice existed.
  static CatalogStartCategory defaultFor(ContentType type) =>
      CatalogStartCategory(
        type == ContentType.live
            ? CatalogStartKind.last
            : CatalogStartKind.newest,
      );

  /// Kinds that make sense for [type]: Diretta has no "latest additions".
  static List<CatalogStartKind> kindsFor(ContentType type) => [
    CatalogStartKind.last,
    if (type != ContentType.live) CatalogStartKind.newest,
    CatalogStartKind.watched,
    CatalogStartKind.all,
    CatalogStartKind.group,
  ];

  String encode() =>
      kind == CatalogStartKind.group ? 'group:${group ?? ''}' : kind.name;

  /// Unknown, empty or unsuitable values fall back to [defaultFor].
  static CatalogStartCategory parse(Object? value, ContentType type) {
    if (value is String) {
      if (value.startsWith('group:')) {
        final label = value.substring(6);
        if (label.isNotEmpty) {
          return CatalogStartCategory(CatalogStartKind.group, label);
        }
      } else {
        final kind = CatalogStartKind.values.asNameMap()[value];
        if (kind != null &&
            kind != CatalogStartKind.group &&
            kindsFor(type).contains(kind)) {
          return CatalogStartCategory(kind);
        }
      }
    }
    return defaultFor(type);
  }

  String label(ContentType type) => switch (kind) {
    CatalogStartKind.last => 'Ultima usata',
    CatalogStartKind.newest => 'Ultimi aggiunti',
    CatalogStartKind.watched => 'Visti di recente',
    CatalogStartKind.all => switch (type) {
      ContentType.live => 'Tutti i canali',
      ContentType.movie => 'Tutti i film',
      _ => 'Tutte le serie TV',
    },
    CatalogStartKind.group => group ?? 'Una categoria',
  };

  @override
  bool operator ==(Object other) =>
      other is CatalogStartCategory &&
      other.kind == kind &&
      other.group == group;

  @override
  int get hashCode => Object.hash(kind, group);
}
