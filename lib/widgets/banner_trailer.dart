import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/banner_trailer.dart';
import '../models/title_trailer.dart';
import '../models/tmdb_item.dart';
import '../providers/discover_provider.dart';
import '../services/image_warmup_service.dart';

/// Trailer of the TV Home: the trailer of [item], once the remote has
/// rested on that title for [delaySeconds].
///
/// One web player serves every title while the Home lives: a new title
/// swaps the video inside the same page. On Fire TV only the first web
/// player of a page gets a working video surface, so a player per title
/// played once and then stayed black. The player is never hidden by
/// removing it from the screen either (that drops its surface): whoever
/// places it draws the still picture over it and fades the picture out
/// while [onPlaying] reports true.
class BannerTrailer extends StatefulWidget {
  const BannerTrailer({
    super.key,
    required this.item,
    required this.audio,
    required this.delaySeconds,
    required this.onButton,
    this.onPlaying,
    this.cover = false,
  });

  final TmdbItem? item;
  final BannerTrailerAudio audio;
  final int delaySeconds;

  /// True while the remote rests on Trailer or Guarda in the banner.
  final ValueListenable<bool> onButton;

  /// The trailer of the current title started or stopped playing.
  final ValueChanged<bool>? onPlaying;

  /// Fill the box, cropping the video (background), instead of fitting it.
  final bool cover;

  /// Test seam: replaces the TMDB trailer lookup.
  @visibleForTesting
  static Future<TitleTrailer?> Function(BuildContext, TmdbItem)? lookup;

  /// Test seam: replaces the web player.
  @visibleForTesting
  static TrailerPage Function(void Function(String message) onMessage)?
  pageFactory;

  /// One muted YouTube page for every title: `play(id, token)` swaps the
  /// video, `stop()` halts it, `release()` frees the video decoder, and
  /// messages carry the token so a late event of an earlier title is
  /// ignored.
  @visibleForTesting
  static String html({required bool cover}) =>
      '''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
#box{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%)}
#box iframe,#p{width:100%;height:100%;border:0}</style>
</head><body><div id="box"><div id="p"></div></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var player=null,fade,cur=0,want=null,api=false,cover=${cover ? 1 : 0};
function send(s){try{Trailer.postMessage(s)}catch(e){}}
function fit(){var W=innerWidth,H=innerHeight,w=W,h=W*9/16;
  if(cover?h<H:h>H){h=H;w=H*16/9;}
  var b=document.getElementById('box');b.style.width=w+'px';b.style.height=h+'px';}
addEventListener('resize',fit);fit();
function make(){if(!api||player||!want)return;
  player=new YT.Player('p',{host:'https://www.youtube-nocookie.com',videoId:want,
    playerVars:{autoplay:1,mute:1,controls:0,rel:0,modestbranding:1,playsinline:1,hl:'it',fs:0,iv_load_policy:3,cc_load_policy:0,disablekb:1},
    events:{
      onReady:function(e){e.target.mute();if(cur)e.target.playVideo();},
      onStateChange:function(e){if(!cur)return;if(e.data==1)send('playing:'+cur);else if(e.data==0)send('ended:'+cur);},
      onError:function(e){if(cur)send('error:'+cur);}
    }});}
function onYouTubeIframeAPIReady(){api=true;send('ready');make();}
function play(id,t){cur=t;want=id;try{clearInterval(fade);
  if(player&&player.loadVideoById){player.mute();player.loadVideoById({videoId:id});}else make();
}catch(e){send('error:'+t);}}
function stop(){cur=0;try{clearInterval(fade);if(player&&player.stopVideo){player.mute();player.stopVideo();}}catch(e){}}
function release(){cur=0;want=null;try{clearInterval(fade);if(player)player.destroy();}catch(e){}
  player=null;if(!document.getElementById('p')){var d=document.createElement('div');d.id='p';document.getElementById('box').appendChild(d);}}
function audio(on,step){if(!player)return;try{clearInterval(fade);
  if(!on){player.mute();return;}
  var v=0;player.setVolume(0);player.unMute();
  fade=setInterval(function(){v+=step||8;player.setVolume(Math.min(v,100));if(v>=100)clearInterval(fade)},90);
}catch(e){}}
</script></body></html>''';

  @override
  State<BannerTrailer> createState() => _BannerTrailerState();
}

/// The web page behind [BannerTrailer]; replaced in tests.
abstract class TrailerPage {
  /// Runs a script of [BannerTrailer.html].
  void run(String script);

  /// Frees the page and its renderer.
  void dispose();

  Widget build();
}

class _WebTrailerPage implements TrailerPage {
  _WebTrailerPage(void Function(String) onMessage, {required bool cover})
    : web = WebViewController() {
    web
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'Trailer',
        onMessageReceived: (m) => onMessage(m.message),
      )
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
      BannerTrailer.html(cover: cover),
      baseUrl: 'https://stellartv.vercel.app',
    );
  }

  final WebViewController web;

  @override
  void run(String script) => web.runJavaScript(script).catchError((_) {});

  @override
  void dispose() {
    web
        .runJavaScript('release()')
        .catchError((_) {})
        .whenComplete(
          () => web.loadRequest(Uri.parse('about:blank')).catchError((_) {}),
        );
  }

  @override
  Widget build() {
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
}

class _BannerTrailerState extends State<BannerTrailer> {
  Timer? _start;
  Timer? _sound;
  Timer? _watchdog;
  TrailerPage? _page;
  bool _ready = false;

  /// Title followed (null when none or the Home is covered).
  String? _for;

  /// Current request: messages with another token are stale.
  int _token = 0;

  /// Script waiting for the page to be ready.
  String? _pending;
  bool _playing = false;
  bool _retried = false;
  DateTime? _since;
  bool? _audible;
  ValueListenable<TickerModeData>? _visible;
  int _pressure = 0;

  @override
  void initState() {
    super.initState();
    widget.onButton.addListener(_applyAudio);
    _pressure = TvImageMemoryGuard.trailerStops.value;
    TvImageMemoryGuard.trailerStops.addListener(_memoryPressure);
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
    if (oldWidget.audio != widget.audio) {
      _audible = null;
      _applyAudio();
    }
  }

  /// Another page covers the Home: the video stops and frees its decoder
  /// (the player itself stays); back on the Home the title starts again.
  void _visibilityChanged() {
    _for = null;
    _halt(release: true);
    _follow();
  }

  /// Memory pressure: stop and free the decoder now. The same title does
  /// not start over; the next one the remote rests on does.
  void _memoryPressure() {
    final stops = TvImageMemoryGuard.trailerStops.value;
    if (stops == _pressure) return;
    _pressure = stops;
    _halt(release: true);
  }

  void _follow() {
    final item = widget.item;
    final visible = _visible?.value.enabled ?? true;
    final key = visible ? item?.key : null;
    if (key == _for) return;
    _for = key;
    _halt();
    if (item == null || key == null) return;
    _retried = false;
    final token = _token;
    _start = Timer(Duration(seconds: widget.delaySeconds), () {
      _load(item, token);
    });
  }

  Future<void> _load(TmdbItem item, int token) async {
    TitleTrailer? trailer;
    try {
      final lookup = BannerTrailer.lookup;
      trailer = lookup != null
          ? await lookup(context, item)
          : await context.read<DiscoverProvider>().tmdb.trailer(item);
    } catch (_) {
      return;
    }
    if (!mounted || token != _token || trailer == null) return;
    _play(trailer.key, token);
  }

  void _play(String video, int token) {
    final page = _page ??= _newPage();
    final script = "play('$video',$token)";
    if (_ready) {
      page.run(script);
    } else {
      _pending = script;
    }
    if (mounted) setState(() {});
    _watchdog?.cancel();
    _watchdog = Timer(
      const Duration(seconds: bannerTrailerWatchdogSeconds),
      () => _stuck(video, token),
    );
  }

  /// Nothing played in time: the page or its renderer is gone. A fresh
  /// player gets one more try for the same title.
  void _stuck(String video, int token) {
    if (!mounted || token != _token || _playing) return;
    _page?.dispose();
    _page = null;
    _ready = false;
    _pending = null;
    if (_retried) {
      setState(() {});
      return;
    }
    _retried = true;
    _play(video, token);
  }

  TrailerPage _newPage() {
    final factory = BannerTrailer.pageFactory;
    return factory != null
        ? factory(_onMessage)
        : _WebTrailerPage(_onMessage, cover: widget.cover);
  }

  void _onMessage(String message) {
    if (!mounted) return;
    if (message == 'ready') {
      _ready = true;
      final pending = _pending;
      _pending = null;
      if (pending != null) _page?.run(pending);
      return;
    }
    final colon = message.indexOf(':');
    if (colon < 0) return;
    final token = int.tryParse(message.substring(colon + 1));
    if (token == null || token != _token) return;
    switch (message.substring(0, colon)) {
      case 'playing':
        _watchdog?.cancel();
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
        _halt(release: true);
    }
  }

  void _applyAudio() {
    final page = _page;
    final since = _since;
    if (page == null || !_playing || since == null) return;
    final audible = bannerTrailerAudible(
      audio: widget.audio,
      playedFor: DateTime.now().difference(since),
      onButton: widget.onButton.value,
    );
    if (audible == _audible) return;
    _audible = audible;
    page.run('audio($audible,${bannerAudioFadeStep(widget.audio)})');
  }

  /// Stops the current title. [release] also frees the video decoder,
  /// for when nothing is about to play (covered Home, memory pressure).
  void _halt({bool release = false}) {
    _token++;
    _start?.cancel();
    _sound?.cancel();
    _watchdog?.cancel();
    _pending = null;
    final wasPlaying = _playing;
    _playing = false;
    _since = null;
    _audible = null;
    _page?.run(release ? 'release()' : 'stop()');
    if (wasPlaying) {
      widget.onPlaying?.call(false);
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    widget.onButton.removeListener(_applyAudio);
    _visible?.removeListener(_visibilityChanged);
    TvImageMemoryGuard.trailerStops.removeListener(_memoryPressure);
    _start?.cancel();
    _sound?.cancel();
    _watchdog?.cancel();
    if (_playing) widget.onPlaying?.call(false);
    _playing = false;
    _page?.dispose();
    _page = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    if (page == null) return const SizedBox.expand();
    return IgnorePointer(child: ExcludeFocus(child: page.build()));
  }
}

/// "Nel riquadro a destra": a 16:9 window whose edges fade into the
/// banner. The still of the title covers the player until the trailer
/// plays, then fades away.
///
/// Everything is drawn over the player as plain Flutter layers: on Fire TV
/// the video is a separate surface that clips and masks cannot reach, but
/// layers painted above it still blend. Gradients only, no blur or
/// offscreen layer, so the weak TV GPU pays a few fills per frame.
class TrailerPanelFrame extends StatelessWidget {
  const TrailerPanelFrame({
    super.key,
    required this.player,
    required this.still,
    required this.playing,
  });

  final Widget player;
  final Widget still;
  final ValueListenable<bool> playing;

  /// Share of the width (sides) and height (top and bottom) that fades.
  static const sideFade = 0.12;
  static const edgeFade = 0.16;

  /// Colour the edges fade to: the dimmed banner behind the window.
  static const edge = Color(0xFF050507);

  @override
  Widget build(BuildContext context) {
    Widget fade(Alignment begin, Alignment end) => IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: begin,
            end: end,
            colors: const [edge, Color(0x00050507)],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.maxWidth * sideFade;
        final top = box.maxHeight * edgeFade;
        return Stack(
          fit: StackFit.expand,
          children: [
            player,
            ValueListenableBuilder<bool>(
              valueListenable: playing,
              builder: (_, on, child) => AnimatedOpacity(
                opacity: on ? 0 : 1,
                duration: const Duration(milliseconds: 500),
                child: child,
              ),
              child: still,
            ),
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

/// Where "Nell'immagine di scena" plays: the scene picture of the selected
/// cover on the Home.
class SceneTrailerSlot {
  SceneTrailerSlot(this.item, this.context);
  final TmdbItem item;
  final BuildContext context;
}

/// Given by the TV Home when the trailer plays in the selected cover.
class SceneTrailerScope extends InheritedWidget {
  const SceneTrailerScope({
    super.key,
    required this.slot,
    required this.playing,
    required super.child,
  });

  /// The open scene picture, if any.
  final ValueNotifier<SceneTrailerSlot?> slot;

  /// Key of the title whose trailer plays (its scene picture fades out).
  final ValueListenable<String?> playing;

  static SceneTrailerScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SceneTrailerScope>();

  @override
  bool updateShouldNotify(SceneTrailerScope oldWidget) =>
      slot != oldWidget.slot || playing != oldWidget.playing;
}

/// Lays the trailer player under the open scene picture, following it
/// while it grows and scrolls. It sits below the rows: the picture fades
/// out over it while the trailer plays, so badges and logo stay on top.
class SceneTrailerLayer extends StatefulWidget {
  const SceneTrailerLayer({
    super.key,
    required this.slot,
    required this.builder,
  });

  final ValueListenable<SceneTrailerSlot?> slot;

  /// The player for the title in the slot (null item: stop).
  final Widget Function(TmdbItem? item) builder;

  @override
  State<SceneTrailerLayer> createState() => _SceneTrailerLayerState();
}

class _SceneTrailerLayerState extends State<SceneTrailerLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => _track());
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    widget.slot.addListener(_slotChanged);
    _slotChanged();
  }

  @override
  void didUpdateWidget(covariant SceneTrailerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.slot, widget.slot)) {
      oldWidget.slot.removeListener(_slotChanged);
      widget.slot.addListener(_slotChanged);
      _slotChanged();
    }
  }

  void _slotChanged() {
    if (!mounted) return;
    final slot = widget.slot.value;
    if (slot == null) {
      if (_ticker.isActive) _ticker.stop();
      setState(() {});
      return;
    }
    if (!_ticker.isActive) _ticker.start();
    setState(() {});
  }

  /// Rectangle of the scene picture in this layer, zoom included.
  void _track() {
    final slot = widget.slot.value;
    final target = slot?.context.mounted == true
        ? slot!.context.findRenderObject()
        : null;
    final layer = context.findRenderObject();
    Rect? rect;
    if (target is RenderBox &&
        target.attached &&
        target.hasSize &&
        layer is RenderBox &&
        layer.attached) {
      final topLeft = target.localToGlobal(Offset.zero, ancestor: layer);
      final bottomRight = target.localToGlobal(
        target.size.bottomRight(Offset.zero),
        ancestor: layer,
      );
      rect = Rect.fromPoints(topLeft, bottomRight);
    }
    if (rect != _rect) setState(() => _rect = rect);
  }

  @override
  void dispose() {
    widget.slot.removeListener(_slotChanged);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot.value;
    final rect = _rect;
    final item = slot != null && rect != null ? slot.item : null;
    // With nothing to show the player stays a black speck in the corner
    // (under the solid banner shade) rather than leaving the screen.
    final place = item == null || rect == null
        ? const Rect.fromLTWH(0, 0, 2, 2)
        : rect;
    return Stack(
      children: [Positioned.fromRect(rect: place, child: widget.builder(item))],
    );
  }
}
