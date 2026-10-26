// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

public class VideoPlayerOptions {
  public boolean mixWithOthers;

  /**
   * The duration of the back buffer in milliseconds, used to configure ExoPlayer's load control.
   */
  @Nullable public Long backBufferDurationMs;

  /** Explicit forward buffer. When set, a [DefaultLoadControl] is always installed. */
  @Nullable public Long minBufferMs;

  @Nullable public Long maxBufferMs;

  @Nullable public Long bufferForPlaybackMs;

  @Nullable public Long bufferForPlaybackAfterRebufferMs;

  /**
   * Live only: keep [backBufferDurationMs] only while the current native window is seekable.
   */
  public boolean backBufferRequiresSeekable;

  /** Byte cap for the forward buffer. Zero or null leaves Media3's own target. */
  @Nullable public Long targetBufferBytes;

  public VideoPlayerOptions() {}

  /** Copy constructor to ensure all options are reliably copied. */
  public VideoPlayerOptions(@NonNull VideoPlayerOptions other) {
    this.mixWithOthers = other.mixWithOthers;
    this.backBufferDurationMs = other.backBufferDurationMs;
    this.minBufferMs = other.minBufferMs;
    this.maxBufferMs = other.maxBufferMs;
    this.bufferForPlaybackMs = other.bufferForPlaybackMs;
    this.bufferForPlaybackAfterRebufferMs = other.bufferForPlaybackAfterRebufferMs;
    this.backBufferRequiresSeekable = other.backBufferRequiresSeekable;
    this.targetBufferBytes = other.targetBufferBytes;
  }
}
