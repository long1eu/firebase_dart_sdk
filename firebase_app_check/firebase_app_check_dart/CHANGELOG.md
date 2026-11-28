## 0.1.0

- `FirebaseAppCheck` with `getToken`, `getLimitedUseToken`, `onTokenChanged`, automatic refresh, rate control,
  optional persistence of the session token across restarts, and installation on the app's token seam.
- Two providers that are pure Dart on every platform: `DebugAppCheckProvider` (exchanges a debug token) and
  `CustomAppCheckProvider` (a token from the app's own function).
- Runs on the VM (macOS, Windows, Linux) and on the web (dart2js, dart2wasm).
- No log line, exception or `toString` carries a debug token, an App Check token or the API key.
