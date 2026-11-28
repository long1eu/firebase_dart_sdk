# firebase_error_reporting_dart

Unofficial pure-Dart reporter of Dart errors to
[Google Cloud Error Reporting](https://cloud.google.com/error-reporting), in the Google Cloud project behind a
Firebase app. For Windows and Linux apps, servers, command-line tools and the web, where FlutterFire's
`firebase_crashlytics` has no implementation. On Android, iOS and macOS, use the official Crashlytics plugin:
it also captures native crashes and symbolicates obfuscated builds.

**Not published yet.** The design is in
[docs/error_reporting_spec.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/error_reporting_spec.md),
and [docs/guides/crash_reporting.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/crash_reporting.md)
compares it with the other choices on each platform. This README grows a full guide before the first release.

## In short

- `ErrorReporter(app, service:, version:, transport:)` formats each error, queues it in an
  `ErrorReportingStore` (memory, `localStorage`, or a file with `package:firebase_error_reporting_dart/io.dart`)
  and sends it to `projects.events.report`.
- `ErrorReportingTransport.relay(url)` sends events to a server you run, which forwards them with its own
  service account: the transport for apps in users' hands. `ErrorReportingTransport.direct(credentials:)` or
  `direct(apiKey:)` call the API directly, for servers and tools you run.
- `runGuarded`, `recordError`, `watchIsolate` (in `io.dart`) and three lines for Flutter's
  `FlutterError.onError` and `PlatformDispatcher.instance.onError` capture errors.
- A rate limit, a capped queue, retries with backoff, `beforeSend` to scrub events, and a persisted
  collection switch.

## Limits

- Dart errors only: no native crashes, no ANRs.
- Error Reporting parses no Dart stack traces. The frames are rewritten into the V8 format (`MessageFormat.v8`,
  the default) or sent as Dart prints them with a `reportLocation` (`MessageFormat.dart`).
  `tool/error_reporting_probe.dart` checks how the console takes each; until it has run, the default is
  unverified.
- No symbolication of obfuscated builds. On the web in a release build, `dart2js` shortens type names, so pass
  `typeName:` to `recordError` for errors you record yourself, and expect the top frame of many errors to be
  the throw helper of `dart2js`.
- One reporter per store: two processes on one file, or two browser tabs on one `localStorage` key, overwrite
  each other's queue and switch.
- If the saved state cannot be read, the reporter starts with `collectionEnabledByDefault`. An app that must
  not report without consent passes `collectionEnabledByDefault: false` and turns collection on after consent.
- Error Reporting keeps 30 days of history, and its API is `v1beta1`.
