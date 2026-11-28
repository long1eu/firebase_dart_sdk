## Unreleased

- `reset()` clears the fetched and active templates, the fetch state and the throttle, in memory and in the
  store; defaults, custom signals and the realtime backoff stay.
- `onActivated`: a broadcast stream that emits after each `activate()` that returned true.
- `onRolloutsStateChanged`: the active rollout assignments (`RolloutAssignment`), the current set on
  listen and a new set after each change.
- `getKeysByPrefix(prefix)` and `getValueFrom(key, source)`.
- `RemoteConfigValue.asBytes()` and `RemoteConfigValue.asJson()`.
- The realtime failure counts and backoff ends are stored in a `realtime` record and restored at start.

## 0.1.0

- `FirebaseRemoteConfig` for a `FirebaseApp` and a `FirebaseInstallations`, with settings fixed at
  construction (defaults, minimum fetch interval, fetch timeout, language, HTTP client, logger) and
  `close()`.
- `fetch()` returning `FetchResult` (`updated`, `unchanged`, `cached`), `activate()` and
  `fetchAndActivate()`; concurrent fetches share one request; the ETag is sent as `If-None-Match`.
- Typed reads (`getValue`, `getAll`, `getString`, `getBool`, `getInt`, `getDouble`) with Android's
  conversions and fall-through to the defaults; reads answer from the defaults before initialization.
- `info`: last fetch status, last successful fetch time, throttle end, active and fetched template
  versions.
- An empty template (`NO_TEMPLATE`, `EMPTY_CONFIG`) keeps the template version and ETag the server sends; `If-None-Match`
  uses the fetched ETag, else the active one; `languageCode` is `en` when empty.
- Throttling after 429, 502, 503 and 504, persisted and shared with realtime fetches.
- Custom signals with the JS SDK's limits; a change makes the next fetch skip the cache.
- Realtime updates on `onConfigUpdated` on every platform: automatic fetch of newer templates, updated
  keys, backoff, `featureDisabled`, reconnection after an installation id change.
- Fetched and active templates, fetch state, throttle and signals stored in the Installations store;
  corrupt records are ignored.
- Response size caps, refused redirects, bounded numbers and redacted messages.
