// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.os.Handler;
import android.os.Looper;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.media3.common.C;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.Timeline;
import androidx.media3.common.Tracks;
import androidx.media3.exoplayer.ExoPlayer;

public abstract class ExoPlayerEventListener implements Player.Listener {
  static final long DURATION_UNSET_INITIALIZATION_TIMEOUT_MS = 2000;
  private boolean isInitialized = false;
  private boolean isWaitingForValidDuration = false;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private final Runnable initializationFallback =
      () -> {
        if (!isInitialized && isWaitingForValidDuration) {
          isWaitingForValidDuration = false;
          isInitialized = true;
          sendInitialized();
        }
      };
  protected final ExoPlayer exoPlayer;
  protected final VideoPlayerCallbacks events;

  protected enum RotationDegrees {
    ROTATE_0(0),
    ROTATE_90(90),
    ROTATE_180(180),
    ROTATE_270(270);

    private final int degrees;

    RotationDegrees(int degrees) {
      this.degrees = degrees;
    }

    public static RotationDegrees fromDegrees(int degrees) {
      for (RotationDegrees rotationDegrees : RotationDegrees.values()) {
        if (rotationDegrees.degrees == degrees) {
          return rotationDegrees;
        }
      }
      throw new IllegalArgumentException("Invalid rotation degrees specified: " + degrees);
    }

    public int getDegrees() {
      return this.degrees;
    }
  }

  public ExoPlayerEventListener(
      @NonNull ExoPlayer exoPlayer, @NonNull VideoPlayerCallbacks events) {
    this.exoPlayer = exoPlayer;
    this.events = events;
  }

  protected abstract void sendInitialized();

  /** Cancels pending initialization callbacks when the player is disposed. */
  public void dispose() {
    isWaitingForValidDuration = false;
    mainHandler.removeCallbacks(initializationFallback);
  }

  private boolean hasValidDuration() {
    return exoPlayer.getDuration() != C.TIME_UNSET;
  }

  private boolean isLiveStream() {
    return exoPlayer.isCurrentMediaItemLive() || exoPlayer.isCurrentMediaItemDynamic();
  }

  private boolean shouldWaitForValidDuration() {
    return !isLiveStream();
  }

  private void maybeSendInitialized() {
    if (isInitialized) {
      return;
    }

    // For live streams: if duration is unknown or suspiciously short (< 5 s),
    // publish immediately with duration 0 so video_player does not pin the
    // clock at position 1 ms for the whole session. A real VOD that receives
    // its duration later will get it via onTimelineChanged as usual.
    if (isLiveStream()) {
      long dur = exoPlayer.getDuration();
      boolean liveHasNoDuration = dur == C.TIME_UNSET || dur < 5_000L;
      if (liveHasNoDuration) {
        isWaitingForValidDuration = false;
        isInitialized = true;
        mainHandler.removeCallbacks(initializationFallback);
        sendInitialized();
        return;
      }
    }

    if (!hasValidDuration() && shouldWaitForValidDuration()) {
      if (!isWaitingForValidDuration) {
        isWaitingForValidDuration = true;
        mainHandler.postDelayed(initializationFallback, DURATION_UNSET_INITIALIZATION_TIMEOUT_MS);
      }
      return;
    }

    isWaitingForValidDuration = false;
    isInitialized = true;
    mainHandler.removeCallbacks(initializationFallback);
    sendInitialized();
  }

  @Override
  public void onPlaybackStateChanged(final int playbackState) {
    PlatformPlaybackState platformState = PlatformPlaybackState.UNKNOWN;
    switch (playbackState) {
      case Player.STATE_BUFFERING:
        platformState = PlatformPlaybackState.BUFFERING;
        break;
      case Player.STATE_READY:
        platformState = PlatformPlaybackState.READY;
        maybeSendInitialized();
        break;
      case Player.STATE_ENDED:
        platformState = PlatformPlaybackState.ENDED;
        break;
      case Player.STATE_IDLE:
        platformState = PlatformPlaybackState.IDLE;
        break;
    }
    events.onPlaybackStateChanged(platformState);
  }

  @Override
  public void onTimelineChanged(@NonNull Timeline timeline, int reason) {
    if (isWaitingForValidDuration && exoPlayer.getPlaybackState() == Player.STATE_READY) {
      maybeSendInitialized();
    }
  }

  @Override
  public void onPlayerError(@NonNull final PlaybackException error) {
    if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
      // See
      // https://exoplayer.dev/live-streaming.html#behindlivewindowexception-and-error_code_behind_live_window
      exoPlayer.seekToDefaultPosition();
      exoPlayer.prepare();
    } else {
      events.onError("VideoError", "Video player had error " + error, null);
    }
  }

  @Override
  public void onIsPlayingChanged(boolean isPlaying) {
    events.onIsPlayingStateUpdate(isPlaying);
  }

  @Override
  public void onTracksChanged(@NonNull Tracks tracks) {
    // Find the currently selected audio track and notify
    String selectedAudioTrackId = findSelectedAudioTrackId(tracks);
    events.onAudioTrackChanged(selectedAudioTrackId);

    // Find the currently selected video track and notify
    String selectedVideoTrackId = findSelectedVideoTrackId(tracks);
    events.onVideoTrackChanged(selectedVideoTrackId);
  }

  /**
   * Finds the ID of the currently selected audio track.
   *
   * @param tracks The current tracks
   * @return The track ID in format "groupIndex_trackIndex", or null if no audio track is selected
   */
  @Nullable
  private String findSelectedAudioTrackId(@NonNull Tracks tracks) {
    // Keep this ID format in sync with android_video_player.dart::_parseAndroidTrackId.
    int groupIndex = 0;
    for (Tracks.Group group : tracks.getGroups()) {
      if (group.getType() == C.TRACK_TYPE_AUDIO && group.isSelected()) {
        // Find the selected track within this group
        for (int i = 0; i < group.length; i++) {
          if (group.isTrackSelected(i)) {
            return groupIndex + "_" + i;
          }
        }
      }
      groupIndex++;
    }
    return null;
  }

  /**
   * Finds the ID of the currently selected video track.
   *
   * @param tracks The current tracks
   * @return The track ID in format "groupIndex_trackIndex", or null if no video track is selected
   */
  @Nullable
  private String findSelectedVideoTrackId(@NonNull Tracks tracks) {
    // Keep this ID format in sync with android_video_player.dart::_parseAndroidTrackId.
    int groupIndex = 0;
    for (Tracks.Group group : tracks.getGroups()) {
      if (group.getType() == C.TRACK_TYPE_VIDEO && group.isSelected()) {
        // Find the selected track within this group
        for (int i = 0; i < group.length; i++) {
          if (group.isTrackSelected(i)) {
            return groupIndex + "_" + i;
          }
        }
      }
      groupIndex++;
    }
    return null;
  }
}
