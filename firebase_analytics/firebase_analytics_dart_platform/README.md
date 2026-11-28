# firebase_analytics_dart_platform

An unofficial implementation of the platform interface of the official
[`firebase_analytics`](https://pub.dev/packages/firebase_analytics) Flutter plugin, on top of
[`firebase_analytics_dart`](../firebase_analytics_dart), a pure-Dart client of the Google Analytics 4
Measurement Protocol. Your app keeps the official API (`logEvent(...)`, `logLogin()`, `setUserId(...)`, ...), and
the client sends the events to a GA4 web data stream, without the native Firebase SDKs.

It is meant for Flutter apps on Windows and Linux, where `firebase_analytics` has no implementation. On Android,
iOS, macOS and the web, keep FlutterFire's own implementation: it collects automatic events, install attribution
and device data that the Measurement Protocol cannot produce. It is not affiliated with or endorsed by Google or
Firebase.

> **Status: in development, not released.** The package has `publish_to: none`. Google's documentation says a web
> event is valid only with a `client_id` that gtag.js has already used, and the client makes its own. Whether
> Google Analytics reports such events in every report is still being checked (see
> [docs/analytics_spec.md](../../docs/analytics_spec.md), section 10). Do not rely on it yet.

Read [the client's README](../firebase_analytics_dart/README.md) first: the API secret, the web stream, the
throwing validation and the missing automatic events apply here unchanged.

## How to enable it

The adapter needs Dart ^3.12 and Flutter >=3.44. Neither it nor the client is on pub.dev, so depend on them from
this repository:

```yaml
dependencies:
  firebase_core: ^5.1.0
  firebase_analytics: ^13.1.0
  firebase_analytics_dart_platform:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_analytics/firebase_analytics_dart_platform
dependency_overrides:
  firebase_analytics_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_analytics/firebase_analytics_dart
```

On Windows and Linux Flutter registers the package before `main()`. Call `FirebaseAnalyticsDart.configure()` at
the start of `main()`, before `Firebase.initializeApp`, to say where the events go. There is no default transport:
the first `FirebaseAnalytics` call without one throws a `StateError` that says so.

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseAnalyticsDart.configure(
    transport: AnalyticsTransport.relay(Uri.parse('https://example.com/collect')),
  );
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseAnalytics.instance.logLogin(loginMethod: 'password');
  runApp(const MyApp());
}
```

The measurement id comes from `FirebaseOptions.measurementId` (the `G-…` id of a **web** data stream), unless
`configure(measurementId:)` gives another. On Linux pass the options to `Firebase.initializeApp`: there is no native
configuration file to read them from.

On another platform, the same `configure()` call also replaces FlutterFire's implementation.

### Options of `configure`

| Argument | Default | What it does |
| --- | --- | --- |
| `transport` | none; required | `AnalyticsTransport.relay(uri)` posts to a server you run, which checks the request and adds the API secret. `AnalyticsTransport.direct(apiSecret:)` posts to Google Analytics with the secret, which anyone can extract from a shipped app: internal tools only. |
| `measurementId` | `FirebaseOptions.measurementId` | The GA4 web data stream. |
| `store` | one store per isolate (below) | Keeps the client id, the user id, user properties, default parameters, consent, the collection switch and unsent events. |
| `httpClient` | each client creates its own | The `http.Client` of the requests (tests, proxies). |
| `tokenProviderFor`, `appCheckProviderFor` | none | Per FlutterFire app, the providers of the ID token and the App Check token a relay request carries, so the relay can check them. An existing `firebase_app_dart` app of the same name (created by another platform package of this repository) keeps its own user provider. |
| `region` | `AnalyticsRegion.global` | `AnalyticsRegion.eu` sends direct requests to the EU endpoint. |
| `sessionTimeout` | 30 minutes | A new session starts after this long without events. |
| `collectionEnabledByDefault` | `true` | Whether events are collected before `setAnalyticsCollectionEnabled` is first called. |
| `batchDelay`, `maxQueuedEvents` | 5 s, 1,000 | How long a batch waits for more events, and the most events kept unsent. |
| `device`, `userLocation` | none | Sent with every request when set. |
| `onWarning` | `dart:developer` log | Receives what the client cannot throw (a store that fails, a refused request). |
| `useDartCore` | Linux only, when `firebase_core` has no other implementation | Installs a small pure-Dart `firebase_core`. Pass `true` to force it (tests), `false` to never do it. |

`configure()` throws a `StateError` once a client was created, because the configuration is read then.

### The default store

Without `configure(store: ...)`, every app shares one store per isolate; the client keeps each app's records under
keys of its own.

- **Windows, Linux, macOS:** a `FileAnalyticsStore` (from `package:firebase_analytics_dart/io.dart`) in the
  `firebase_dart_analytics` directory under the application support directory (`getApplicationSupportDirectory()`
  of `path_provider`). If the directory cannot be found, the client collects nothing until it can, reports it to
  `onWarning`, and the next call tries again.
- **Web:** memory. The package does not register itself on the web; pass a store if you select it there.
- **Tests:** pass `AnalyticsStore.memory()`.

### `firebase_core` on Linux

`firebase_core` has no Linux implementation. This package installs a small one (apps in memory, `initializeApp`
needs `options`) only while `firebase_core` still has its default implementation. The other platform packages of
this repository do the same, so they can be in one app: whichever registers first provides `firebase_core`. On
Windows `firebase_core` keeps its own implementation. Under `flutter test` the registration leaves `firebase_core`
alone, so that `setupFirebaseCoreMocks` keeps working; call `configure()` to choose otherwise.

## What is implemented

| Official API | Underneath |
| --- | --- |
| `FirebaseAnalytics.instance` | one `firebase_analytics_dart` client per app, created on first use (FlutterFire allows other apps on the web only) |
| `isSupported()` | `true` |
| `appInstanceId`, `getSessionId()` | the client's `appInstanceId` and `sessionId` |
| `logEvent(name:, parameters:, callOptions:)` and every typed helper (`logLogin`, `logPurchase`, ...) | the client's `logEvent`; `callOptions` is ignored |
| `logScreenView(screenName:, screenClass:, parameters:)` | the client's `logScreenView`, sent as `page_view` |
| `setUserId`, `setUserProperty` | mapped; `callOptions` is ignored |
| `setAnalyticsCollectionEnabled`, `resetAnalyticsData`, `setDefaultEventParameters` | mapped |
| `setConsent(...)` | below |
| `setSessionTimeoutDuration` | below |
| `logTransaction`, `initiateOnDeviceConversionMeasurementWith…` | throw `UnimplementedError` |

**Consent.** `adUserDataConsentGranted` and `adPersonalizationSignalsConsentGranted` are sent as the `consent` of
later requests (`GRANTED` or `DENIED`); until one of them is set, no `consent` is sent. While
`analyticsStorageConsentGranted` is false nothing is queued or sent, and `appInstanceId` and `getSessionId()` are
null. `adStorageConsentGranted` is kept and changes nothing: the client collects no advertising identifier. The
three web storage flags (`functionality…`, `personalization…`, `security…`) are accepted and ignored.

**App lifecycle.** The package listens to Flutter's `AppLifecycleListener` and tells the client when the app is in
use (`resumed`) or not (any other state): engagement time counts only while it is, and leaving it sends the queue.
The listener starts with the first call after the binding exists, so calls made before
`WidgetsFlutterBinding.ensureInitialized()` work too.

**Sending now.** The official API has no `flush`. `FirebaseAnalyticsDart.clientFor(app)` returns the client, whose
`flush()` sends the queue and `close()` sends it and releases the client.

## How it differs from the native plugins

These throw, or behave differently, where the native plugins do not:

- **Invalid events throw** a `FirebaseException` of `firebase_core` with the plugin `firebase_analytics` and the
  client's code (`invalid-event-name`, `reserved-name`, `invalid-parameter`, `too-many-parameters`,
  `invalid-user-property`, `too-many-user-properties`, `invalid-user-id`, `event-too-large`). The native SDKs drop
  them and log a line; the Measurement Protocol accepts invalid data without an error and never reports it.
- **`logAdImpression` throws `reserved-name`**: `ad_impression` is for app streams only. So does `logInAppPurchase`
  where it reaches the package (`in_app_purchase`); on Windows and Linux `FirebaseAnalytics` itself throws
  `UnimplementedError` for it before that, as it does for `logTransaction` and the on-device conversion methods.
- **`logTransaction` and `initiateOnDeviceConversionMeasurement`** throw `UnimplementedError` with a message that
  says why: StoreKit transactions and on-device conversion measurement exist in the native iOS and macOS SDKs only.
- **`setSessionTimeoutDuration` works only before the first event.** The client takes the timeout as configuration,
  so the call creates the client again with the new timeout, keeping its state. After the first `logEvent` or
  `logScreenView` of the app in this process (a refused one counts), it throws a `StateError`; set the timeout at
  start-up, or with `configure(sessionTimeout:)`.
- **`logScreenView` sends `page_view`**, with `page_title` set to the screen name, `page_location` set to
  `app://<app id>/<screen name>` and the class in `screen_class`, because `screen_view` is for app streams only. It
  needs a `screenName`: without one it throws `invalid-parameter`.
- **No automatic events** (`first_open`, `session_start`, `user_engagement`, screen tracking), no install
  attribution, no audiences. Sessions are carried by `session_id` and `engagement_time_msec` on every event.
- **The data shows as web traffic** of the web data stream.

The full comparison is in [docs/analytics_parity.md](../../docs/analytics_parity.md).

## Tests

`flutter test` drives the official `firebase_analytics` API against a fake relay (`MockClient`): nothing reaches
Google Analytics.
