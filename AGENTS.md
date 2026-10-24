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

- TV catalogs share a lazy filter grid with explicit four-direction row/column targets; Back restores its opener through teardown and settings Left returns to the retained active sidebar node, avoiding geometric focus jumps while touch is unchanged.
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

- PlayerScreen forwards an optional engine factory to PlaybackSession for remote-input tests; hidden OK pauses through the existing session and reveals Play, with intro/outro priority and repeat suppression. Hidden VOD vertical shortcuts use a local timed info overlay and a modal chooser dispatching existing audio/subtitle/episode panels, preserving decoder ownership and avoiding metadata requests.

- Subtitle source selection is session-owned across engine replacements; external cues listen directly to playback time and use interval-aware lookup, with local per-content delay and bounded alternative downloads to avoid device-specific timing sync.
- Series resume policy follows the newest playback timestamp and immediate successor, independent of manual watched badges; Home checks are bounded to active profile/progress keys and discard obsolete catalog results, so replay never clears sibling history or needs a new sync format.
- WatchCompletionPolicy validates the portable watched threshold; HistoryProvider projects the current preference onto entries without changing serialized progress, and UiSettings changes refresh every history consumer immediately.
- Manual episode completion and suggestion dismissals use versioned timestamped control records inside encrypted profile histories, separate from playback and its cap; SyncService serializes writes and preserves newer controls against late playback snapshots. Series management never invents position or changes automatic next playback.
- Guided diagnostics adds only an enumerated optional problem to explicit exports/uploads; original technical evidence and player behavior remain unchanged.

- Settings option pickers mount their bounded option list eagerly inside a scroll view, so the current offscreen value receives TV autofocus and arrow navigation starts from it.
- Catalog panel Back resolves the mounted, focus-enabled same-route toolbar using the Home context even when primary focus detaches; transition tokens cancel stale focus callbacks and panel arrows remain owned by the explicit grid.

- All PlaybackSession instances register shared background-work gates: guide/playlist work waits for closed sessions, cloud sends wait for explicit pause/end; pending local changes flush through the existing serialized sync.
- Native device identity carries a stable cloud compatibility marker independent of release numbering; external vault gating must reject explicitly and preserve the existing validation/CAS function, never claim a discarded write succeeded.

- ForegroundPolicy combines resumed lifecycle and best-effort native display hints; one guarded cloud HTTP transport and suspended schedulers preserve local writes without account leases or background heartbeats. Playback ownership stays separate from visibility so foreground return cannot release a playing session.

- Remote single-device signout and its background polling are retired; keep normal local/global Auth signout and token refresh unchanged to reduce recurring database traffic without weakening authentication.

- Playback assistance is device-local: automatic episode transitions obey the player preference at both credits and natural end; unknown credits only suggest manual continuation. Local chapter reads are one-shot per engine and bounded, with validated segment coordinates and cached remote lookups.
- Service diagnosis uses one bounded local account request only on manual action or final playback failure, no stream probes, polling or database; reports uncertainty and refuses mismatched playback accounts.

- Automatic next is stored in one portable boolean outside technical player blobs; loads project it into VOD settings while live settings never overwrite it.
- Startup publishes the device catalog before detached missing-section loading; configured devices restore cloud data without gating Home. Full refresh keeps the input guard and catalog publication waits for closed playback.
- Episode progress follows the latest actual seek or playback sample, not the greatest past progress; explicit completion remains terminal only within that player session.
- Watch management uses one remote focus stop per season/episode and separate choice dialogs for bulk changes, avoiding ambiguous inline action grids.

- Home title availability and series folders are indexed once per playlist in a background isolate (lib/services/catalog_index_builder.dart); Home lookups are non-blocking (wait: false) while user actions keep the synchronous fallback, so launch never freezes the remote. The index stays device-local and is never synced to the cloud.
- Live guide is one shared proportional time window (past range bounded) with a theme-coloured now line; past cells replay only via XtreamCatchup, so the grid never invents archive support.
- Live previews wait for guide initialization and active guide/catalog downloads, resuming through provider listeners; blocked initial EPG scheduling retains due work so closing playback cannot lose a refresh.
- Frame telemetry records aggregates only during an explicit session (auto-stop) and uploads through the same owner-scoped diagnostic reports table, so no extra polling or tables exist.

- TV Home decodes posters on demand, retains one complete vertical neighbour and bounded horizontal neighbours for D-Pad traversal, and swaps only changed settled artwork; native memory pressure bounds the single Home backdrop through TvRenderPolicy while suppressing other decorative backdrops until process restart, never hiding selectable cards or deleting disk/user data.
- TV decoded-image memory shrinks on native memory-pressure signals; speculative image work checks playback/visibility and reuses cached files, never deleting user data or disk images.
- Catalog sort logic is browser/native-independent in catalog_sort.dart; a top-level isolate boundary receives only catalog entries and rating snapshots, while recent/filter list identities are cached to avoid repeated UI-thread sorts.

- TV focus uses a static lift and theme ring without animated blurred shadows; duplicate decorative poster fills and the custom splash fade are touch-only, reducing raster work while retaining the same controls.

- Update dialogs own a bounded notes scroll controller and explicit TV focus nodes: initial Update focus, Up enters notes from the top, Down at the end restores Update, and horizontal keys select actions; touch keeps native buttons and scrolling.

- EPG HTTP, gzip, incremental XML events, merging and JSON serialization run in a killable worker; only bounded classified errors leave it and staged cache replacement follows the foreground/playback guard, preserving the previous guide on failure.
- Catalog section publication yields in bounded batches and validates account, profile, evidence and snapshot before atomic replacement; per-section disk workers are awaited to avoid overlapping downloads and saves on constrained TVs.
- EPG yields priority to active catalog refreshes and is canceled/deferred through the existing guide queue, avoiding competing heavy workers without new polling.

- EPG timeline uses presentation-only clipped intervals and original program objects for playback; shared time geometry and event identity prevent overlap without changing archive timestamps.
- TV Discover artwork paints one contrast scrim and keeps touch/player styling unchanged to reduce full-screen overdraw.
- Both release workflows generate neutral, change-scoped notes from versioned release-current bullets; a bounded summary feeds the update dialog, whose notes focus owns remote scrolling directly.

- Catalog derivation uses bounded cooperative jobs and scope/playback checks; prepared device files include genre counts, so filter opening never scans titles synchronously. Evidence cache loads before queuing unknowns; EPG files are source-scoped in application support, with independent freshness and full-refresh integration.
- Frame diagnostics checkpoint bounded aggregates privately through a coalesced atomic file writer and rotate current to previous before auto-start, allowing explicit recovery uploads without background network work.

- Genre options are immediately available independently of counts; matching retains verified metadata and Kids filtering, while counts are read-only in rendering and refreshed after evidence/preparation changes. Category labels memoize channel identity to avoid repeated catalog scans.

- Title category membership is indexed once per visible playlist snapshot off the UI thread, invalidated with catalog caches; Home omits unused category facets and platform membership uses ID sets to avoid rendering-time scans.
- Optional shared TMDB detail/credits/video cache keys include endpoint and language; only already-requested responses are cached, writes require a verified account, and missing schema falls back to the existing proxy without mass prefetch.
- Per-title metadata (IMDb ratings, watch providers) lives in device stores valid 30 days and refreshed in the background, never rebuilt at start; badges must not depend on opening filters.
- EPG matching keeps timeshift channels (+1/+2) separate from base guides even with shared tvg-ids; missing timeshift guides reuse the base shifted by the hours.

- Title parsing is device-only and year-aware, preserves numeric titles, and requires an unambiguous official-name match; versioned derived caches exclude legacy title-only identities. TMDB policy markers prevent double weighting; IMDb pending values stay hidden, with nonpersistent transport-failure fallback. Episode artwork uses validated per-episode stills and a bounded cached fallback chain. App services use the primary companion origin.
- Episode metadata is scoped by series/season/episode, prepared per selected season before playback and read locally by player information; never substitute the series rating for an episode.
- Catalog section copies use verified NDJSON (header, one title per line, end marker) written in time-sliced batches and streamed back in a background isolate; incomplete copies fall back to the previous format so a failed save never empties a section or spikes memory.
