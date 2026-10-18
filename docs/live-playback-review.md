# Live playback review — 2026-10-18

## Applied
- Video health uses native rendered-first-frame and output counters on Android, not stream dimensions. mpv uses VideoController's first-render future, not estimated frame numbers (which follow playback time).
- Decoder disposal is awaited without turning a deadline into successful release, including preview, channel zapping, episode and MultiView transitions.
- Android live preview can use the same bounded software fallback as MultiView when automatic fallback is enabled. Disabled fallback is respected for both.
- Software-decoder memory is written only after the replacement successfully opens.
- mpv tuning runs after VideoController's asynchronous platform setup. Android and Apple copy-decoder paths remain unchanged; other native platforms use auto-safe instead of an Android decoder name.

## Rejected blanket changes
- Removing ExoPlayer or imposing one global player would remove native live-window DVR or MultiView. One player per ordinary session plus awaited screen handoffs is the appropriate invariant; MultiView intentionally has one session per tile.
- Forced vo/gpu-context options are owned by media_kit_video's platform controller. Android output names cannot be applied to Apple/desktop.
- Forced VLC user agent is not a universal compatibility fix; preserve provider/user-configured headers and existing network timeouts.
- genpts is not a video-render fix. Preserve live PCR/PTS and discard-corrupt handling; changing valid timestamps risks sync/seek regressions.
- A universal two-second fallback deadline interrupts valid keyframe/probing/surface startup. mpv waits ten active non-buffering seconds (fifteen in software), excluding pause/radio; session connection timeout remains configured.

## Verification and remaining limits
- 19 focused Flutter tests passed with Flutter 3.38.3 in a separate compatibility copy: video health, serialized disposal longer than four seconds, disabled preview fallback, session recovery, decoder memory and Xtream archive/DVR rules.
- The compatibility copy adjusts SDK/video_player constraints and omits unavailable video-quality APIs; production dependencies are unchanged. This is not an original-dependency APK verification.
- Additional legacy widget suites exposed missing HistoryProvider fixtures and /tmp/stv screenshot directory; they did not pass and are not claimed as verified.
- Native first-frame regression is added to VideoPlayerTest and the existing release workflow. Android SDK/Gradle environment is unavailable locally: the native test and compilation still require CI. No APK workflow was dispatched.
- Provider playback and surface behavior still require real Fire TV, Google TV/Chromecast, Android and iOS devices. No guarantee for broken sources, unsupported DRM or hardware-only codecs.