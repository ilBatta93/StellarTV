import '../models/source_access.dart';
import 'portal_source.dart';
import 'settings_service.dart';

/// Turns a stored item address into the address a player can open. Only
/// portal items need it: the portal creates their link at playback time.
class StreamAddress {
  StreamAddress._();

  static bool needsResolve(String url) => PortalSource.isAddress(url);

  /// Test hook.
  static Future<String> Function(String url)? override;

  static Future<String> resolve(String url) async {
    if (!needsResolve(url)) return url;
    if (override case final hook?) return hook(url);
    final access = SourceAccess.fromCredentials(
      await SettingsService().getXtreamCredentials(),
    );
    if (access == null || access.kind != SourceKind.portal) {
      throw const PortalException('Il portale non è più configurato.');
    }
    return PortalSession.of(access.server, access.mac).resolve(url);
  }
}
