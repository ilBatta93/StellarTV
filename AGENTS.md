Kids visibility uses one strict genre/category-and-certification policy across catalogs, external results, history, episodes and navigation; device caches carry certifications in a new version and cloud cached verdicts are re-evaluated so legacy rating-only approvals cannot leak.
- Cloud sync is tied to an email/password account: the authenticated user id is the sync key and row-level rules restrict every row to its owner.
- The native application identity is StellarTV on every platform; Dart and native player bridge names change together.
- TV presentation is capability-gated through the native Android UI mode; touch layouts and behavior remain the unchanged default.
- TV category panels share one remote-only drawer implementation with geometric left-edge detection and explicit focus restoration, to avoid trapping navigation across catalog tabs.
- The TV player reads the remote through an early key handler and moves its own (row, column) selection over a focus-free overlay; option panels above it use normal focus, and Back needs a confirmation press so playback is never left by accident.

- Playlist sections download in a background isolate with a streaming JSON parser (truncation-tolerant, bounded timeouts), run one at a time through a shared queue, publish and cache per section, and can be retried individually; pages are wrapped by a shared section frame that shows real progress, retry and saved-copy states on touch and TV, so huge playlists never block the UI or reload unrelated sections.
- The playlist opens from the device copy at every start; only sections never saved are downloaded immediately, and a full refresh runs only when the chosen interval has elapsed since the last complete download.
- Large derived caches (kids verdicts, playlist sections) are persisted to files through background isolates with batched writes, never to preferences or the main thread.

- TV catalogs keep filters/categories in a lazy inline panel shared by live and VOD: remote movement stays inside open panels until their vertical boundary, returns to tools above the first row and enters content below the last; default sorting preserves provider order and category drawers retain left-edge access.
- TV poster ratings use a shared two-request queue and an isolate-written device cache; unknown ratings sort last, and only the selected category is queued for vote sorting.
- TV person details reuse the fixed title backdrop and compact poster grid; the touch person layout stays unchanged.

- MPV receives live/VOD state before opening and applies native tuning serially before playback, so live buffering differs from VOD without racing stream initialization.

- TV player settings persist independent live and film/series scopes, initialized from legacy preferences; playback selects its content scope and touch continues using the shared legacy scope.

- Xtream expiry reminders compute schedules in a pure planner from the provider's exp_date, deliver them as local notifications plus an in-app Home banner (Google TV hides notifications), and fire each threshold once per expiry date.
- Cloud sync pushes on every change with zero delay; a single in-flight guard coalesces changes made during an upload into one follow-up push, and favorites pushes trigger only on real favorite changes.
- Poster ratings resolve in groups through the backend's shared TMDB rating cache, falling back to direct TMDB lookups while the backend is unreachable.
- Every network image goes through one shared disk cache manager and is decoded at display size.
- Catalog grids memoize filtered lists by source instance, genre and metadata version so rebuilds reuse the same list and the sort cache keeps hitting.

- Primary section order and startup section are owned by UiSettings and identified by stable AppSection ids, so mobile/TV navigation and cloud sync never depend on positional indexes.

- Offline downloads live in DownloadService (one at a time, HTTP Range resume, device-only files) and playChannel swaps in the local file: history/resume ids stay unchanged.
- Every new TV control must be a TvFocusable stop reachable with the D-Pad: the app is used with a remote only.

- Reactions use timestamped per-profile entries with neutral tombstones inside the existing authenticated settings snapshot, so cloud merges preserve reversals and profile privacy without a second sync path.
- Episode presentation is a shared fixed-width horizontal card with separate playback/download/watched stops; the player episode picker owns modal focus, shows history progress/watched state, steps Back from episodes to seasons before closing, and retires the old connection before episode replacement.
- Live previews are audible, focus-debounced, active-tab gated and silenced before retirement on route pushes or backgrounding, so hidden tabs cannot compete with playback.
- PlaybackSession owns at most one native player: every swap unmounts the view, awaits full engine release and a provider-connection pause before creating the next, and exposes `released` so screens wait before opening another stream; repeated or stale engine errors trigger one recovery only.
- MultiView owns an isolated session per tile, serial mute-before-unmute audio ownership, bounded preview buffers and shared persisted layout preferences; its picker rechecks catalog and Kids permissions before opening streams.
- PlaybackSession supports an optional engine factory for deterministic remote/audio lifecycle tests without replacing production native engines.
- TV Home seeds its banner from the latest eligible history item until user focus takes over; HorizontalRow owns horizontal-only focused-card reveal independently from vertical heading reveal, so banner callbacks cannot leave selection offscreen or exhaust lazy neighbours.

- Secondary pages share ApplePageScaffold with bounded readable widths and their original scroll/focus bodies; shared theme and controls own Apple styling so no playback or sync logic is duplicated.
- TV focus respects the animation setting and system reduced motion, uses one high-contrast stop per action, and avoids blur filters on video or catalog surfaces to preserve low-powered TV performance.

- TV live guide rows and the preview expose catalog boundary markers: Up reaches tools from the first row or preview, then the shared menu; Down from tools skips items marked non-entry (the preview) to land on channels; channel logos reuse the bounded disk image cache without adding focus stops.
- Preview and MultiView tiles use ExoPlayer on Android with no engine fallback, and the Diretta queue awaits the session's full release before the next preview or the full player, because rapid native mpv/MDK create/release crashed TV devices.
- Three engines (mpv, MDK via fvp used directly, ExoPlayer on texture view) share PlaybackEngine; a session tries every address of the channel with the chosen engine, then with PlayerEngineType.other (ExoPlayer and mpv only, MDK never automatic); mpv reports audio-without-frames as an error instead of changing decoder at runtime, and never uses force-seekable because media_kit seeks to 0 on surface attach.
- Player settings show each option only for engines that honour it, driven by PlayerEngineType capability getters, so adding an engine means declaring its capabilities there.

- Account and Xtream login share a presentation-only AuthScaffold; fields use the existing TV shell with explicit OK/tap activation, while session and playlist handlers remain in their original screens.
- BrandIntro crops the approved raster asset without regeneration or new lettering; its controller is presentation-only and never gates startup/session routing, and independent orbit motion requires original separated layers.

- Xtream edits authenticate and recheck refresh activity before persistence, push the complete existing settings snapshot immediately, and refresh through AppProvider.loadFromXtream with explicit partial-download feedback; settings logout uses SyncProvider.signOut before routing to the initial AccountScreen so a saved session cannot bypass login.

- Home artwork uses landscape-only presentation widgets and focus-triggered cached official TMDB logos with text fallbacks; display title formatting never mutates catalog or sync identifiers.
- Player resume writes share a serialized per-screen writer; only the automatic next-episode overlay completes history and clears URL resume before the existing decoder release, so manual next and late lifecycle saves cannot change that intent.
