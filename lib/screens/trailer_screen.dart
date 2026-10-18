import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/title_trailer.dart';

/// Plays the trailer inside StellarTV so the remote Back key always returns
/// to the title page (the external YouTube TV app kept users inside it).
class TrailerScreen extends StatefulWidget {
  const TrailerScreen({super.key, required this.trailer});
  final TitleTrailer trailer;
  @override
  State<TrailerScreen> createState() => _TrailerScreenState();
}

class _TrailerScreenState extends State<TrailerScreen> {
  late final WebViewController _web;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final key = widget.trailer.key; // validated: 11 safe characters
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) => r.url.contains('/embed/') ||
                r.url.startsWith('about:') ||
                r.url.startsWith('https://stellartv.lovable.app')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ))
      ..loadHtmlString(
        '<!doctype html><html><head><meta name="viewport" '
        'content="width=device-width,initial-scale=1">'
        '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}'
        'iframe{border:0;width:100%;height:100%}</style></head><body>'
        '<iframe src="https://www.youtube-nocookie.com/embed/$key?autoplay=1'
        '&playsinline=1&rel=0&modestbranding=1&hl=it" '
        'allow="autoplay; encrypted-media; fullscreen" allowfullscreen>'
        '</iframe></body></html>',
        baseUrl: 'https://stellartv.lovable.app',
      );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _external() async {
    try {
      await launchUrl(widget.trailer.url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _web)),
        Positioned(
          right: 16,
          top: 16,
          child: TextButton.icon(
            onPressed: _external,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Apri in YouTube'),
          ),
        ),
      ],
    ),
  );
}
