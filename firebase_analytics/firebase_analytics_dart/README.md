# firebase_analytics_dart

An unofficial pure-Dart client of Google Analytics for Firebase, over the GA4 Measurement Protocol. It is
meant for programs the official SDKs do not cover: Windows and Linux desktop apps, command-line tools and Dart
servers.

**Status: in development, not published.** Google's documentation says a web event is valid only with a
`client_id` that gtag.js has already used, and this client makes its own. Whether Google Analytics reports
such events is being checked with `tool/analytics_probe.dart`. The package will not be released unless they
are. The plan is in [docs/analytics_spec.md](../../docs/analytics_spec.md), the wire facts with their sources
in [docs/analytics_protocol.md](../../docs/analytics_protocol.md), and the comparison with the official SDKs in
[docs/analytics_parity.md](../../docs/analytics_parity.md).

The [Analytics guide](../../docs/guides/analytics.md) covers setup, delivery and errors.

On Android, iOS, macOS and the web, use FlutterFire's `firebase_analytics`. It collects automatic events,
install attribution and device data that the Measurement Protocol cannot produce.

## Use

```dart
import 'package:firebase_analytics_dart/firebase_analytics_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

Future<void> main() async {
  final FirebaseApp app = await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'my-api-key',
      appId: '1:1234567890:web:0123456789abcdef',
      projectId: 'my-project',
      measurementId: 'G-XXXXXXXXXX',
    ),
  );
  final FirebaseAnalytics analytics = FirebaseAnalytics(
    app,
    transport: AnalyticsTransport.relay(Uri.parse('https://example.com/collect')),
  );
  await analytics.logEvent(name: 'level_up', parameters: <String, Object>{'level': 3});
  await analytics.close();
}
```

## What to know first

- **The API secret.** Each Measurement Protocol request needs an API secret of the GA4 data stream, and in a
  program shipped to users anyone can extract it. Apps should use `AnalyticsTransport.relay`: events go to a
  server you run, which checks the App Check and ID tokens, adds the secret and forwards the body to Google.
  `AnalyticsTransport.direct(apiSecret: …)` is for servers and internal tools only.
- **A web stream.** Events go to a GA4 web data stream and show as web traffic. App streams need an app
  instance id that only the native SDKs can produce.
- **Invalid events throw** a `FirebaseAnalyticsException`, where the native SDKs drop them silently. The
  protocol accepts invalid data without an error and never reports it.
- **No automatic events.** `first_open`, `session_start` and screen tracking are reserved by the protocol.
  Sessions are carried by `session_id` and `engagement_time_msec` on every event, and `logScreenView` sends
  `page_view`.
- **No device block by default, and no location is guessed.** Strict validation refused a `device` block
  without `model` and `browser`, which a program cannot read; pass a complete `device` if you can fill it,
  and `userLocation` to report a location.
- **State** (client id, user id, user properties, default parameters, consent, the collection switch and
  unsent events) lives in an `AnalyticsStore`: memory by default, or `FileAnalyticsStore` from
  `package:firebase_analytics_dart/io.dart`. A state that cannot be read may hold an opt-out, so the client
  then collects nothing until the collection switch, consent or a reset is set again.
- **At least once.** A request that times out may still have arrived, and its events are sent again: the
  Measurement Protocol cannot recognise a repeated request.
