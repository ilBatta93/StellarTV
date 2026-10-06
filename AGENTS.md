Kids certification is warmed in the background after playlist loading and cached locally/cloud-side so profiles remain responsive.
- Cloud sync is tied to an email/password account: the authenticated user id is the sync key and row-level rules restrict every row to its owner.
- The native application identity is StellarTV on every platform; Dart and native player bridge names change together.
- TV presentation is capability-gated through the native Android UI mode; touch layouts and behavior remain the unchanged default.
- TV category panels share one remote-only drawer implementation with geometric left-edge detection and explicit focus restoration, to avoid trapping navigation across catalog tabs.
- The TV player reads the remote through an early key handler and moves its own (row, column) selection over a focus-free overlay; option panels above it use normal focus, and Back needs a confirmation press so playback is never left by accident.

- Playlist sections download in a background isolate with a streaming JSON parser (truncation-tolerant, bounded timeouts), run one at a time through a shared queue, publish and cache per section, and can be retried individually; pages are wrapped by a shared section frame that shows real progress, retry and saved-copy states on touch and TV, so huge playlists never block the UI or reload unrelated sections.
- The playlist opens from the device copy at every start; only sections never saved are downloaded immediately, and a full refresh runs only when the chosen interval has elapsed since the last complete download.
- Large derived caches (kids verdicts, playlist sections) are persisted to files through background isolates with batched writes, never to preferences or the main thread.

- TV catalogs use a shared collapsible-search/sort toolbar; Arrow Up returns to the active top-menu tab, while category drawers retain left-edge access.
- TV poster ratings use a shared two-request queue and an isolate-written device cache; unknown ratings sort last, and only the selected category is queued for vote sorting.
- TV person details reuse the fixed title backdrop and compact poster grid; the touch person layout stays unchanged.
