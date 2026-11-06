import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/banner_trailer.dart';
import '../models/title_trailer.dart';
import '../models/tmdb_item.dart';
import '../providers/discover_provider.dart';

/// "Trailer nel banner" (TV Home): the trailer of the banner title, once
/// the remote has rested on that title for [delaySeconds]. It stays
/// invisible until the video really plays, so a slow start never shows a
/// black box, and it stops as soon as another page covers the Home.
class BannerTrailer extends StatefulWidget {
  const BannerTrailer({
    super.key,
    required this.item,
    required this.audio,
    required this.delaySeconds,
    required this.onButton,
    this.onPlaying,
  });

  final TmdbItem? item;
  final BannerTrailerAudio audio;
  final int delaySeconds;

  /// True while the remote rests on Trailer or Guarda in the banner.
  final ValueListenable<bool> onButton;

  /// The trailer started or stopped playing.
  final ValueChanged<bool>? onPlaying;

  /// Test seam: replaces the TMDB trailer lookup.
  @visibleForTesting
  static Future<TitleTrailer?> Function(BuildContext, TmdbItem)? lookup;

  /// Muted YouTube page with a sound fade the banner drives.
  @visibleForTesting
  static String html(String key) =>
      '''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{width:100%;height:100%}</style>
</head><body><div id="p"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var player,fade;
function send(s){try{Trailer.postMessage(s)}catch(e){}}
function onYouTubeIframeAPIReady(){
  player=new YT.Player('p',{host:'https://www.youtube-nocookie.com',videoId:'$key',
    playerVars:{autoplay:1,mute:1,controls:0,rel:0,modestbranding:1,playsinline:1,hl:'it',fs:0,iv_load_policy:3,cc_load_policy:0,disablekb:1},
    events:{
      onReady:function(e){e.target.mute();e.target.playVideo();},
      onStateChange:function(e){if(e.data==1)send('playing');else if(e.data==0)send('ended');},
      onError:function(e){send('error');}
    }});
}
function audio(on){if(!player)return;try{clearInterval(fade);
  if(!on){player.mute();return;}
  var v=0;player.setVolume(0);player.unMute();
  fade=setInterval(function(){v+=8;player.setVolume(Math.min(v,100));if(v>=100)clearInterval(fade)},90);
}catch(e){}}
</script></body></html>''';

  @override
  State<BannerTrailer> createState() => _BannerTrailerState();
}

class _BannerTrailerState extends State<BannerTrailer> {
  Timer? _start;
  Timer? _sound;
  WebViewController? _web;
  String? _for;
  bool _playing = false;
  DateTime? _since;
  bool? _audible;
  ValueListenable<TickerModeData>? _visible;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.onButton.addListener(_applyAudio);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.getValuesNotifier(context);
    if (!identical(visible, _visible)) {
      _visible?.removeListener(_visibilityChanged);
      _visible = visible..addListener(_visibilityChanged);
    }
    _follow();
  }

  @override
  void didUpdateWidget(covariant BannerTrailer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.onButton, widget.onButton)) {
      oldWidget.onButton.removeListener(_applyAudio);
      widget.onButton.addListener(_applyAudio);
    }
    if (oldWidget.delaySeconds != widget.delaySeconds) _for = null;
    _follow();
    if (oldWidget.audio != widget.audio) _applyAudio();
  }

  /// Another page covers the Home: stop at once, start again on return.
  void _visibilityChanged() {
    _for = null;
    _stop();
    _follow();
  }

  void _follow() {
    final item = widget.item;
    final visible = _visible?.value.enabled ?? true;
    final key = visible ? item?.key : null;
    if (key == _for) return;
    _for = key;
    _stop();
    if (item == null || key == null) return;
    final generation = _generation;
    _start = Timer(Duration(seconds: widget.delaySeconds), () {
      _load(item, generation);
    });
  }

  Future<void> _load(TmdbItem item, int generation) async {
    TitleTrailer? trailer;
    try {
      final lookup = BannerTrailer.lookup;
      trailer = lookup != null
          ? await lookup(context, item)
          : await context.read<DiscoverProvider>().tmdb.trailer(item);
    } catch (_) {
      return;
    }
    if (!mounted || generation != _generation || trailer == null) return;
    final web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('Trailer', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (r) =>
              r.url.contains('youtube') ||
                  r.url.contains('ytimg') ||
                  r.url.startsWith('about:') ||
                  r.url.startsWith('https://stellartv.vercel.app')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
    final platform = web.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    web.loadHtmlString(
      BannerTrailer.html(trailer.key),
      baseUrl: 'https://stellartv.vercel.app',
    );
    setState(() => _web = web);
  }

  void _onMessage(JavaScriptMessage message) {
    if (!mounted) return;
    switch (message.message) {
      case 'playing':
        if (_playing) return;
        setState(() {
          _playing = true;
          _since = DateTime.now();
        });
        widget.onPlaying?.call(true);
        _audible = null;
        _applyAudio();
        if (widget.audio == BannerTrailerAudio.delayed) {
          _sound = Timer(
            const Duration(seconds: bannerAudioDelaySeconds),
            _applyAudio,
          );
        }
      case 'ended':
      case 'error':
        // Back to the still; the same title does not start again.
        _stop();
    }
  }

  void _applyAudio() {
    final web = _web;
    final since = _since;
    if (web == null || !_playing || since == null) return;
    final audible = bannerTrailerAudible(
      audio: widget.audio,
      playedFor: DateTime.now().difference(since),
      onButton: widget.onButton.value,
    );
    if (audible == _audible) return;
    _audible = audible;
    web.runJavaScript('audio($audible)').catchError((_) {});
  }

  /// Releases the web player and its video decoder at once.
  void _stop() {
    _generation++;
    _start?.cancel();
    _sound?.cancel();
    final web = _web;
    final wasPlaying = _playing;
    _web = null;
    _playing = false;
    _since = null;
    _audible = null;
    if (web != null) {
      web
          .runJavaScript(
            'try{player&&player.stopVideo();player&&player.destroy()}catch(e){}',
          )
          .catchError((_) {})
          .whenComplete(
            () => web.loadRequest(Uri.parse('about:blank')).catchError((_) {}),
          );
    }
    if (wasPlaying) widget.onPlaying?.call(false);
    if (mounted && web != null) setState(() {});
  }

  @override
  void dispose() {
    widget.onButton.removeListener(_applyAudio);
    _visible?.removeListener(_visibilityChanged);
    final playing = _playing;
    _playing = false;
    _stop();
    if (playing) widget.onPlaying?.call(false);
    super.dispose();
  }

  Widget _webView(WebViewController web) {
    if (web.platform is AndroidWebViewController) {
      return WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: web.platform,
          displayWithHybridComposition: true,
        ),
      );
    }
    return WebViewWidget(controller: web);
  }

  @override
  Widget build(BuildContext context) {
    final web = _web;
    if (web == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeFocus(
        child: AnimatedOpacity(
          opacity: _playing ? 1 : 0,
          duration: const Duration(milliseconds: 450),
          child: _webView(web),
        ),
      ),
    );
  }
}

/// "Finestra sfumata": the panel trailer has no frame, its edges fade into
/// the banner. Gradients are drawn over the video (a platform view cannot
/// be masked), darkest at the border.
class FeatheredTrailerWindow extends StatelessWidget {
  const FeatheredTrailerWindow({super.key, required this.child});

  final Widget child;

  static const _edge = Color(0xF0000000);

  @override
  Widget build(BuildContext context) {
    Widget fade(Alignment begin, Alignment end) => IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: begin,
            end: end,
            colors: const [_edge, Color(0x00000000)],
            stops: const [0, 1],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.maxWidth * 0.14;
        final top = box.maxHeight * 0.16;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: side,
              child: fade(Alignment.centerLeft, Alignment.centerRight),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: side,
              child: fade(Alignment.centerRight, Alignment.centerLeft),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: top,
              child: fade(Alignment.topCenter, Alignment.bottomCenter),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: top,
              child: fade(Alignment.bottomCenter, Alignment.topCenter),
            ),
          ],
        );
      },
    );
  }
}
