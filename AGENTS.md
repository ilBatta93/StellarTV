Kids certification is warmed in the background after playlist loading and cached locally/cloud-side so profiles remain responsive.
- Cloud sync is tied to an email/password account: the authenticated user id is the sync key and row-level rules restrict every row to its owner.
- The native application identity is StellarTV on every platform; Dart and native player bridge names change together.
- TV presentation is capability-gated through the native Android UI mode; touch layouts and behavior remain the unchanged default.
- TV category panels share one remote-only drawer implementation with geometric left-edge detection and explicit focus restoration, to avoid trapping navigation across catalog tabs.
- TV player controls use a dedicated play focus anchor and leave button activation to the focused control, so showing controls never traverses back into the video surface.

- Playlist loading publishes independent per-section states and data after each sequential request; passive fixed-size navigation indicators share those states on touch and TV without adding focus targets or guessed percentages.
