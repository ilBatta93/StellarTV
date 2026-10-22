import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../theme/app_theme.dart';
import 'device_type_service.dart';
import '../widgets/tv_focusable.dart';

/// Navigator used to show the update dialog from anywhere (startup check).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class AppRelease {
  final String version;
  final int build;
  final String notes;
  final String apkUrl;
  const AppRelease(this.version, this.build, this.notes, this.apkUrl);
}

/// Checks GitHub Releases for a newer APK, downloads it and opens the
/// Android installer. Android only; every step is remote-friendly.
class AppUpdateService {
  static const String _repo = 'ilBatta93/StellarTV-releases';
  static const String _defined = String.fromEnvironment('APP_VERSION');
  static const MethodChannel _device = MethodChannel('stellartv/device');

  static String get currentVersion => _defined.isEmpty ? '3.0.0' : _defined;
  static int get currentBuild => buildOf(currentVersion);

  static bool _checking = false;
  static bool _startupDone = false;

  /// Comparable build key from a version or tag ("v3.1.4" -> 3001004).
  /// Semantic order Major > Minor > Patch, so 3.1.0 > 3.0.12 and 4.0.0 > 3.9.50.
  static int buildOf(String v) {
    final clean = v
        .trim()
        .replaceAll(RegExp(r'^[vV]'), '')
        .split(RegExp(r'[-+ ]'))
        .first;
    final parts = clean.split('.');
    int seg(int i) {
      if (i >= parts.length) return 0;
      final m = RegExp(r'^\d+').firstMatch(parts[i]);
      final n = int.tryParse(m?.group(0) ?? '') ?? 0;
      return n > 999 ? 999 : n;
    }

    return seg(0) * 1000000 + seg(1) * 1000 + seg(2);
  }

  static Future<AppRelease?> fetchLatest() async {
    final res = await http
        .get(
          Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception(
        'Server aggiornamenti non raggiungibile (${res.statusCode})',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] ?? '').toString();
    final assets = (data['assets'] as List? ?? const []).cast<Map>();
    final apk = assets.firstWhere(
      (a) => a['name'].toString().toLowerCase().endsWith('.apk'),
      orElse: () => const {},
    );
    final url = apk['browser_download_url']?.toString();
    if (url == null) return null;
    return AppRelease(
      tag.replaceAll(RegExp(r'^[vV]'), ''),
      buildOf(tag),
      (data['body'] ?? '').toString(),
      url,
    );
  }

  /// Silent check ~20 s after launch, only on CI builds with a known version.
  static void scheduleStartupCheck() {
    if (kIsWeb || !Platform.isAndroid || _defined.isEmpty || _startupDone)
      return;
    _startupDone = true;
    Future.delayed(const Duration(seconds: 20), () async {
      try {
        final rel = await fetchLatest();
        final ctx = appNavigatorKey.currentContext;
        if (rel != null &&
            rel.build > currentBuild &&
            ctx != null &&
            ctx.mounted) {
          await showReleaseDialog(ctx, rel);
        }
      } catch (_) {
        /* silent at startup */
      }
    });
  }

  static Future<void> checkManually(BuildContext context) async {
    if (_checking) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (kIsWeb || !Platform.isAndroid) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Aggiornamento automatico disponibile solo su Android'),
        ),
      );
      return;
    }
    _checking = true;
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Verifica aggiornamenti…'),
        duration: Duration(seconds: 2),
      ),
    );
    try {
      final rel = await fetchLatest();
      if (!context.mounted) return;
      if (rel == null || rel.build <= currentBuild) {
        messenger?.showSnackBar(
          SnackBar(content: Text('StellarTV è aggiornata (v$currentVersion)')),
        );
      } else {
        await showReleaseDialog(context, rel);
      }
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Verifica non riuscita: $e')),
      );
    } finally {
      _checking = false;
    }
  }

  static Future<void> showReleaseDialog(BuildContext context, AppRelease rel) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(release: rel),
    );
  }

  static Future<String> download(
    AppRelease rel,
    void Function(double) onProgress,
  ) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File('${dir.path}/StellarTV-${rel.version}.apk');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(rel.apkUrl)));
      if (res.statusCode != 200)
        throw Exception('Download non riuscito (${res.statusCode})');
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = file.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
    } finally {
      client.close();
    }
    return file.path;
  }

  static Future<bool> canInstall() async =>
      (await _device.invokeMethod<bool>('canInstallApk')) ?? true;
  static Future<void> openInstallSettings() =>
      _device.invokeMethod('openInstallSettings');
  static Future<void> install(String path) =>
      _device.invokeMethod('installApk', path);
}

class _UpdateDialog extends StatefulWidget {
  final AppRelease release;
  const _UpdateDialog({required this.release});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String? _error;
  String? _path;
  final _notesScroll = ScrollController();
  final _notesFocus = FocusNode(debugLabel: 'update-notes');
  final _updateFocus = FocusNode(debugLabel: 'update-install');
  final _laterFocus = FocusNode(debugLabel: 'update-later');
  bool _readingNotes = false;

  @override
  void dispose() {
    _notesScroll.dispose();
    _notesFocus.dispose();
    _updateFocus.dispose();
    _laterFocus.dispose();
    super.dispose();
  }

  KeyEventResult _navigate(FocusNode node, KeyEvent event) {
    if (!DeviceTypeService.isTv ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_notesFocus.hasFocus) {
      if (key != LogicalKeyboardKey.arrowUp &&
          key != LogicalKeyboardKey.arrowDown) {
        return KeyEventResult.ignored;
      }
      if (!_notesScroll.hasClients) return KeyEventResult.handled;
      final position = _notesScroll.position;
      final down = key == LogicalKeyboardKey.arrowDown;
      if (down && position.pixels >= position.maxScrollExtent - 0.5) {
        if (_progress == null) _updateFocus.requestFocus();
      } else {
        // Immediate bounded steps remain safe under held D-Pad input.
        _notesScroll.jumpTo(
          (position.pixels + (down ? 56 : -56))
              .clamp(0.0, position.maxScrollExtent)
              .toDouble(),
        );
      }
      return KeyEventResult.handled;
    }
    if (_updateFocus.hasFocus || _laterFocus.hasFocus) {
      if (key == LogicalKeyboardKey.arrowUp &&
          widget.release.notes.trim().isNotEmpty) {
        if (_notesScroll.hasClients) _notesScroll.jumpTo(0);
        _notesFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        if (_progress == null) {
          (key == LogicalKeyboardKey.arrowLeft ? _laterFocus : _updateFocus)
              .requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _start() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      _path ??= await AppUpdateService.download(widget.release, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!await AppUpdateService.canInstall()) {
        if (mounted) {
          setState(() {
            _progress = null;
            _error =
                'Consenti a StellarTV di installare app, poi premi di nuovo "Installa".';
          });
        }
        await AppUpdateService.openInstallSettings();
        return;
      }
      final path = _path;
      if (!mounted || path == null) return;
      await AppUpdateService.install(path);
      if (mounted) setState(() => _progress = null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _progress != null;
    final notes = widget.release.notes.trim();
    final tv = DeviceTypeService.isTv;
    Widget action(
      Widget child,
      FocusNode focus,
      VoidCallback onPressed, {
      bool autofocus = false,
    }) => tv
        ? TvFocusable(
            focusNode: focus,
            autofocus: autofocus,
            focusedScale: 1,
            revealOnFocus: false,
            onPressed: () {
              if (!busy) onPressed();
            },
            child: child,
          )
        : child;
    final notesView = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 160),
      child: Scrollbar(
        controller: _notesScroll,
        thumbVisibility: tv,
        child: SingleChildScrollView(
          controller: _notesScroll,
          child: Text(notes, style: Theme.of(context).textTheme.bodySmall),
        ),
      ),
    );
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _navigate,
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Nuova versione v${widget.release.version}'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hai la v${AppUpdateService.currentVersion}.'),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                if (tv)
                  Focus(
                    focusNode: _notesFocus,
                    onFocusChange: (value) {
                      if (mounted) setState(() => _readingNotes = value);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _readingNotes
                              ? AppColors.primary
                              : AppColors.clear,
                          width: 2,
                        ),
                      ),
                      child: ExcludeFocus(child: notesView),
                    ),
                  )
                else
                  notesView,
              ],
              if (busy) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                ),
                const SizedBox(height: 6),
                Text('Download ${((_progress ?? 0) * 100).round()}%'),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error ?? '', style: TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
        actions: [
          action(
            TextButton(
              focusNode: tv ? null : _laterFocus,
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Più tardi'),
            ),
            _laterFocus,
            () => Navigator.of(context).pop(),
          ),
          action(
            FilledButton(
              focusNode: tv ? null : _updateFocus,
              autofocus: !tv,
              onPressed: busy ? null : _start,
              child: Text(_path == null ? 'Aggiorna ora' : 'Installa'),
            ),
            _updateFocus,
            _start,
            autofocus: true,
          ),
        ],
      ),
    );
  }
}
