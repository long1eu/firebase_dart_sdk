## 0.1.0-dev.1

Not released.

- The client core: `FirebaseAnalytics` with `logEvent`, `logScreenView` (as `page_view`), user id, user
  properties, default parameters, consent, the collection switch, `resetAnalyticsData`, `appInstanceId`,
  `sessionId`, `setAppActive`, `flush` and `close`.
- Validation of names, values and limits of the GA4 Measurement Protocol before an event is queued.
- Sessions and engagement time on every event; batches of up to 25 events and 130,000 bytes; retries with
  exponential backoff on network errors, 429 and 5xx; events older than 72 hours dropped.
- Two transports: a relay that carries the App Check and ID tokens, and a direct one with the API secret.
- `AnalyticsStore.memory()` and `FileAnalyticsStore` (`io.dart`).
- `AnalyticsDevice` and `AnalyticsUserLocation`, sent only when passed to the constructor.
