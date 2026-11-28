# firebase_error_reporting_dart

Unofficial pure-Dart reporter of Dart errors to
[Google Cloud Error Reporting](https://cloud.google.com/error-reporting), in the Google Cloud project behind a
Firebase app. For Windows and Linux apps, servers, command-line tools and the web, where FlutterFire's
`firebase_crashlytics` has no implementation.

**On Android, iOS and macOS, use the official Crashlytics plugin instead:** it also captures native crashes and
ANRs and symbolicates obfuscated builds. A Flutter app can use both: Crashlytics on mobile, this package on
desktop and the web. [docs/guides/crash_reporting.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/guides/crash_reporting.md)
compares the choices on each platform.

**Not published yet.** The design is in
[docs/error_reporting_spec.md](https://github.com/long1eu/firebase_dart_sdk/blob/main/docs/error_reporting_spec.md).

## What you get

Errors in the Error Reporting page of the Google Cloud console, grouped by type and stack, with counts, first
and last occurrence, a resolution status, and notifications for new and regressed errors. Error Reporting has no
charge of its own; reports become Cloud Logging entries, which count toward Logging ingestion. It keeps 30 days.

## Set up a project

1. Enable the Error Reporting API in the project of your Firebase app.
2. For an app in users' hands, deploy a relay (below): a small server of yours that checks each report and
   forwards it with its own service account. For a server or a tool you run, give its service account the role
   Error Reporting Writer (`roles/errorreporting.writer`).

## Report from an app: through a relay

The app holds no credential of the project. It sends each report to your relay with its App Check token and,
when a user is signed in, the user's ID token; the relay checks both, rebuilds the report from the fields it
trusts, sets the user from the verified token, and forwards it.
[`examples/error_reporting_relay`](https://github.com/long1eu/firebase_dart_sdk/tree/main/examples/error_reporting_relay)
is a complete relay on `package:shelf`.

```dart
import 'dart:io';

import 'package:firebase_error_reporting_dart/firebase_error_reporting_dart.dart';
import 'package:firebase_error_reporting_dart/io.dart';

final ErrorReporter reporter = ErrorReporter(
  app,
  service: 'notes-desktop',
  version: '1.4.0',
  transport: ErrorReportingTransport.relay(Uri.parse('https://relay.example.com/errors')),
  store: FileErrorReportingStore(Directory.systemTemp),
);
```

`service` is what the console groups and filters by; `version` is the release (`1.4.0`), not a build number,
because Error Reporting keeps at most 10,000 pairs of a version and an error group. Use a directory of your app
for the store (from `path_provider` in Flutter), so reports that could not be sent survive a restart. In a
browser use `ErrorReportingStore.localStorage()`.

## Report from a server or a tool: directly

```dart
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

final OAuthTokenProvider credentials = OAuthTokenProvider.serviceAccount(
  jsonDecode(File(Platform.environment['SERVICE_ACCOUNT_KEY_FILE']!).readAsStringSync()),
  scopes: const <String>['https://www.googleapis.com/auth/cloud-platform'],
);
final ErrorReporter reporter = ErrorReporter(
  app,
  service: 'billing-worker',
  version: '2.0.1',
  transport: ErrorReportingTransport.direct(credentials: credentials),
);
```

On Google Cloud, `applicationDefaultCredentials(scopes: ...)` from `package:firebase_auth_providers_dart/adc.dart`
gives the tokens of the service's own account. `ErrorReportingTransport.direct(apiKey: ...)` takes an API key
restricted to the Error Reporting API instead; anyone who extracts it can post errors into the project, so use it
only for tools you run yourself. Never put a service account key in an app.

## Capture errors

```dart
await reporter.runGuarded(() async {
  // The program: errors that escape it, and errors of work it starts and nobody awaits, are reported.
});
```

```dart
try {
  await File('notes.json').readAsString();
} on FileSystemException catch (error, stack) {
  await reporter.recordError(error, stack, reason: 'while loading the notes');
}
```

In Flutter, set the two hooks yourself before `runApp`, as with Crashlytics:

```dart flutter
FlutterError.onError = (details) {
  FlutterError.presentError(details);
  reporter.recordError(details.exception, details.stack, reason: details.context?.toString(), fatal: true);
};
PlatformDispatcher.instance.onError = (error, stack) {
  reporter.recordError(error, stack, fatal: true);
  return true;
};
```

`fatal: true` sends the report at once and marks the header `[fatal]`. Errors of other isolates:
`reporter.watchIsolate(isolate)` from `io.dart`. Before a program exits, `await reporter.close()` sends what is
queued (for up to 10 seconds) and keeps the rest in the store for the next run.

## Users, requests and privacy

```dart
await reporter.setUser('user-7f3a');
await reporter.recordError(
  StateError('order not found'),
  StackTrace.current,
  httpRequest: const HttpRequestContext(method: 'GET', url: '/orders/42', responseStatusCode: 404),
);
await reporter.setCollectionEnabled(false);
```

- No user is sent until `setUser`; the console shows it to everyone with access to the project, so send an
  opaque id. Through a relay the user is the uid of the verified ID token.
- `beforeSend` sees each report before it is queued and can change it or drop it: remove e-mail addresses or file
  paths (`file:///Users/...`) from messages.
- `setCollectionEnabled(false)` stops recording, drops the queue and is saved. An app that must not report
  without consent passes `collectionEnabledByDefault: false` and turns collection on after consent; if the saved
  state cannot be read, the reporter starts with the default.

```dart
final ErrorReporter scrubbing = ErrorReporter(
  app,
  service: 'notes-desktop',
  transport: ErrorReportingTransport.relay(Uri.parse('https://relay.example.com/errors')),
  beforeSend: (ErrorEvent event) => event.copyWith(
    message: event.message.replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'), '<email>'),
  ),
);
```

## How it behaves

- Reports are queued (at most 100; the oldest go first; none older than 30 days) and sent one at a time, two
  seconds after they are recorded, on `flush()` and `close()`, or at once when fatal.
- A rate limit keeps a loop of errors from using up the project's quota: 30 reports a minute, and 5 a minute of
  the same error at the same place. The next report of a kind says how many like it were dropped.
- Network errors, 408, 429 and 5xx are retried with backoff (never sooner than `Retry-After`); a report that
  fails ten times in a row is dropped. Through the relay, 401 and 403 pause the queue for five minutes. Other
  refusals drop the report. Problems go to `onDiagnostic` (by default `dart:developer`'s `log`); the reporter
  never throws into your code.

## Limits

- Dart errors only: no native crashes, no ANRs.
- Error Reporting parses no Dart stack traces. The frames are rewritten into the V8 format
  (`MessageFormat.v8`, the default) or sent as Dart prints them with a `reportLocation` (`MessageFormat.dart`).
  `tool/error_reporting_probe.dart` checks how the console takes each; until it has run, the default is
  unverified.
- No symbolication of obfuscated builds: build without `--obfuscate` when readable reports matter.
- On the web in a release build, `dart2js` shortens type names: pass `typeName:` to `recordError` for errors
  you record yourself, and expect the top frame of many errors to be the throw helper of `dart2js`.
- One reporter per store: two processes on one file, or two browser tabs on one `localStorage` key, overwrite
  each other's queue and switch.
- The API is `v1beta1`, and Error Reporting keeps 30 days.
