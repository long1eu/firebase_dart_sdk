# Analytics

`firebase_analytics_dart` is an unofficial pure-Dart client of Google Analytics for Firebase, over the GA4
Measurement Protocol. It is for programs the official SDKs do not cover: Windows and Linux desktop apps,
command-line tools and Dart servers. It is **in development and not released** (`publish_to: none`, version
`0.1.0-dev.1`): depend on it from this repository. Whether Google Analytics reports events from a `client_id`
that gtag.js never used is still being checked (see [Open questions](#open-questions)); the package will not be
released unless it does. The wire facts with their sources are in [analytics_protocol.md](../analytics_protocol.md),
the plan in [analytics_spec.md](../analytics_spec.md) and the comparison with the official SDKs in
[analytics_parity.md](../analytics_parity.md).

## What it is, and what it is not

It is a Measurement Protocol client. It sends events, user properties and a user id as JSON to a GA4 **web** data
stream. It is not a port of the native SDKs:

- **No automatic events.** `first_open`, `session_start`, `user_engagement` and screen tracking are reserved by
  the protocol. You log every event yourself.
- **No attribution, no audiences, no device data.** The Measurement Protocol cannot produce them.
- **The data shows as web traffic** of the web stream, because app streams need an app instance id that only the
  native SDKs can make.
- **Invalid events throw** where the native SDKs drop them silently (see [Errors](#errors)).

On Android, iOS, macOS and the web, use FlutterFire's `firebase_analytics`.

## Choose a transport

Every Measurement Protocol request needs an API secret of the data stream, and in a program shipped to users
anyone can extract it and send fake events into your property.

| Transport | Use it for | The secret |
|---|---|---|
| `AnalyticsTransport.relay(Uri)` | Apps. Recommended. | Only on your server. The client sends the App Check token and, when someone is signed in, the ID token; the relay checks them, adds the secret and forwards the body. |
| `AnalyticsTransport.direct(apiSecret: ...)` | Servers and internal tools. | In the program. |

A relay is a small server. [`examples/analytics_relay`](../../examples/analytics_relay/README.md) is one on
`package:shelf`, with the checks and the limits it applies. The relay URL must be `https`, or `http` to a loopback
host for local development.

## Set up

Add the package from this repository, and `firebase_app_dart`:

```yaml
dependencies:
  firebase_app_dart: ^0.2.0
  firebase_analytics_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_analytics/firebase_analytics_dart
```

Create the client from a `FirebaseApp`. The measurement id (`G-...`) is the one of a **web** data stream; it
comes from `FirebaseOptions.measurementId` unless you pass `measurementId:`. Constructing the client sends
nothing.

```dart
import 'package:firebase_analytics_dart/firebase_analytics_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

Future<FirebaseAnalytics> create() async {
  final FirebaseApp app = await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'my-api-key',
      appId: '1:1234567890:web:0123456789abcdef',
      projectId: 'my-project',
      measurementId: 'G-XXXXXXXXXX',
    ),
  );
  return FirebaseAnalytics(
    app,
    transport: AnalyticsTransport.relay(Uri.parse('https://relay.example.com/collect')),
  );
}
```

### The store

The client id, the user id, user properties, default parameters, consent, the collection switch and the unsent
events live in an `AnalyticsStore`. The default is memory: everything is forgotten when the program ends, and
every start is a new client id. For anything that runs more than once, use a file store on the VM:

```dart
import 'dart:io';

import 'package:firebase_analytics_dart/io.dart';

FirebaseAnalytics withFiles(FirebaseApp app) {
  final String home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  return FirebaseAnalytics(
    app,
    transport: AnalyticsTransport.relay(Uri.parse('https://relay.example.com/collect')),
    store: FileAnalyticsStore(Directory('$home/.my_app/analytics')),
  );
}
```

The files hold the client id, the user id and unsent events, so keep them where the user's other application data
lives. `io.dart` needs `dart:io`; **on the web** there is no file store, so the web uses memory (or an
`AnalyticsStore` of your own, which is an interface of `read` and `write`). A state that cannot be read may hold
an opt-out, so the client then collects nothing until the collection switch, consent or a reset is set again.

## Log events

```dart
Future<void> logging(FirebaseAnalytics analytics) async {
  await analytics.logEvent(name: 'level_up', parameters: <String, Object?>{'level': 3, 'character': 'mage'});
  await analytics.logScreenView(screenName: 'home', screenClass: 'HomeScreen');
}
```

Parameter values are `String` (at most 100 characters), `int`, `double` or `bool`; `items` is a list of maps, as
in GA4's e-commerce events. An event has at most 23 parameters of its own, because the client adds `session_id`
and `engagement_time_msec`. `logScreenView` sends `page_view` (`screen_view` is for app streams only), with
`page_title` set to the screen name, `page_location` set to `app://<app id>/<screen name>` and the class in
`screen_class`.

### User id, user properties, default parameters

```dart
Future<void> userState(FirebaseAnalytics analytics) async {
  await analytics.setUserId('user-1234'); // not an email address or other personal data
  await analytics.setUserProperty(name: 'plan', value: 'free'); // a null value removes it
  await analytics.setDefaultEventParameters(<String, Object?>{'app_flavor': 'beta'});
}
```

Default parameters are added to every later event; an event's own value of the same name wins; `null` as the whole
map clears them. All of this is kept in the store.

### Consent and the collection switch

```dart
Future<void> privacy(FirebaseAnalytics analytics) async {
  await analytics.setAnalyticsCollectionEnabled(false); // drops the queue and stops sending
  await analytics.setConsent(analyticsStorage: false, adUserData: false, adPersonalization: false);
  await analytics.resetAnalyticsData(); // a new client id, no user id, no properties, no queue
}
```

While collection is off or `analyticsStorage` is denied, valid events are dropped and nothing is sent, and
`appInstanceId` and `sessionId` are null. `adUserData` and `adPersonalization` go out as the `consent` of later
requests; `adStorage` is kept and changes nothing, since the client collects no advertising identifier.
`collectionEnabledByDefault:` sets what holds until the switch is first called.

### Sessions and engagement

A session starts at the first event and after `sessionTimeout` (30 minutes) without one. It is carried by the
`session_id` and `engagement_time_msec` parameters of every event. `await analytics.sessionId` and
`await analytics.appInstanceId` read the current ones. Engagement time counts while the app is active. A
command-line tool or a server is always active; a desktop app should say when it is not, which also sends the
queue:

```dart
void lifecycle(FirebaseAnalytics analytics, bool inForeground) {
  analytics.setAppActive(inForeground);
}
```

### Send and close

```dart
Future<void> finish(FirebaseAnalytics analytics) async {
  await analytics.flush(); // send what is queued now; never throws
  await analytics.close(); // flush, save, release the HTTP client
}
```

Always `close()` a short-lived program, or its last events wait for the next run (with a file store) or are lost
(with memory). After `close()`, calls throw a `StateError`.

## Errors

Rules of the protocol are checked before anything is queued, and a break throws a `FirebaseAnalyticsException`
(a `FirebaseException` of the plugin `firebase_analytics`). The native SDKs drop an invalid event and log a line;
here the Measurement Protocol accepts invalid data with a 2xx answer and never reports it, so a mistake would
stay hidden until someone looks at a report. Branch on `code`:

| Code | Cause |
|---|---|
| `invalid-event-name` | Empty, over 40 characters, or not letters, digits and `_` starting with a letter. |
| `reserved-name` | An event, parameter or user property name, or its prefix, is reserved by the protocol or set by the client. |
| `invalid-parameter` | A parameter name or value breaks a rule: length, type, a number that is not finite, an `items` entry. |
| `too-many-parameters` | More parameters than an event may carry. |
| `invalid-user-property`, `too-many-user-properties` | The name or value breaks a rule, or setting it would pass 25 properties. |
| `invalid-user-id` | Empty or over 256 characters. |
| `event-too-large` | The event alone would not fit in one request body. |

```dart
Future<void> safeLog(FirebaseAnalytics analytics, String name) async {
  try {
    await analytics.logEvent(name: name);
  } on FirebaseAnalyticsException catch (e) {
    print('Not logged: ${e.code}');
  }
}
```

Delivery problems never throw; they are handled as below. A bad `measurementId`, `sessionTimeout`,
`maxQueuedEvents` or `batchDelay` throws an `ArgumentError` from the constructor.

## Delivery

Events are queued in the store and sent in batches of at most 25 events and 130,000 bytes: `batchDelay` (5 s)
after the first event of a batch, when a batch is full, on `flush` and on `close`. The queue keeps at most
`maxQueuedEvents` (1,000); past that the oldest go first, and events older than about 72 hours are dropped,
which is as long as the protocol takes a timestamp. By status:

| Answer | What happens |
|---|---|
| 2xx | Delivered. |
| 401, 403, 408, 429, 5xx, no network, a timeout | The events stay queued and are retried with backoff (2 s doubling to 5 minutes). 401 and 403 are kept because a wrong relay setting or an expired token is fixed on your side, and the events should survive until it is. |
| any other 4xx | The request can never succeed: its events are dropped, with a warning to `onWarning`. |

Delivery is **at least once**. A request that times out may still have arrived, and its events are sent again; the
Measurement Protocol cannot recognise a repeated request. `onWarning` receives what the client cannot throw (a
store that fails, a refused request); by default it goes to `dart:developer`'s `log`.

## Flutter

The [`firebase_analytics_dart_platform`](../../firebase_analytics/firebase_analytics_dart_platform/README.md)
adapter keeps the official `firebase_analytics` API (`FirebaseAnalytics.instance.logEvent(...)`) on Windows and
Linux, where that plugin has no implementation. Call `FirebaseAnalyticsDart.configure(...)` at the start of
`main()`, before `Firebase.initializeApp`; there is no default transport.

```dart flutter
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseAnalyticsDart.configure(
    transport: AnalyticsTransport.relay(Uri.parse('https://relay.example.com/collect')),
  );
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseAnalytics.instance.logLogin(loginMethod: 'password');
  runApp(const MyApp());
}
```

The default store is a file store under the application support directory. Some official methods throw where the
native plugin does not: `logTransaction`, `logInAppPurchase` and the on-device conversion methods throw
`UnimplementedError`, `logAdImpression` throws `reserved-name`, and `setSessionTimeoutDuration` works only before
the first event. The adapter's README lists every difference.

## Experiment properties

`setExperimentProperties(Map<String, String?>)` sets `firebase_exp_<id>` user properties. It is for integrations,
not apps: Remote Config's A/B testing hand-off calls it. These names break two rules `setUserProperty` enforces
(the `firebase_` prefix and the 24-character limit), and whether a web stream keeps them is **not verified**
(protocol [section 10, question 7](../analytics_protocol.md)). Until it is, the hand-off is best effort.

## Limits

At most 25 events per request, 130,000 bytes per body, 25 user properties, event and parameter names of 40
characters, parameter values of 100, user property values of 36 and user ids of 256, counted as the protocol
counts them; the constants are in `AnalyticsLimits`. The reserved names and the sources of every number are in
[analytics_protocol.md](../analytics_protocol.md), section 4. By default no `device` block is sent, because strict
validation refused one without `model` and `browser`, and no location is guessed: pass `device:` and
`userLocation:` to the constructor to send them.

## Open questions

Whether such events reach the standard reports (not only DebugView and Realtime), whether geography is reported
without `user_location`, and the exact limits the validation server applies are listed in
[analytics_protocol.md, section 10](../analytics_protocol.md). Do not rely on the package for reporting you need
yet.

A second transport that speaks gtag.js's own protocol, so that events have a client id Google Analytics already
knows, is planned and not built: [analytics_gtag.md](../analytics_gtag.md).
