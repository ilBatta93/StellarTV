# Live diagnostics

Settings → Diagnostica dirette is off by default and stored only on this device, not synchronized as a player setting. Turn it on before reproducing a problem. It observes all live PlaybackSession instances, including previews and MultiView, without changing recovery behavior.

Reports contain platform, OS/model, app version/build, per-attempt engine/format/software mode, open readiness time, actual renderer first-frame time when available, buffering intervals and classified failures. A stationary media clock for five seconds is labeled `suspected_stall`, not proof of a frozen frame. Pauses and background states are excluded. Starting diagnostics during playback is identified separately so its first observation is never mislabeled full startup time. Events are capped at 1000 and persisted locally; disabling stops sampling but retains prior events until cleared.

URLs, provider usernames/passwords, account identifiers, channel titles and raw player errors are excluded. Per-device salted stream hashes allow correlating the same address without exposing credentials. Model/OS details are collected for device comparison. No automatic upload: `Invia al mio account` explicitly sends a snapshot using the existing signed-in account. Guests must sign in for website export; phones can share a JSON file without an account. TV export uses the authenticated website, not a public LAN listener.

Website: Il mio account → Log errori → select report → Copia or Scarica JSON. Owner-only grants/RLS apply to read/insert/delete. Up to 30 recent reports are listed; deletion removes a report from the site, clearing local events does not. The web table migration is applied in the Lovable site, shared with Flutter's existing account backend.

Tests: live_diagnostics_test.dart and live_diagnostics_remote_test.dart cover default off, disabling, bounded retention, private stream/error data, stall exclusions and TV activation/focus. They passed with a locally adapted SDK dependency copy; original SDK and native platform/share-sheet behavior require CI/device validation.

Next investigation: reproduce the same failing channel on each affected device and export immediately; compare first-frame vs open-ready times, TS vs HLS, engine changes and connection-limit errors. Try Wi-Fi vs Ethernet and a single stream before MultiView. Add native decoder/codec and dropped-frame telemetry if these reports indicate decode stalls; do not add more universal tuning guesses without this evidence.
