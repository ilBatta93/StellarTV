// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import androidx.annotation.Nullable;
import androidx.annotation.VisibleForTesting;
import androidx.media3.common.C;
import androidx.media3.common.Timeline;
import androidx.media3.common.util.NullableType;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.LoadControl;
import androidx.media3.exoplayer.analytics.PlayerId;
import androidx.media3.exoplayer.source.TrackGroupArray;
import androidx.media3.exoplayer.trackselection.ExoTrackSelection;
import androidx.media3.exoplayer.upstream.DefaultAllocator;

/**
 * Explicit Media3 load control. Preview and MultiView keep a short forward buffer. Film keeps a
 * wider one. A live back buffer is retained only after the current window is seekable: held TS
 * samples do not create a seekable live window, so they are not kept.
 */
@UnstableApi
public final class ExoLoadControls {
  private ExoLoadControls() {}

  public static void apply(ExoPlayer.Builder builder, VideoPlayerOptions options) {
    LoadControl control = create(options);
    if (control != null) {
      builder.setLoadControl(control);
    }
  }

  @Nullable
  @VisibleForTesting
  public static LoadControl create(VideoPlayerOptions options) {
    Long backRaw = options.backBufferDurationMs;
    if (backRaw != null && backRaw < 0) {
      throw new IllegalArgumentException("backBufferDurationMs must be at least 0");
    }
    int back = clampMs(backRaw);
    if (options.minBufferMs == null) {
      if (back <= 0) {
        return null;
      }
      return new DefaultLoadControl.Builder().setBackBuffer(back, true).build();
    }
    int min = clampMs(options.minBufferMs);
    int max = Math.max(min, clampMs(options.maxBufferMs));
    int playback = Math.min(min, clampMs(options.bufferForPlaybackMs));
    int rebuffer = Math.min(min, clampMs(options.bufferForPlaybackAfterRebufferMs));
    int target = clampBytes(options.targetBufferBytes);
    boolean prioritize = target > 0;
    if (options.backBufferRequiresSeekable && back > 0) {
      return new SeekAwareLoadControl(min, max, playback, rebuffer, back, target, prioritize);
    }
    DefaultLoadControl.Builder builder =
        new DefaultLoadControl.Builder()
            .setBufferDurationsMs(min, max, playback, rebuffer)
            .setBackBuffer(back, true);
    if (prioritize) {
      builder.setTargetBufferBytes(target).setPrioritizeTimeOverSizeThresholds(true);
    }
    return builder.build();
  }

  private static int clampMs(@Nullable Long value) {
    if (value == null || value <= 0) {
      return 0;
    }
    return (int) Math.min(value, 120_000L);
  }

  private static int clampBytes(@Nullable Long value) {
    if (value == null || value <= 0) {
      return 0;
    }
    return (int) Math.min(value, Integer.MAX_VALUE);
  }

  /**
   * Same forward buffer as {@link DefaultLoadControl}, but the configured back buffer stays at
   * zero until a load callback reports a seekable window.
   */
  static final class SeekAwareLoadControl extends DefaultLoadControl {
    private final Timeline.Window window = new Timeline.Window();
    private final Timeline.Period period = new Timeline.Period();
    private volatile boolean seekable;

    SeekAwareLoadControl(
        int minBufferMs,
        int maxBufferMs,
        int bufferForPlaybackMs,
        int bufferForPlaybackAfterRebufferMs,
        int backBufferDurationMs,
        int targetBufferBytes,
        boolean prioritizeTimeOverSizeThresholds) {
      super(
          new DefaultAllocator(/* trimOnReset= */ true, C.DEFAULT_BUFFER_SEGMENT_SIZE),
          minBufferMs,
          minBufferMs,
          maxBufferMs,
          maxBufferMs,
          bufferForPlaybackMs,
          bufferForPlaybackMs,
          bufferForPlaybackAfterRebufferMs,
          bufferForPlaybackAfterRebufferMs,
          targetBufferBytes > 0 ? targetBufferBytes : C.LENGTH_UNSET,
          prioritizeTimeOverSizeThresholds,
          prioritizeTimeOverSizeThresholds,
          backBufferDurationMs,
          /* retainBackBufferFromKeyframe= */ true);
    }

    @Override
    public long getBackBufferDurationUs(PlayerId playerId) {
      if (!seekable) {
        return 0;
      }
      return super.getBackBufferDurationUs(playerId);
    }

    @Override
    public boolean shouldContinueLoading(Parameters parameters) {
      remember(parameters);
      return super.shouldContinueLoading(parameters);
    }

    @Override
    public boolean shouldStartPlayback(Parameters parameters) {
      remember(parameters);
      return super.shouldStartPlayback(parameters);
    }

    @Override
    public void onTracksSelected(
        Parameters parameters,
        TrackGroupArray trackGroups,
        @NullableType ExoTrackSelection[] trackSelections) {
      remember(parameters);
      super.onTracksSelected(parameters, trackGroups, trackSelections);
    }

    @VisibleForTesting
    void setWindowSeekableForTest(boolean value) {
      seekable = value;
    }

    private void remember(Parameters parameters) {
      Timeline timeline = parameters.timeline;
      if (timeline == null || timeline.isEmpty()) {
        seekable = false;
        return;
      }
      try {
        Object uid = parameters.mediaPeriodId.periodUid;
        int windowIndex = timeline.getPeriodByUid(uid, period).windowIndex;
        seekable = timeline.getWindow(windowIndex, window).isSeekable;
      } catch (RuntimeException error) {
        seekable = false;
      }
    }
  }
}
