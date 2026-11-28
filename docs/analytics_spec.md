# Analytics client: specification

The plan for `firebase_analytics_dart`, a pure-Dart client of Google Analytics for Firebase, and its
FlutterFire adapter `firebase_analytics_dart_platform`. It follows
[contributing_a_product.md](contributing_a_product.md). This document comes before the code. Once the
code exists, an `analytics_decisions.md` in the format of [storage_decisions.md](storage_decisions.md)
replaces it, and an `analytics_parity.md` in the format of [auth_parity.md](auth_parity.md) compares the
API with the official SDKs.

The first draft marked a number of statements **(measure)**: expectations not yet checked. Each is now
answered from Google's documentation in [analytics_protocol.md](analytics_protocol.md), with its source and
date, and the text below links to the section that answers it. The questions the documentation leaves open are listed in its
section 10 and answered by the production verification kit.

## 1. Why this is not a port

The other clients in this repository port the behaviour of the JS SDK. Analytics cannot work that way:

- The Android and iOS Analytics SDKs ship as closed binaries, so there is no source to compare with.
- `@firebase/analytics` (JS) is open source, but it is a thin wrapper that loads Google's `gtag.js` into
  the page and forwards calls to it. A Dart program on the VM has no `gtag.js`.
- The only public way for a program that is not a browser page or a mobile app to send events is the
  **GA4 Measurement Protocol**: JSON over HTTP POST to `https://www.google-analytics.com/mp/collect`.

So the package is a Measurement Protocol client with the API shape of Firebase Analytics. The JS SDK is
the reference for the public API: method names, `setConsent`, default event parameters,
`isSupported`, the collection switch. Google's Measurement Protocol documentation is the reference for
the wire format and its limits.

**Who it is for.** Windows and Linux desktop apps (FlutterFire's `firebase_analytics` has no
implementation there), command-line tools, and Dart servers that record events for their own users.
The C++ SDK does have a Windows implementation, a closed DLL with no consent, no session timeout and no
instance id; it is not reachable from Dart without FFI, and on Linux the C++ SDK has stubs only
([parity](analytics_parity.md#the-c-sdk-on-desktop)).
On Android, iOS, macOS and the web, the official FlutterFire plugin remains the better choice: it
collects automatic events, attribution and device data that the Measurement Protocol cannot produce.
The README says this in its first section.

## 2. Hard limits, said in the README

1. **The API secret.** Each Measurement Protocol request needs an `api_secret` created on the GA4 data
   stream. Google's guidance is to keep it private. In a desktop app it ends up in the binary, and
   anyone who extracts it can send fake events into the property. The client therefore has two
   transports (section 5): a **relay** that sends events to a server the developer runs, which adds
   the secret (the recommended path), and a **direct** transport that carries the secret, documented as
   suitable for internal tools and servers only.
2. **Reserved events.** The Measurement Protocol refuses or ignores some event names that the native
   SDKs collect automatically, among them `first_open`, `first_visit`, `session_start`,
   `user_engagement`; `screen_view`, `ad_impression` and `in_app_purchase` are allowed for app streams
   only, so a web stream cannot send them either (the full list:
   [protocol §4](analytics_protocol.md#reserved-names)). The client cannot report them the way the native SDKs do. Sessions are reported
   through the `session_id` and `engagement_time_msec` parameters (section 6). Screen views are a
   decision for the protocol document; section 7 has the proposal.
3. **The kind of stream.** A request names either a web stream (`measurement_id` and `client_id`) or a
   Firebase app stream (`firebase_app_id` and `app_instance_id`). The `app_instance_id` is documented as
   coming from the native SDK, and the documentation gives it no format and says it "must be retrieved
   using the Firebase SDK". The client therefore targets a **web stream** only, and the data appears in
   the console as web traffic ([protocol §5](analytics_protocol.md#5-the-kind-of-stream)). The same
   documentation says a valid web event needs a `client_id` "that has already been used to send an event
   from gtag.js". Whether events from a self-generated `client_id` are reported is the first question
   for the production kit; if they are not, this specification goes back for a decision.
4. **No parity with the native SDKs.** The client has no install attribution, no automatic device and
   geography data beyond what the request can carry (section 6), no audiences for Remote Config
   conditions and no AdMob linking. `analytics_parity.md` lists each of these as "not applicable" or
   "later".
5. **No emulator.** The Firebase emulator suite has no Analytics emulator. Tests use `MockClient`. The
   validation endpoint (`/debug/mp/collect`) and DebugView are used only by the production
   verification kit, run by the maintainer with their own property.

## 3. Packages

| Package | Path | Kind |
|---|---|---|
| `firebase_analytics_dart` | `firebase_analytics/firebase_analytics_dart` | Dart, every platform, web included |
| `firebase_analytics_dart_platform` | `firebase_analytics/firebase_analytics_dart_platform` | Flutter adapter for FlutterFire's `firebase_analytics_platform_interface`, registered on Windows and Linux |

Both names were free on pub.dev on 2026-11-27. Dependencies of the client: `firebase_app_dart`, `http`,
`meta`. No `dart:io` in the main library. A file-backed store lives in `lib/io.dart`, as in Storage.

## 4. Public API (proposal)

```dart
final analytics = FirebaseAnalytics(
  app,
  measurementId: 'G-XXXXXXX',
  transport: AnalyticsTransport.relay(Uri.parse('https://example.com/collect')),
  // or AnalyticsTransport.direct(apiSecret: '...'): internal tools and servers only
  store: FileAnalyticsStore(directory),          // from io.dart; AnalyticsStore.memory() by default
  region: AnalyticsRegion.global,                // .eu uses region1.google-analytics.com
  sessionTimeout: const Duration(minutes: 30),
  collectionEnabledByDefault: true,
  httpClient: client, clock: clock, random: random,
);

await analytics.logEvent(name: 'level_up', parameters: {'level': 3});
await analytics.setUserId('user-123');                 // null clears it
await analytics.setUserProperty(name: 'plan', value: 'pro');
await analytics.setDefaultEventParameters({'app_version': '1.4.0'});
await analytics.setConsent(adUserData: false, adPersonalization: false);
await analytics.setConsent(analyticsStorage: false);  // nothing is queued or sent while denied
await analytics.setAnalyticsCollectionEnabled(false);  // persisted; queued events are dropped
await analytics.resetAnalyticsData();                  // new client id, clears the user id, properties and queue
final String id = await analytics.appInstanceId;       // the client id of this installation
final int? session = await analytics.sessionId;
analytics.setAppActive(true);                          // lifecycle hook; the adapter calls it
await analytics.flush();
await analytics.close();
```

Decisions behind the proposal:

- **Configuration is immutable** (design rule 4). `setAnalyticsCollectionEnabled`, consent, the user
  id, user properties and default parameters are runtime state, not configuration: they are what the
  user decides while the app runs. They are persisted in the store.
- **The client keeps one general method, `logEvent`.** FlutterFire's dozens of `logXxx` helpers
  (`logLogin`, `logPurchase` and the rest) belong in the adapter, which maps them to
  `logEvent` with GA4's recommended names and parameters. The client may export constants for the
  recommended event and parameter names.
- **Validation happens in the client**, before an event is queued, with the limits as constants:
  name length and characters, reserved names and prefixes (`firebase_`, `google_`, `ga_`), the number
  of parameters per event, parameter name and value lengths, user property name and value lengths,
  and the number of user properties ([protocol §4](analytics_protocol.md#4-names-and-limits)). An invalid
  event throws `FirebaseAnalyticsException` with a kebab-case code (`invalid-event-name`,
  `invalid-parameter`, `reserved-name` and so on). The native SDKs drop invalid events silently and log
  them. Throwing is a deliberate difference, listed in the parity document, because a silent drop
  hides mistakes during development, and the server never reports them
  ([protocol §9](analytics_protocol.md#9-validation-in-the-client-throw)).
- **Parameter values** are `String`, `int`, `double` or `bool` (sent as `0` or `1`), plus the `items` list
  of e-commerce events. Every number is checked with `isFinite` (design rule 9).

## 5. Transport

`AnalyticsTransport` is a sealed class with two implementations.

- **Relay** posts the Measurement Protocol body, without the secret, to a URL of the developer's server.
  It attaches the App Check token from `app.appCheckProvider` and, when a user is signed in, the ID token
  from `app.authProvider`, under the same rules as the other packages (design rule 5: https, a
  loopback host, or nothing). The server checks those tokens, adds `api_secret` and forwards the body.
  The package ships an example relay in `examples/` (a few dozen lines on `shelf`) and documents the
  checks a relay must do: rate limits per user or App Check token, a size cap, and passing the body on
  without rewriting `client_id`.
- **Direct** posts to `https://www.google-analytics.com/mp/collect?measurement_id=…&api_secret=…`, or
  to `region1.google-analytics.com` for the EU. The secret never appears in exceptions, logs or
  `toString`.

Both transports:

- send at most the documented number of events per request and keep the body under the documented
  size: 25 events, and 130,000 bytes of UTF-8 JSON
  ([protocol §3](analytics_protocol.md#3-request-body));
- treat 2xx as delivered. The production endpoint answers 2xx even for invalid events, which is why
  validation lives in the client;
- retry on network errors and on 5xx and 429, with injected exponential backoff and jitter; drop a
  batch refused with any other 4xx, as the documentation says not to retry it
  ([protocol §1](analytics_protocol.md#1-endpoints)); do not follow redirects;
- never send while collection is disabled.

## 6. What every request carries

- `client_id`: created on first use, persisted, as `<random 31-bit positive integer>.<Unix seconds>`,
  the documented "two positive numbers, joined by a period". `resetAnalyticsData` replaces it.
- `user_id` when set, and `user_properties` as `{name: {value: …}}`.
- `consent` from `setConsent`, and only after it was called: without the field, Google Analytics uses
  the client's earlier consent settings.
- `timestamp_micros` on **each event** (not on the request, as this document first said), taken from the
  time the event was logged, not sent. Events older than the documented backdating limit of 72 hours are
  dropped from the queue rather than sent, because the server would silently re-date them.
- **Session parameters on every event:** `session_id` (the start time of the session, in seconds) and
  `engagement_time_msec`. A session ends after `sessionTimeout` without events while the app is
  inactive, as in gtag. Engagement time is the time the app was active since the previous event, at
  least 1 ms. Without `setAppActive` calls (a CLI or a server) the app counts as active.
- **Device and location fields** ([protocol §7](analytics_protocol.md#7-device-and-geography)): no
  `device` block by default. Strict validation refused a partial one (it required `model`, then `browser`,
  measured on 2026-11-28), and a program cannot read those fields; a developer may pass a complete block.
  No `user_agent` and no `ip_override`. `user_location` only when the developer supplies it; the client
  does not guess a country from the locale. No IP address is collected or sent.

## 7. Screen views

`screen_view` is allowed for app streams only, and the documentation says to use `page_view` on a web
stream ([protocol §8](analytics_protocol.md#8-screen-views)). Decided:
`logScreenView(screenName:, screenClass:)` sends `page_view` with `page_title` set to the screen name,
`page_location` set to `app://<app id>/<screen name>` and the class in `screen_class`, so screens appear in
GA4's pages report. The parity document records it as a difference.

## 8. Queue and storage

- Events are queued in the store and sent in batches: after a short delay (default 5 s), when the
  queue reaches the batch limit, on `flush()` and on `close()`.
- `AnalyticsStore` is an interface (load and save the client id, the state of section 4, and the
  queue). Two stores ship: `AnalyticsStore.memory()` and `FileAnalyticsStore` in `io.dart`. On the web,
  a `localStorage` store behind a conditional import. Sizes are capped (default 1,000 events): when
  the cap is reached the oldest events go first.
- A store that cannot be read starts empty with a new client id and logs a warning. It never throws
  into `logEvent`.

## 9. The FlutterFire adapter

`firebase_analytics_dart_platform` implements `FirebaseAnalyticsPlatform`, registers itself on Windows
and Linux (`dartPluginClass`), and maps every method. Methods that have no meaning here
(`initiateOnDeviceConversionMeasurementWith…`, `logTransaction`) throw `UnimplementedError` with a clear
message. `setSessionTimeoutDuration` reconfigures the client before the first event and throws after it.
Every method is mapped in [the parity document](analytics_parity.md#the-flutterfire-adapter). It hooks
`AppLifecycleListener` to `setAppActive`, and it takes the measurement id and transport from a
`FirebaseAnalyticsDart.configure(...)` call made before `Firebase.initializeApp`. The exact
registration follows `firebase_storage_dart_platform`.

## 10. Order of work, one PR each

1. **This specification and the protocol document** (`docs/analytics_protocol.md`): every limit,
   reserved name, field and endpoint marked "measure" above, with the source and date. This step reads
   documentation only and sends no request to Google.
2. **The parity document** (`docs/analytics_parity.md`): JS, Android, iOS and C++ public APIs, method
   by method, ranked first release, later, or not applicable.
2a. **The reporting probe**, the core of step 6 brought forward: `tool/analytics_probe.dart`
   ([tool/analytics_probe.md](../tool/analytics_probe.md)) sends a few events and a user property with a
   self-generated `client_id` to `/debug/mp/collect` and then `/mp/collect`, optionally the same events under
   a `client_id` from gtag.js as a positive control, and prints what to look for in DebugView, Realtime and
   the standard reports. It answers
   the first question of [protocol §10](analytics_protocol.md#10-what-the-production-kit-must-answer).
   **Step 3 does not start until the maintainer has run it and the events are reported.**
3. **The client core:** the model, validation, the stores, sessions, both transports, the queue, unit
   tests with `MockClient` and `fake_async`, security tests (the secret never leaks; tokens only go
   where design rule 5 allows; no redirects), and a web compile with `tool/check_web_imports.dart`.
4. **The FlutterFire adapter** and its tests.
5. **Docs and wiring:** README, `docs/guides/analytics.md`, CHANGELOGs, `tool/test_all.sh`, the
   `others` leg of the CI unit jobs and the Flutter job, the example relay in `examples/`, and the
   browser leg.
6. **The production verification kit** under `tool/verify_production` style: it sends a few events to
   `/debug/mp/collect` and then to DebugView, and answers the open questions in
   [protocol §10](analytics_protocol.md#10-what-the-production-kit-must-answer). The maintainer runs it
   with a GA4 property and secret they create. Nothing in this repository creates them.
7. **Independent review** of the transport, the store and the security tests by a reviewer who did not
   write them.

Releases are the maintainer's manual step: the packages are not added to `release.yml` or
`publish.yml` in any of these PRs.
