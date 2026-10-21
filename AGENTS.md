Kids visibility uses one strict genre/category-and-certification policy across catalogs, external results, history, episodes and navigation; device caches carry certifications in a new version and cloud cached verdicts are re-evaluated so legacy rating-only approvals cannot leak.
- Cloud sync is tied to an email/password account: the authenticated user id is the sync key and row-level rules restrict every row to its owner.
- The native application identity is StellarTV on every platform; Dart and native player bridge names change together.
- TV presentation is capability-gated through the native Android UI mode; touch layouts and behavior remain the unchanged default.
- TV category panels share one remote-only drawer implementation with geometric left-edge detection and explicit focus restoration, to avoid trapping navigation across catalog tabs.
- The TV player reads the remote through an early key handler and moves its own (row, column) selection over a focus-free overlay; option panels above it use normal focus, and Back needs a confirmation press so playback is never left by accident.

- Playlist sections download in a background isolate with a streaming JSON parser (truncation-tolerant, bounded timeouts), run one at a time through a shared queue, publish and cache per section, and can be retried individually; pages are wrapped by a shared section frame that shows real progress, retry and saved-copy states on touch and TV, so huge playlists never block the UI or reload unrelated sections.
- The playlist opens from the device copy at every start; only sections never saved are downloaded immediately, and a full refresh runs only when the chosen interval has elapsed since the last complete download.
- Large derived caches (kids verdicts, playlist sections) are persisted to files through background isolates with batched writes, never to preferences or the main thread.
- Kids scans deduplicate normalized pending/in-flight keys and cool down unresolved failures locally; unknown verdicts remain hidden and later requests can retry without a tight loop.

- TV catalog boundary keys bubble through a non-focusable ancestor before geometric traversal; the Home-owned top menu links every stop explicitly across spacers, so Up returns to the active tab and lateral movement never selects a tab by itself.
- Live completion flags never enter replay controls; explicit viewer pause cancels startup health deadlines and defers recovery until manual resume, so monitoring cannot restart a paused stream.

- TV catalogs keep filters/categories in a lazy inline panel shared by live and VOD: remote movement stays inside open panels until their vertical boundary, returns to tools above the first row and enters content below the last; default sorting preserves provider order and category drawers retain left-edge access.
- TV poster ratings use a shared two-request queue and an isolate-written device cache; unknown ratings sort last, and only the selected category is queued for vote sorting.
- TV person details reuse the fixed title backdrop and compact poster grid; the touch person layout stays unchanged.

- MPV receives live/VOD state before opening and applies native tuning serially before playback, so live buffering differs from VOD without racing stream initialization.

- TV player settings persist independent live and film/series scopes, initialized from legacy preferences; playback selects its content scope and touch continues using the shared legacy scope.

- Xtream expiry reminders compute schedules in a pure planner from the provider's exp_date, deliver them as local notifications plus an in-app Home banner (Google TV hides notifications), and fire each threshold once per expiry date.
- Cloud sync pushes immediately, serializes every caller and compares each fresh decrypted remote merge before encrypting or writing; unchanged verified snapshots succeed without a revision increment, preserving cross-device CAS and real user changes.
- Poster ratings resolve in groups through the backend's shared TMDB rating cache, falling back to direct TMDB lookups while the backend is unreachable.
- Every network image goes through one shared disk cache manager and is decoded at display size.
- Catalog grids memoize filtered lists by source instance, genre and metadata version so rebuilds reuse the same list and the sort cache keeps hitting.

- Primary section order and startup section are owned by UiSettings and identified by stable AppSection ids, so mobile/TV navigation and cloud sync never depend on positional indexes.

- Offline downloads live in DownloadService (one at a time, HTTP Range resume, device-only files) and playChannel swaps in the local file: history/resume ids stay unchanged.
- Every new TV control must be a TvFocusable stop reachable with the D-Pad: the app is used with a remote only.

- Reactions use timestamped per-profile entries with neutral tombstones inside the existing authenticated settings snapshot, so cloud merges preserve reversals and profile privacy without a second sync path.
- Episode playback targets use a concrete runtime FocusNode role, never debug labels (stripped in release), in an explicit horizontal lane; Down enters that episode’s actions and Up restores playback, keeping action geometry out of episode traversal. Episode presentation is a shared fixed-width horizontal card with separate playback/download/watched stops; the player episode picker owns modal focus, shows history progress/watched state, steps Back from episodes to seasons before closing, and retires the old connection before episode replacement.
- Live previews are audible, focus-debounced, active-tab gated and silenced before retirement on route pushes or backgrounding, so hidden tabs cannot compete with playback.
- PlaybackSession owns at most one native player: every swap unmounts the view, awaits full engine release and a provider-connection pause before creating the next, and exposes `released` so screens wait before opening another stream; repeated or stale engine errors trigger one recovery only.
- MultiView owns an isolated session per tile, serial mute-before-unmute audio ownership, bounded preview buffers and shared persisted layout preferences; its picker rechecks catalog and Kids permissions before opening streams.
- PlaybackSession supports an optional engine factory for deterministic remote/audio lifecycle tests without replacing production native engines.
- TV Home seeds its banner from the latest eligible history item until user focus takes over; HorizontalRow owns horizontal-only focused-card reveal independently from vertical heading reveal, so banner callbacks cannot leave selection offscreen or exhaust lazy neighbours.

- Secondary pages share ApplePageScaffold with bounded readable widths and their original scroll/focus bodies; shared theme and controls own Apple styling so no playback or sync logic is duplicated.
- TV focus respects the animation setting and system reduced motion, uses one high-contrast stop per action, and avoids blur filters on video or catalog surfaces to preserve low-powered TV performance.

- TV live guide rows and the preview expose catalog boundary markers: Up reaches tools from the first row or preview, then the shared menu; Down from tools skips items marked non-entry (the preview) to land on channels; channel logos reuse the bounded disk image cache without adding focus stops.
- Preview and MultiView start with ExoPlayer on Android and may recover through mpv only when automatic fallback is enabled; every handoff awaits actual native disposal, never treating a deadline as successful release, to prevent overlapping decoder/provider connections.
- ExoPlayer and mpv share PlaybackEngine; native Exo first-frame/output counters and the media_kit controller rendering signal drive video startup health instead of dimensions or estimated frame numbers, because metadata and playback time can advance with black output. VideoController finishes output setup before mpv tuning; output backends remain platform-owned to preserve Flutter texture compatibility.
- Player settings show each option only for engines that honour it, driven by PlayerEngineType capability getters, so adding an engine means declaring its capabilities there.

- Account and Xtream login share a presentation-only AuthScaffold; fields use the existing TV shell with explicit OK/tap activation, while session and playlist handlers remain in their original screens.
- All brand widgets render the shared full, symbol and name SVG paths with flutter_svg inside the existing layout envelopes; BrandIntro keeps its presentation-only timeline and never gates startup/session routing. Native icons are size-specific raster exports from these vectors.

- Xtream edits authenticate and recheck refresh activity before persistence, push the complete existing settings snapshot immediately, and refresh through AppProvider.loadFromXtream with explicit partial-download feedback; settings logout uses SyncProvider.signOut before routing to the initial AccountScreen so a saved session cannot bypass login.

- Home artwork uses landscape-only presentation widgets and focus-triggered cached official TMDB logos with text fallbacks; display title formatting never mutates catalog or sync identifiers.
- Player resume writes share a serialized per-screen writer; only the automatic next-episode overlay completes history and clears URL resume before the existing decoder release, so manual next and late lifecycle saves cannot change that intent.

- TV Home foreground starts below the real menu; TvHomeRows owns a snap-locked vertical viewport and retained row focus so each row occupies the entire remaining space and implicit child reveals cannot leak adjacent rows. Both actual series and movie routes publish resolved identity before optional metadata and use bounded official title art.
- TV Home scopes adaptive carousel dimensions through TvHomeLayout so synopsis and cards share the available height without changing touch or catalog defaults; recent episode labels use structured numbers with an explicit-title fallback, never modifying history identifiers.

- TV Top selectors use runtime focus roles and explicit selector/poster transitions inside the existing snap pager, so lateral keys never change rows.
- Trailer metadata uses the shared TMDB proxy and a validated YouTube URL launched externally, separate from IPTV playback/history to avoid extracting protected streams.

- Android uses the maintained local video_player_android fork for native decoder initialization fallback and a per-player live timeline channel; native seekability alone enables Exo DVR controls and LIVE uses the native default position, because retained TS samples do not create a seekable live window.
- Xtream archive capability is retained in cached Channel metadata; programme replay uses provider timezone and finite archive sources, rejecting future/expired requests rather than inventing history.
- Discovery refreshes share one in-flight future and bounded platform batches with persisted freshness, so page remounts cannot multiply catalog requests.

- Cached Kids selection is applied before catalog initialization; unresolved offline profiles never announce deselection, preventing startup races from relaxing content permissions.
- Archive playback retains the catalog identity and shared Kids gate but disables film/history resume writes; native DVR seeks use the current timeline rather than stale controller duration.
- Live diagnostics observes PlaybackSession without altering engine recovery; collection is device-local opt-in, bounded structured events exclude URLs/raw errors/identities, and explicit authenticated report uploads are owner-scoped for website export.

- SDK auth storage stays device-local and is excluded from both snapshot collection and restore; startup reads the session restored before runApp and device logout uses local scope, preventing token rotation races and cross-device revocation.

- Title logo URL metadata uses a versioned language-safe bounded disk cache and small adjacent decode warmups; initial catalog rendering never waits for logo downloads.
- Startup and QR pairing share bundled space artwork as presentation only; pairing polling and one-shot token exchange remain unchanged.

- QR presentation accepts an optional pairing service for isolated layout previews; production defaults to the real service and never seeds pairing data.

- Personal media sync uses account-bound AES-256-GCM envelopes and revision-CAS RPC writes; recovery keys use device-only OS secure storage, never preferences or cloud, to keep server access insufficient for decryption.
- SyncService owns legacy read/import and verified ciphertext readback; legacy rows are never cleaned automatically, because preservation must precede destructive migration.
- Favorite events use an encrypted reserved profile lane with persistent timestamped tombstones; this keeps the deployed website wire format compatible and prevents stale devices resurrecting removals.
- All cloud settings use a fail-closed presentation allowlist shared with website and SQL sanitization; player, codec and device settings are excluded on collection, merge and restore, keeping compatibility local.
- Public release notes enumerate every included commit with neutral descriptions rather than copying commit text, preserving coverage without exposing content configuration.

- Android excludes all app data from OS cloud backup and device transfer, while iOS recovery keys use this-device-only keychain accessibility, so recovery requires explicit user transfer.
- Complete favorite membership mutations, imports, event timestamps and decrypted merges share a serialized local queue; account exit drains that queue before clearing device preferences, preventing lost updates or late writes restoring another account’s data.
- Each installation imports paginated legacy rows until an encrypted write is read back and verified; a local account-scoped verification marker retires repeated imports, never deleting legacy rows.

- Live playback tries native MPEG-TS before HLS in automatic format, because Xtream HLS sessions stay counted after close and restreamed HLS often never delivers media; Exo HLS prepares from real segments, not playlist CODECS.
- Live sessions end a player that is ready but draws no first picture within an engine-specific deadline, choosing decoder fallback only when media time advances, so silent buffering never leaves a permanent black screen.
- Diretta "Visti di recente" uses a device-local id list separate from watch history, because live channels are intentionally excluded from history, Home rows and cloud sync.
- The in-player live channel list is a transparent dialog route over the running session, so the early player key handler yields to it and playback never stops while browsing.

- HomePresentation scopes validated layout preferences to Home cards and keeps image/caption bounds inside the existing TV snap rows, preserving focus reveal and catalog defaults.
- UiScale wraps presentation shells only, never the navigator or player surfaces; logical layout and hit testing scale together while root text scaling remains single-owned.

- PlayerScreen forwards an optional engine factory to PlaybackSession for remote-input tests; hidden-control seeking preserves overlay visibility while explicit OK and visible-control navigation keep their original behavior.

- Subtitle source selection is session-owned across engine replacements; external cues listen directly to playback time and use interval-aware lookup, with local per-content delay and bounded alternative downloads to avoid device-specific timing sync.
- HistoryEntry owns completion classification and remaining-time calculations from actual saved progress; Home metadata and detail actions reuse that policy, and series action countdowns target the same resume episode as playback, without a new sync wire format.
- WatchCompletionPolicy validates the portable watched threshold; HistoryProvider projects the current preference onto entries without changing serialized progress, and UiSettings changes refresh every history consumer immediately.
- Manual episode completion and suggestion dismissals use versioned timestamped control records inside encrypted profile histories, separate from playback and its cap; SyncService serializes writes and preserves newer controls against late playback snapshots. Series management never invents position or changes automatic next playback.
- Guided diagnostics adds only an enumerated optional problem to explicit exports/uploads; original technical evidence and player behavior remain unchanged.

- Settings option pickers mount their bounded option list eagerly inside a scroll view, so the current offscreen value receives TV autofocus and arrow navigation starts from it.
- Catalog panel Back resolves the visible same-route toolbar across focus transitions and consumes duplicate hardware/system dispatch within the closing frame, so genre/platform panels restore their own opener before the top menu handles a later Back.

- All PlaybackSession instances register shared background-work gates: guide/playlist work waits for closed sessions, cloud sends wait for explicit pause/end; pending local changes flush through the existing serialized sync.
- Native device identity carries a stable cloud compatibility marker independent of release numbering; external vault gating must reject explicitly and preserve the existing validation/CAS function, never claim a discarded write succeeded.
