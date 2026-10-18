// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.annotation.VisibleForTesting;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.hls.DefaultHlsExtractorFactory;
import androidx.media3.exoplayer.hls.HlsMediaSource;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy;
import androidx.media3.exoplayer.source.MediaSource;
import androidx.media3.extractor.DefaultExtractorsFactory;
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory;
import androidx.media3.extractor.ts.TsExtractor;
import java.util.Map;

final class HttpVideoAsset extends VideoAsset {
  @NonNull private final StreamingFormat streamingFormat;
  @NonNull private final Map<String, String> httpHeaders;
  @Nullable private final String userAgent;

  HttpVideoAsset(
      @Nullable String assetUrl,
      @NonNull StreamingFormat streamingFormat,
      @NonNull Map<String, String> httpHeaders,
      @Nullable String userAgent) {
    super(assetUrl);
    this.streamingFormat = streamingFormat;
    this.httpHeaders = httpHeaders;
    this.userAgent = userAgent;
  }

  @NonNull
  @Override
  public MediaItem getMediaItem() {
    MediaItem.Builder builder = new MediaItem.Builder().setUri(assetUrl);
    String mimeType = null;
    switch (streamingFormat) {
      case SMOOTH:
        mimeType = MimeTypes.APPLICATION_SS;
        break;
      case DYNAMIC_ADAPTIVE:
        mimeType = MimeTypes.APPLICATION_MPD;
        break;
      case HTTP_LIVE:
        mimeType = MimeTypes.APPLICATION_M3U8;
        break;
    }
    if (mimeType != null) {
      builder.setMimeType(mimeType);
    }
    return builder.build();
  }

  @NonNull
  @Override
  public MediaSource.Factory getMediaSourceFactory(@NonNull Context context) {
    return getMediaSourceFactory(context, new DefaultHttpDataSource.Factory());
  }

  /**
   * Returns a configured media source factory, starting at the provided factory.
   *
   * <p>This method is provided for ease of testing without making real HTTP calls.
   *
   * @param context application context.
   * @param initialFactory initial factory, to be configured.
   * @return configured factory, or {@code null} if not needed for this asset type.
   */
  @VisibleForTesting
  @OptIn(markerClass = UnstableApi.class)
  MediaSource.Factory getMediaSourceFactory(
      Context context, DefaultHttpDataSource.Factory initialFactory) {
    unstableUpdateDataSourceFactory(initialFactory, httpHeaders, userAgent);
    DataSource.Factory dataSourceFactory = new DefaultDataSource.Factory(context, initialFactory);
    // Transient IPTV hiccups (a slow segment, a dropped socket) are retried in place instead of
    // surfacing as a fatal error that makes the app tear the player down and reconnect.
    DefaultLoadErrorHandlingPolicy retries = new DefaultLoadErrorHandlingPolicy(LOAD_RETRIES);
    if (streamingFormat == StreamingFormat.HTTP_LIVE) {
      return broadcastTolerantHls(dataSourceFactory).setLoadErrorHandlingPolicy(retries);
    }
    return new DefaultMediaSourceFactory(context, broadcastTolerantExtractors())
        .setDataSourceFactory(dataSourceFactory)
        .setLoadErrorHandlingPolicy(retries);
  }

  private static final int LOAD_RETRIES = 6;

  /**
   * HLS segments are parsed by the HLS extractor, not the progressive one: without these flags a
   * broadcast H.264 stream whose segments do not start with an IDR frame was "ready" but never
   * drew a picture (Xtream live HLS with 10-11 s segments).
   */
  @OptIn(markerClass = UnstableApi.class)
  private static HlsMediaSource.Factory broadcastTolerantHls(DataSource.Factory dataSourceFactory) {
    return new HlsMediaSource.Factory(dataSourceFactory)
        .setExtractorFactory(
            new DefaultHlsExtractorFactory(
                DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES
                    | DefaultTsPayloadReaderFactory.FLAG_DETECT_ACCESS_UNITS,
                true))
        // Prepare from the first real segment, not from the playlist CODECS
        // attribute: restreamed Xtream channels declared codecs that did not
        // match the segments, so the player was "ready" in ~0.4 s and then
        // stayed black. Real-media preparation also proves the server is
        // actually sending the channel before the picture is promised.
        .setAllowChunklessPreparation(false);
  }

  /**
   * IPTV MPEG-TS streams carry broadcast timestamp jumps, missing IDR frames and corrupted
   * packets: detect access units and accept non-IDR keyframes so playback resynchronises
   * instead of stalling, and search further for timestamps on noisy streams.
   */
  @OptIn(markerClass = UnstableApi.class)
  private static DefaultExtractorsFactory broadcastTolerantExtractors() {
    return new DefaultExtractorsFactory()
        .setTsExtractorFlags(
            DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES
                | DefaultTsPayloadReaderFactory.FLAG_DETECT_ACCESS_UNITS)
        .setTsExtractorMode(TsExtractor.MODE_SINGLE_PMT)
        .setTsExtractorTimestampSearchBytes(TsExtractor.DEFAULT_TIMESTAMP_SEARCH_BYTES * 3);
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @OptIn(markerClass = UnstableApi.class)
  private static void unstableUpdateDataSourceFactory(
      @NonNull DefaultHttpDataSource.Factory factory,
      @NonNull Map<String, String> httpHeaders,
      @Nullable String userAgent) {
    factory.setUserAgent(userAgent).setAllowCrossProtocolRedirects(true);
    // IPTV servers often answer slowly under load: the 8 s default gave up on valid channels.
    factory.setConnectTimeoutMs(12_000);
    factory.setReadTimeoutMs(15_000);
    if (!httpHeaders.isEmpty()) {
      factory.setDefaultRequestProperties(httpHeaders);
    }
  }
}
