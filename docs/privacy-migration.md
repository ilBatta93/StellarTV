# Encrypted personal synchronization — integration handoff

## State
The website companion is integrated into the Lovable working branch on the user's explicit request; Flutter changes are prepared for integration on StellarTV main. No website publication or Android build is authorized by this integration task. This is NOT a completed production data migration.

## Protocol and preservation
AES-256-GCM; 32-byte user recovery key; account-bound SHA-256 key identifier and authenticated additional data; fresh 12-byte nonce per write; revision-CAS RPC. Source settings and playback addresses are excluded from uploaded plaintext before encryption. The key remains in per-account device secure storage; Android OS backup/transfer is excluded, iOS accessibility is this-device-only. QR display is explicit and contains the recovery key: transfer privately or enter it manually on the other signed-in device. No cloud QR relay or automatic camera scanner is provided.

Each installation reads all paginated legacy classes, merges local and remote data, uploads encrypted data, then reads it back and decrypts/compares it. Only verified writes set the account-scoped local import marker. Failed reads/writes preserve every local and legacy copy. No legacy cleanup is enabled. Do not call the disabled cleanup RPC or delete legacy data.

Favorite removal events are serialized and retained in the encrypted reserved profile lane. History deletion wins equal timestamps. Source catalogs must be configured locally on each device; cloud data contains no playback URLs. Native playback/episode resolution requires real-device verification.

## Verification and remaining gates
Reduced isolated Flutter verification covers synthetic web-to-Dart AES-GCM interoperability, key/account rejection, tamper/nonce rules, complete concurrent favorite mutations/imports, diagnostic privacy, settings/auth exclusion, account exit and TV Back/navigation. Website unit tests and authenticated browser navigation/key-confirmation checks pass without writing real cloud data. These are not full app/build or real account migration tests.

Production app requires Dart >=3.13.5 / Flutter >=3.44.0; available local Flutter is 3.38.3 / Dart 3.10.1. Restore dependency lock through `flutter pub get` with the original supported SDK before integration; new packages have not been resolved in the original production lock. No SDK constraints were relaxed in production.

After integration: run full production analysis/tests; build only when explicitly requested; test secure storage/sign-out/restart on Android/iOS, QR/manual authorization of a second device, synchronized additions/removals/progress, local playback address resolution, concurrent revision conflict, offline changes, and failed migration. Authorize with a privately held real recovery key and read back actual data through the UI before declaring migration complete. Historical GitHub releases/commits and all source identifiers have not been removed. Neither a public website nor readable client source can hide the application's entire function or guarantee zero risk.
