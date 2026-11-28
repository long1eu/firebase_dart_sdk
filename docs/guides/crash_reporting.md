# Crash and error reporting

Which tool reports the crashes and errors of a Dart or Flutter program, on each platform. This
repository does not have a Crashlytics client and will not have one:
[crashlytics_feasibility.md](../crashlytics_feasibility.md) explains why (a private protocol, a
key that belongs to Google's SDK, and a service that accepts only Android and Apple apps).

## The short version

| Where the program runs | Use | What you get |
|---|---|---|
| Android, iOS, macOS (Flutter) | the official [`firebase_crashlytics`](https://pub.dev/packages/firebase_crashlytics) plugin | native crashes, ANRs on Android, Dart errors, symbolicated obfuscated builds, the Firebase console |
| Windows, Linux (Flutter or plain Dart) | Cloud Error Reporting or a Sentry-protocol tracker | Dart errors; native crashes only with the tracker |
| Servers, jobs, command-line tools | Cloud Error Reporting or a Sentry-protocol tracker | Dart errors, grouped, with alerts |
| The web | Cloud Error Reporting or a Sentry-protocol tracker | Dart errors |

`firebase_crashlytics` declares Android, iOS and macOS only. On Windows, Linux and the web its calls
have no implementation. A Flutter app that targets mobile and desktop can use Crashlytics on mobile and one
of the two alternatives on desktop. Pick the reporter by `defaultTargetPlatform` when the app starts.

## Android, iOS and macOS: Crashlytics

Follow Firebase's [Get started with Crashlytics for Flutter](https://firebase.google.com/docs/crashlytics/flutter/get-started).
Three points from it matter most:

- Set `FlutterError.onError` and `PlatformDispatcher.instance.onError` yourself. The plugin does not
  install them.
- Obfuscated builds (`--obfuscate --split-debug-info`) need their symbols uploaded with
  `firebase crashlytics:symbols:upload` on Android before the crash is reported; on Apple platforms a
  build phase uploads the dSYM.
- A Dart error sent with `fatal: true` goes out at once, through a rate-limited queue. A non-fatal error
  is sent the next time the app starts.

The packages of this repository run next to the plugin in the same app; nothing in them touches
Crashlytics.

## Windows, Linux, servers and the web

### Cloud Error Reporting

A documented REST API in the Google Cloud project behind your Firebase app
(`projects.events.report`). It groups errors, counts them, keeps 30 days of history, and notifies
you of new and regressed errors. It has no charge of its own; reports become Cloud Logging entries,
which count toward Logging ingestion. Errors appear in the Google Cloud console, not the Firebase
console.

Things to know before you choose it:

- **Credentials.** The API takes an OAuth token with the Error Reporting Writer role, or an API key.
  Never ship a service account key in an app. From an app, send errors to a small server you run, which
  checks the request and forwards it with its own service account. From a server or a job, call the API
  directly with the service account or Application Default Credentials.
- **Dart traces.** Error Reporting parses Java, Python, JavaScript (V8), Ruby, C#, PHP, Go and Rust stack
  traces, not Dart. Send a Dart trace rewritten into one of those formats, or the message with a
  `reportLocation` (file, line, function) taken from the top frame.
- **No symbolication** of obfuscated builds, and no native crashes.

[`firebase_error_reporting_dart`](../../firebase_error_reporting/firebase_error_reporting_dart/) is a Dart
client for it in this repository, not published yet: it captures errors (`runGuarded`, `recordError`, Flutter's
hooks, other isolates), rewrites Dart frames into a format Error Reporting parses, queues reports on disk, and
sends them through a relay (for apps; [`examples/error_reporting_relay`](../../examples/error_reporting_relay/)) or
directly with a service account (for servers). Its README has the setup.

### A Sentry-protocol tracker

[`sentry`](https://pub.dev/packages/sentry) and [`sentry_flutter`](https://pub.dev/packages/sentry_flutter)
are maintained Dart and Flutter SDKs whose pub.dev pages list Windows, Linux, macOS, the web, Android and
iOS. They upload Dart debug symbols for obfuscated builds, and the Flutter SDK can capture native crashes
through its native SDKs. The server is either the hosted service, which has a free tier, or self-hosted.
Read the self-hosted server's license and hardware requirements before planning to run it.

Choose it when you need readable obfuscated stack traces, native crashes on desktop, or breadcrumbs and
release health. Choose Cloud Error Reporting when you want errors to stay in your Google Cloud project
with nothing else to sign up for.

## See also

- [Platforms](platforms.md): what runs where in this repository.
- [Error handling](error_handling.md): the error types of the clients in this repository.
