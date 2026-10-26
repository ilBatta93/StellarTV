// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.content.Context;
import android.util.LongSparseArray;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.media3.common.util.UnstableApi;
import io.flutter.FlutterInjector;
import io.flutter.Log;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugins.videoplayer.platformview.PlatformVideoViewFactory;
import io.flutter.plugins.videoplayer.platformview.PlatformViewVideoPlayer;
import io.flutter.plugins.videoplayer.texture.TextureVideoPlayer;
import io.flutter.view.TextureRegistry;

/** Android platform implementation of the VideoPlayerPlugin. */
public class VideoPlayerPlugin implements FlutterPlugin, AndroidVideoPlayerApi {
  private static final String TAG = "VideoPlayerPlugin";
  private final LongSparseArray<VideoPlayer> videoPlayers = new LongSparseArray<>();
  private FlutterState flutterState;
  private final VideoPlayerOptions sharedOptions = new VideoPlayerOptions();
  private long nextPlayerIdentifier = 1;

  /** Register this with the v2 embedding for the plugin to respond to lifecycle callbacks. */
  public VideoPlayerPlugin() {}

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    final FlutterInjector injector = FlutterInjector.instance();
    this.flutterState =
        new FlutterState(
            binding.getApplicationContext(),
            binding.getBinaryMessenger(),
            injector.flutterLoader()::getLookupKeyForAsset,
            injector.flutterLoader()::getLookupKeyForAsset,
            binding.getTextureRegistry());
    flutterState.startListening(this, binding.getBinaryMessenger());

    binding
        .getPlatformViewRegistry()
        .registerViewFactory(
            "plugins.flutter.dev/video_player_android",
            new PlatformVideoViewFactory(videoPlayers::get));
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    if (flutterState == null) {
      Log.wtf(TAG, "Detached from the engine before registering to it.");
    }
    flutterState.stopListening(binding.getBinaryMessenger());
    flutterState = null;
    onDestroy();
  }

  private void disposeAllPlayers() {
    for (int i = 0; i < videoPlayers.size(); i++) {
      videoPlayers.valueAt(i).dispose();
    }
    videoPlayers.clear();
  }

  public void onDestroy() {
    // The whole FlutterView is being destroyed. Here we release resources acquired for all
    // instances
    // of VideoPlayer. Once https://github.com/flutter/flutter/issues/19358 is resolved this may
    // be replaced with just asserting that videoPlayers.isEmpty().
    // https://github.com/flutter/flutter/issues/20989 tracks this.
    disposeAllPlayers();
  }

  @Override
  public void initialize() {
    disposeAllPlayers();
  }

  @OptIn(markerClass = UnstableApi.class)
  @Override
  public long createForPlatformView(@NonNull CreationOptions options) {
    final VideoAsset videoAsset = videoAssetWithOptions(options);

    long id = nextPlayerIdentifier++;
    final String streamInstance = Long.toString(id);
    VideoPlayerOptions playerOptions = new VideoPlayerOptions(sharedOptions);
    copyLoadControl(playerOptions, options);

    VideoPlayer videoPlayer =
        PlatformViewVideoPlayer.create(
            flutterState.applicationContext,
            VideoPlayerEventCallbacks.bindTo(flutterState.binaryMessenger, streamInstance),
            videoAsset,
            playerOptions);

    registerPlayerInstance(videoPlayer, id);
    return id;
  }

  @OptIn(markerClass = UnstableApi.class)
  @Override
  public @NonNull TexturePlayerIds createForTextureView(@NonNull CreationOptions options) {
    final VideoAsset videoAsset = videoAssetWithOptions(options);

    long id = nextPlayerIdentifier++;
    final String streamInstance = Long.toString(id);
    TextureRegistry.SurfaceProducer handle = flutterState.textureRegistry.createSurfaceProducer();
    VideoPlayerOptions playerOptions = new VideoPlayerOptions(sharedOptions);
    copyLoadControl(playerOptions, options);

    VideoPlayer videoPlayer =
        TextureVideoPlayer.create(
            flutterState.applicationContext,
            VideoPlayerEventCallbacks.bindTo(flutterState.binaryMessenger, streamInstance),
            handle,
            videoAsset,
            playerOptions);

    registerPlayerInstance(videoPlayer, id);
    return new TexturePlayerIds(id, handle.id());
  }

  private static void copyLoadControl(
      @NonNull VideoPlayerOptions playerOptions, @NonNull CreationOptions options) {
    playerOptions.backBufferDurationMs = options.getBackBufferDurationMs();
    playerOptions.minBufferMs = options.getMinBufferMs();
    playerOptions.maxBufferMs = options.getMaxBufferMs();
    playerOptions.bufferForPlaybackMs = options.getBufferForPlaybackMs();
    playerOptions.bufferForPlaybackAfterRebufferMs =
        options.getBufferForPlaybackAfterRebufferMs();
    playerOptions.backBufferRequiresSeekable =
        Boolean.TRUE.equals(options.getBackBufferRequiresSeekable());
    playerOptions.targetBufferBytes = options.getTargetBufferBytes();
  }

  private static @NonNull Map<String, String> headersWithoutLoadControl(
      @NonNull Map<String, String> headers) {
    if (headers.isEmpty()) {
      return headers;
    }
    Map<String, String> copy = new HashMap<>();
    for (Map.Entry<String, String> entry : headers.entrySet()) {
      if (!"x-stellartv-loadcontrol".equals(entry.getKey().toLowerCase(Locale.US))) {
        copy.put(entry.getKey(), entry.getValue());
      }
    }
    return copy;
  }

  private @NonNull VideoAsset videoAssetWithOptions(@NonNull CreationOptions options) {
    final @NonNull String uri = options.getUri();
    if (uri.startsWith("asset:")) {
      return VideoAsset.fromAssetUrl(uri);
    } else if (uri.startsWith("rtsp:")) {
      return VideoAsset.fromRtspUrl(uri);
    } else {
      VideoAsset.StreamingFormat streamingFormat = VideoAsset.StreamingFormat.UNKNOWN;
      PlatformVideoFormat formatHint = options.getFormatHint();
      if (formatHint != null) {
        switch (formatHint) {
          case SS:
            streamingFormat = VideoAsset.StreamingFormat.SMOOTH;
            break;
          case DASH:
            streamingFormat = VideoAsset.StreamingFormat.DYNAMIC_ADAPTIVE;
            break;
          case HLS:
            streamingFormat = VideoAsset.StreamingFormat.HTTP_LIVE;
            break;
        }
      }
      return VideoAsset.fromRemoteUrl(
          uri,
          streamingFormat,
          headersWithoutLoadControl(options.getHttpHeaders()),
          options.getUserAgent());
    }
  }

  @OptIn(markerClass = UnstableApi.class)
  private void registerPlayerInstance(VideoPlayer player, long id) {
    // Set up the instance-specific API handler, and make sure it is removed when the player is
    // disposed.
    BinaryMessenger messenger = flutterState.binaryMessenger;
    final String channelSuffix = Long.toString(id);
    VideoPlayerInstanceApi.Companion.setUp(messenger, player, channelSuffix);
    final io.flutter.plugin.common.MethodChannel channel = new io.flutter.plugin.common.MethodChannel(messenger, "stellartv/video_player_android/live/" + channelSuffix);
    channel.setMethodCallHandler((call, result) -> {
      try {
        switch (call.method) {
          case "seekWithinLiveWindow":
            Number position = call.argument("positionMs");
            if (position == null) { result.error("invalid_position", "Missing position", null); break; }
            result.success(player.seekWithinLiveWindow(position.longValue())); break;
          case "getLiveWindow": result.success(player.getLiveWindow()); break;
          case "seekToDefaultLivePosition": result.success(player.seekToDefaultLivePosition()); break;
          default: result.notImplemented();
        }
      } catch (RuntimeException error) { result.error("live_player_error", error.getMessage(), null); }
    });
    player.setDisposeHandler(() -> {
      channel.setMethodCallHandler(null);
      VideoPlayerInstanceApi.Companion.setUp(messenger, null, channelSuffix);
    });

    videoPlayers.put(id, player);
  }

  @NonNull
  private VideoPlayer getPlayer(long playerId) {
    VideoPlayer player = videoPlayers.get(playerId);

    // Avoid a very ugly un-debuggable NPE that results in returning a null player.
    if (player == null) {
      String message = "No player found with playerId <" + playerId + ">";
      if (videoPlayers.size() == 0) {
        message += " and no active players created by the plugin.";
      }
      throw new IllegalStateException(message);
    }

    return player;
  }

  @Override
  public void dispose(long playerId) {
    VideoPlayer player = getPlayer(playerId);
    player.dispose();
    videoPlayers.remove(playerId);
  }

  @Override
  public void setMixWithOthers(boolean mixWithOthers) {
    sharedOptions.mixWithOthers = mixWithOthers;
  }

  @Override
  public @NonNull String getLookupKeyForAsset(@NonNull String asset, @Nullable String packageName) {
    return packageName == null
        ? flutterState.keyForAsset.get(asset)
        : flutterState.keyForAssetAndPackageName.get(asset, packageName);
  }

  private interface KeyForAssetFn {
    String get(String asset);
  }

  private interface KeyForAssetAndPackageName {
    String get(String asset, String packageName);
  }

  private static final class FlutterState {
    final Context applicationContext;
    final BinaryMessenger binaryMessenger;
    final KeyForAssetFn keyForAsset;
    final KeyForAssetAndPackageName keyForAssetAndPackageName;
    final TextureRegistry textureRegistry;

    FlutterState(
        Context applicationContext,
        BinaryMessenger messenger,
        KeyForAssetFn keyForAsset,
        KeyForAssetAndPackageName keyForAssetAndPackageName,
        TextureRegistry textureRegistry) {
      this.applicationContext = applicationContext;
      this.binaryMessenger = messenger;
      this.keyForAsset = keyForAsset;
      this.keyForAssetAndPackageName = keyForAssetAndPackageName;
      this.textureRegistry = textureRegistry;
    }

    void startListening(VideoPlayerPlugin methodCallHandler, BinaryMessenger messenger) {
      AndroidVideoPlayerApi.Companion.setUp(messenger, methodCallHandler);
    }

    void stopListening(BinaryMessenger messenger) {
      AndroidVideoPlayerApi.Companion.setUp(messenger, null);
    }
  }
}
