import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/title_trailer.dart';
import '../widgets/tv_focusable.dart';

/// Plays the trailer inside StellarTV so the remote Back key always returns
/// to the title page. The web page never receives the remote's focus (a TV
/// remote cannot click inside an iframe): Flutter draws focusable controls
/// and drives the YouTube player through its JavaScript API.
class TrailerScreen extends StatefulWidget {
  const TrailerScreen({super.key, required this.trailer});
  final TitleTrailer trailer;
  @override
  State<TrailerScreen> createState() => _TrailerScreenState();
}

/// Player states reported by the YouTube IFrame API.
enum TrailerState { loading, playing, paused, ended, error }

class _TrailerScreenState extends State<TrailerScreen> {
  late final WebViewController _web;
  final _playFocus = FocusNode(debugLabel: 'trailer-play');
  TrailerState _state = TrailerState.loading;
  bool _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final key = widget.trailer.key; // validated: 11 safe characters
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('Trailer', onMessageReceived: _onMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) => r.url.contains('youtube') ||
                r.url.contains('ytimg') ||
                r.url.startsWith('about:') ||
                r.url.startsWith('https://stellartv.lovable.app')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ));
    final platform = _web.platform;
    if (platform is AndroidWebViewController) {
      // Play/pause come from the remote through Flutter, never from a tap
      // inside the page: allow the API to start the video.
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    _web.loadHtmlString(trailerHtml(key), baseUrl: 'https://stellartv.lovable.app');
    _scheduleHide();
  }

  /// YouTube IFrame API page: the player reports its state to Flutter and
  /// exposes play/pause/seek for the on-screen controls.
  @visibleForTesting
  static String trailerHtml(String key) => '''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{width:100%;height:100%}</style>
</head><body><div id="p"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var player;
function send(s){try{Trailer.postMessage(s)}catch(e){}}
function onYouTubeIframeAPIReady(){
  player=new YT.Player('p',{host:'https://www.youtube-nocookie.com',videoId:'$key',
    playerVars:{autoplay:1,controls:0,rel:0,modestbranding:1,playsinline:1,hl:'it',fs:0,iv_load_policy:3},
    events:{
      onReady:function(e){e.target.playVideo();},
      onStateChange:function(e){
        if(e.data==1)send('playing');else if(e.data==2)send('paused');else if(e.data==0)send('ended');},
      onError:function(e){send('error');}
    }});
}
function toggle(){if(!player)return;var s=player.getPlayerState();if(s==1){player.pauseVideo()}else{player.playVideo()}}
function seekBy(d){if(!player)return;player.seekTo(Math.max(0,player.getCurrentTime()+d),true)}
</script></body></html>''';

  void _onMessage(JavaScriptMessage message) {
    final next = switch (message.message) {
      'playing' => TrailerState.playing,
      'paused' => TrailerState.paused,
      'ended' => TrailerState.ended,
      'error' => TrailerState.error,
      _ => _state,
    };
    if (!mounted || next == _state) return;
    setState(() => _state = next);
    if (next == TrailerState.playing) {
      _scheduleHide();
    } else {
      _show();
    }
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted && _state == TrailerState.playing) {
        setState(() => _controls = false);
      }
    });
  }

  void _show() {
    _hide?.cancel();
    if (!_controls) setState(() => _controls = true);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _playFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _run(String js) async {
    try {
      await _web.runJavaScript(js);
    } catch (_) {}
  }

  void _toggle() {
    _run(_state == TrailerState.ended
        ? 'player&&(player.seekTo(0,true),player.playVideo())'
        : 'toggle()');
    _show();
  }

  void _seek(int seconds) {
    _run('seekBy(${jsonEncode(seconds)})');
    _show();
  }

  Future<void> _external() async {
    try {
      await launchUrl(widget.trailer.url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Hidden controls: the first key only brings them back, so the remote
  /// never acts on something the viewer cannot see.
  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      _toggle();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaFastForward) {
      _seek(10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaRewind) {
      _seek(-10);
      return KeyEventResult.handled;
    }
    if (!_controls && key != LogicalKeyboardKey.goBack && key != LogicalKeyboardKey.escape) {
      _show();
      _playFocus.requestFocus();
      return KeyEventResult.handled;
    }
    _scheduleHide();
    return KeyEventResult.ignored;
  }

  Widget _button({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    FocusNode? focusNode,
    bool autofocus = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(24),
      child: Material(
        color: scheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onPressed,
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 22, color: scheme.onSurface),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: scheme.onSurface, fontSize: 15)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playing = _state == TrailerState.playing;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            // The web page must never take the remote's focus.
            Positioned.fill(
              child: ExcludeFocus(child: WebViewWidget(controller: _web)),
            ),
            if (_state == TrailerState.loading)
              const Center(child: CircularProgressIndicator()),
            if (_state == TrailerState.error)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Questo trailer non può essere riprodotto nell\'app.\n'
                    'Usa «Apri in YouTube».',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: _controls ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_controls,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 28),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    child: FocusTraversalGroup(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _button(
                            icon: Icons.replay_10,
                            label: '-10 s',
                            onPressed: () => _seek(-10),
                          ),
                          _button(
                            focusNode: _playFocus,
                            autofocus: true,
                            icon: playing ? Icons.pause : Icons.play_arrow,
                            label: playing
                                ? 'Pausa'
                                : _state == TrailerState.ended
                                ? 'Riguarda'
                                : 'Riproduci',
                            onPressed: _toggle,
                          ),
                          _button(
                            icon: Icons.forward_10,
                            label: '+10 s',
                            onPressed: () => _seek(10),
                          ),
                          _button(
                            icon: Icons.open_in_new,
                            label: 'Apri in YouTube',
                            onPressed: _external,
                          ),
                          _button(
                            icon: Icons.close,
                            label: 'Chiudi',
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
