# Crashlytics: feasibility

Can this repository ship a pure-Dart Crashlytics client, the way it ships Firestore, Storage, Realtime
Database and (soon) Analytics? This document answers that from the source of the official SDKs and from
Google's published documentation and terms. It is written before any code, as
[contributing_a_product.md](contributing_a_product.md) asks, and no code follows until it has been read
and a decision taken.

**Short answer: do not build it.** The report upload uses a private Google API, authenticated with an
API key that Google compiles into its own SDKs, not with the developer's key. No document describes
the protocol for third-party use. The license for Crashlytics covers integrating Google's SDK, not
reimplementing it. Even if the protocol were usable, a Windows or Linux app would have to pose as an
Android or Apple app to be accepted, and the console has no way to symbolicate its Dart frames. Section 6 has the full recommendation and
section 5 the alternatives.

No request was sent to any Crashlytics or Google API endpoint to write this document. Everything below
comes from reading source and documentation.

## Sources

| Short name | Repository | Commit (date) | Paths read |
|---|---|---|---|
| [AND] | `firebase/firebase-android-sdk` | `2cfdd0389569ef63353d0ce2cd1bf1d63fb49b83` (2026-11-20) | `firebase-crashlytics/`, `transport/` |
| [IOS] | `firebase/firebase-ios-sdk` | `cef246feaa31a404622b4b0830da8e78798810fd` (2026-11-20) | `Crashlytics/`, `Package.swift`, `FirebaseCrashlytics.podspec` |
| [GDT] | `google/GoogleDataTransport` | `4c7af6cf54bac608ac87947f2cc9b8f8ebf5fc34` (2026-11-13), version 10.1.1 | `GoogleDataTransport/` |
| [FF] | `firebase/flutterfire` | `6a80b1b5eea1ea86ba8c7e7bf2a8525cabb77126` (2026-11-20), `firebase_crashlytics` 6.1.0 | `packages/firebase_crashlytics/`, `docs/crashlytics/` |
| [UNITY] | `firebase/firebase-unity-sdk` | `3090c4cb3f99c0565f0176c351368fa1a20b7827` (2026-11-25) | `crashlytics/` |
| [CPP] | `firebase/firebase-cpp-sdk` | `09d2e7a6d2a98854b8358c39bc0b50c2970b8e1d` (2026-11-18) | top-level tree |

Abbreviations in paths: `CR/` is
`firebase-crashlytics/src/main/java/com/google/firebase/crashlytics/internal/` in [AND]; `CCT/` is
`transport/transport-backend-cct/src/main/java/com/google/android/datatransport/cct/` in [AND]; `C/` is
`Crashlytics/Crashlytics/` in [IOS].

Documentation and terms, all read on 2026-11-28:

| Short name | Page | Date shown |
|---|---|---|
| [CLS-TOS] | [Firebase Crashlytics and Firebase App Distribution Terms of Service](https://firebase.google.com/terms/crashlytics) | Last updated June 1, 2023 |
| [FB-TOS] | [Firebase terms](https://firebase.google.com/terms) (the table of which terms govern which service) | September 24, 2026 |
| [API-TOS] | [Google APIs Terms of Service](https://developers.google.com/terms) | November 9, 2021 |
| [CLS-DOCS] | [Crashlytics overview](https://firebase.google.com/docs/crashlytics) | none |
| [CLS-FLUTTER] | [Get started with Crashlytics for Flutter](https://firebase.google.com/docs/crashlytics/flutter/get-started) | none |
| [REST] | [Firebase REST API reference index](https://firebase.google.com/docs/reference/rest) | none |
| [ER-REPORT] | [Error Reporting `projects.events.report`](https://cloud.google.com/error-reporting/reference/rest/v1beta1/projects.events/report) | none |
| [ER-FORMAT] | [Formatting errors for Error Reporting](https://cloud.google.com/error-reporting/docs/formatting-error-messages) | none |
| [ER-QUOTA] | [Error Reporting quotas and limits](https://cloud.google.com/error-reporting/quotas) | none |

## 1. The protocol

A Crashlytics client talks to two services: a settings service, and a report upload that goes through
Google's data transport library ("datatransport" on Android, GoogleDataTransport on Apple platforms).
Android and Apple use the same hosts, but they encode the report differently.

### 1.1 Settings

| | Android | Apple |
|---|---|---|
| URL | `https://firebase-settings.crashlytics.com/spi/v2/platforms/android/gmp/%s/settings`, where `%s` is the Google app id (`CR/settings/SettingsController.java:45-46`) | the same host (`Crashlytics/Shared/FIRCLSConstants.m:31`) with `platforms/<p>`, where `<p>` is `ios`, `mac` or `tvos` (`C/Components/FIRCLSApplication.m:44-54`). watchOS and visionOS say `ios` |
| Method | `GET`, 10 s timeouts | `GET`, 10 s timeout |
| Query | `build_version`, `display_version`, `source` (install source), `instance` (a SHA-1 over the build) (`CR/settings/DefaultSettingsSpiCall.java`) | the same four (`C/Settings/FIRCLSSettingsManager.m`) |
| Headers | `X-CRASHLYTICS-GOOGLE-APP-ID`, `X-CRASHLYTICS-API-CLIENT-TYPE: android`, `X-CRASHLYTICS-API-CLIENT-VERSION`, `X-CRASHLYTICS-INSTALLATION-ID` (a Crashlytics UUID, not the Firebase installation id), device and OS headers, and a fixed `X-CRASHLYTICS-DEVELOPER-TOKEN` compiled into the SDK (`DefaultSettingsSpiCall.java:33-52, 95`) | the same set with Apple names, plus its own fixed `X-Crashlytics-Developer-Token` (`C/Settings/Operations/FIRCLSNetworkOperation.m`) |
| Authentication | none beyond the developer token; no API key, no Firebase Installations token | the same |

Fields used from the response (`CR/settings/SettingsV3JsonTransform.java`, `C/Models/FIRCLSSettings.m`):
`settings_version` (Android parses version 3 only), `cache_duration` (default 3,600 s),
`features.collect_reports`, `features.collect_anrs` (Android), `features.collect_logged_exceptions`
(Apple), `session.max_custom_exception_events` (default 8), and the on-demand rate limits
`on_demand_upload_rate_per_minute` (default 10), `on_demand_backoff_base` (Android 1.2, Apple 1.5) and
`on_demand_backoff_step_duration_seconds` (Android 60, Apple 6). Both SDKs cache the response and fetch
again when it expires or when the build changes.

### 1.2 The report

**Android** builds a `CrashlyticsReport` (`CR/model/CrashlyticsReport.java`, AutoValue with generated
encoders) and encodes it as **JSON** (`CR/model/serialization/CrashlyticsReportJsonTransform.java`); the
same JSON is the on-disk format. Top-level fields: `sdkVersion`, `gmpAppId`, `platform` (fixed at `4`,
`REPORT_ANDROID_PLATFORM`, `CR/common/CrashlyticsReportDataCapture.java:68`), `installationUuid`,
`firebaseInstallationId`, `firebaseAuthenticationToken`, `appQualitySessionId`, `buildVersion`,
`displayVersion`, then either a `session` (Java crashes and logged errors) or an `ndkPayload` (native
crashes, raw files). A session holds the app, OS (`platform` 3), device and user, and a list of events.
An event holds the timestamp, the `type`, logs, custom keys, rollouts, and an `execution` with threads,
frames (`pc`, `symbol`, `file`, `offset`), the exception chain, a signal and binary images.

**Apple** sends a protobuf `google_crashlytics.Report`
(`Crashlytics/ProtoSupport/Protos/crashlytics.proto`, generated nanopb in `Crashlytics/Protogen/`):
`sdk_version`, `gmp_app_id`, `platform` (enum `IOS = 1`, `TVOS = 2`, `MAC_OS_X = 5`; nothing else),
`installation_uuid`, `build_version`, `display_version`, `firebase_installation_id`,
`app_quality_session_id`, `firebase_authentication_token` (tag 19 in the generated code, not in the
`.proto`), and `apple_payload`: the raw `.clsrecord` files of the report folder as bytes
(`C/Models/Record/FIRCLSReportAdapter.m`). The `.clsrecord` files are an undocumented, line-oriented
format written by the crash handlers (`C/Models/FIRCLSInternalReport.m` lists them: `metadata`,
`binary_images`, `exception`, `signal`, `mach_exception`, `custom_exception_a/b`, `errors_a/b`,
`log_a/b`, key-value files, `custom_fatal`). The server parses and symbolicates them.

So there is no single report format: one client would have to produce the Android JSON schema or the
Apple protobuf with its embedded record files, and neither is documented.

### 1.3 Upload

Both platforms post to the same private endpoint:

    https://crashlyticsreports-pa.googleapis.com/v1/firelog/legacy/batchlog

- **In source the URL is obfuscated.** It is split into two strings whose characters are interleaved at
  run time: `CommonUtils.mergeStrings` (`CR/common/CommonUtils.java:96`), used for
  `DataTransportCrashlyticsReportSender.CRASHLYTICS_ENDPOINT`
  (`CR/send/DataTransportCrashlyticsReportSender.java:43-44`). The Apple copy is in
  `GoogleDataTransport/GDTCORLibrary/GDTCOREndpoints.m` [GDT], as target `kGDTCORTargetCSH` (1002).
- **The API key is Google's, not the app's.** Android sends
  `X-Goog-Api-Key: CommonUtils.CRASHLYTICS_API_KEY` (`CR/common/CommonUtils.java:51-52`), a fixed
  key built into the Crashlytics SDK the same way. GoogleDataTransport sends its own fixed key for this
  target (`GoogleDataTransport/GDTCCTLibrary/GDTCCTUploader.m`, `-FLLAndCSHAndINTAPIKey`). Neither
  request uses the `apiKey` of the developer's `FirebaseOptions`. This document does not reproduce
  either key.
- **Envelope.** A `BatchedLogRequest` of `LogRequest`s, each with client info, a log source, and log
  events that carry the report. Android: gzipped JSON, `Content-Type: application/json`, log source name
  `FIREBASE_CRASHLYTICS_REPORT`, the report JSON as a string in `sourceExtensionJsonProto3`,
  `clientType` 23 (Android Firebase) with `androidClientInfo` (`CCT/CctTransportBackend.java:364-430`,
  `CCT/internal/*.java`). Apple: protobuf, `Content-Type: application/x-protobuf`, gzipped when that is
  smaller, log source `1206` (`C/FIRCrashlytics.m:88, 150`), the report bytes in `source_extension`,
  `client_type` 15 (iOS Firebase) with `ios_client_info` or `mac_client_info`
  (`GoogleDataTransport/GDTCCTLibrary/GDTCCTNanopbHelpers.m`).
- **Responses.** Android: 200 is success; 404 and 5xx are retried; 400 and anything else drop the event.
  Apple: 2xx success; 404, 429 and 5xx retried; other 4xx dropped. Both honour
  `next_request_wait_millis` in the response.

### 1.4 Authentication

Three things identify the sender, none of them a credential the developer controls:

1. the shared Google API key in the header (above);
2. the Google app id (`gmpAppId` / `gmp_app_id`) in the report;
3. the Firebase Installations id and **auth token**, in the report body, not in a header
   (`CrashlyticsReportDataCapture.java:182-184`; `C/Models/FIRCLSInstallIdentifierModel.m`). Android
   fetches them with a 10 s timeout and, when collection is off, writes a synthetic `SYN_<uuid>` id
   instead (`CR/common/IdManager.java:184`).

Item 3 is reachable from Dart: the JS SDK talks to Firebase Installations over REST, and the Remote
Config work in this repository needs the same client. Item 1 is the problem: the only key the upload accepts, as far as the source
shows, is one that belongs to Google's SDK.

### 1.5 Batching and retry

| | Android | Apple |
|---|---|---|
| Unsent reports kept | 4 finalized (`maxCompleteSessionsCount`), 8 open sessions (`CR/persistence/CrashlyticsReportPersistence.java:60`) | 4 (`FIRCLSMaxUnsentReports`, `C/Controllers/FIRCLSExistingReportManager.m:30`, "should stay in sync with the Android SDK") |
| Logged errors per session | 8, oldest dropped (`max_custom_exception_events`) | 8 |
| When reports go out | at the next launch, or right away for an on-demand fatal | the same |
| Transport priority | every report `Event.ofUrgent` (`CR/send/ReportQueue.java:157`) | every report `GDTCOREventQoSFast` (`C/Controllers/FIRCLSReportUploader.m`) |
| Transport retry | job scheduler with backoff `3^(n-1) × delta`; dropped after 16 attempts (`SQLiteEventStore.MAX_RETRIES`); events older than a week are deleted; 10 MiB store | 30 s upload timer; 15 min default wait after a failure; events expire after 7 days; 20 MB store |
| Consent | `setCrashlyticsCollectionEnabled`, manifest flag, Firebase default; when off, `checkForUnsentReports` then `sendUnsentReports` or `deleteUnsentReports` (`CR/common/DataCollectionArbiter.java`) | the same API (`C/Controllers/FIRCLSReportManager.m`) |

### 1.6 Fatal, non-fatal and on-demand events

- **Fatal crash.** Captured by the uncaught-exception handler (Android) or by signal, Mach exception and
  `NSException` handlers (Apple) while the process dies. Event `type: "crash"` on Android
  (`CR/common/SessionReportingCoordinator.java:68`), stored as high priority, so the session is marked
  `crashed`. It is sent at the next launch.
- **Non-fatal** (`recordException`, `recordError`, `recordExceptionModel`). Event `type: "error"`
  (`SessionReportingCoordinator.java:69`), normal priority, subject to the cap of 8 per session. It
  stays in the current session and is sent at the next launch.
- **On-demand fatal.** Android `CrashlyticsCore.logFatalException` and Apple
  `recordOnDemandExceptionModel` (`C/FIRCrashlytics.m:491-503`). The app keeps running. The SDK closes the
  current session as crashed, opens a new one, and sends the closed session at once through a
  rate-limited queue: capacity `on_demand_upload_rate_per_minute`, a pause of
  `60 / rate × base^step` seconds after each send (at most an hour), and events dropped when the queue is
  full. FlutterFire uses this path for `fatal: true` (section 4).
- **Android only:** ANRs (`type: "anr"`, from `ApplicationExitInfo`, when `collect_anrs` is on) and NDK
  crashes (`ndkPayload` instead of a session).

## 2. Is it a public API?

**No. None of the endpoints is documented for third-party use.**

- The Firebase REST reference [REST] lists no Crashlytics API. No Firebase or Google Cloud page
  describes `firebase-settings.crashlytics.com` or `crashlyticsreports-pa.googleapis.com`.
- By Google's naming convention, the `-pa` suffix in `crashlyticsreports-pa.googleapis.com` marks a private API
  that serves Google's own clients, as opposed to the public `*.googleapis.com` APIs listed in the API
  Library.
- The SDKs hide the URLs and keys behind string interleaving (section 1.3). That is not security, but it
  shows the values are not meant to be reused.

**What the terms say.** The Firebase terms page [FB-TOS] puts Crashlytics under its own agreement,
[CLS-TOS], together with the Firebase Data Processing and Security Terms. The Google APIs Terms
[API-TOS] are the general terms for Google APIs.

- [CLS-TOS] §2.2(b) licenses the developer to "download, install and use a reasonable number of copies
  of the Crashlytics software development kit", "solely for the integration of the Software into an
  Application". §2.12: "no other license is granted, no other use is permitted".
- [CLS-TOS] §2.3(b) forbids attempts to "disassemble, decompile, reverse engineer, decipher, translate"
  the software to discover its source code, algorithms or trade secrets, except where statutory law
  expressly prohibits that restriction. §2.3(d) forbids attempts to "adapt, combine, create derivative works of, or otherwise
  modify any Google Properties".
- [API-TOS] §2(c): "You will only access (or attempt to access) an API by the means described in the
  documentation of that API." The same paragraph forbids misrepresenting or masking the identity of
  your API client. §4(b)(1): "Developer credentials (such as passwords, keys, and client IDs) are
  intended to be used by you and identify your API Client", and "Developer credentials may not be
  embedded in open source projects."

A Dart client would need Google's own API key, compiled into an open-source package, to send
requests that identify themselves as Google's SDK. That conflicts with each clause above. This
document is a reading of the terms, not legal advice, but the reading is not close.

**And it can break without notice.** The protocol is internal. Google can change the endpoint, rotate
the key, change the report schema, or require a new field at any time, and no deprecation policy
covers it. The SDKs have already moved the upload once, from a multipart endpoint
(`reports.crashlytics.com`, still declared and now unused in `Crashlytics/Shared/FIRCLSConstants.m:33`
[IOS], with comments about the "old endpoint" in `C/Controllers/FIRCLSReportUploader.m`) to the current
transport. When the next such change ships, a Dart client stops reporting, and the
developer only finds out from missing crashes.

## 3. Which apps can report

**Only Android and Apple apps.** Nothing in the official SDKs reports from Windows, Linux, a server or
the web.

- **The protocol** has no other platform. The settings URL takes `android`, `ios`, `mac` or `tvos`. The
  Android report has `platform: 4`, OS `platform: 3` and Android client info. The Apple enum has only
  `IOS`, `TVOS` and `MAC_OS_X`. A Windows report would have to claim one of these, under an app id
  registered as an Android or Apple app.
- **FlutterFire** `firebase_crashlytics` 6.1.0 declares `android`, `ios` and `macos` only
  (`packages/firebase_crashlytics/firebase_crashlytics/pubspec.yaml:34-43` [FF]). It has no Windows,
  Linux or web implementation, so a call there fails with a missing plugin. The request for desktop
  support (flutterfire discussion #5557, open since 2020) has no answer about Crashlytics.
- **Unity** picks a native implementation only on iOS and Android; every other platform, the editor
  included, gets the base `Impl`, documented as "Used for platforms where a native implementation is not
  available", which only writes debug logs (`crashlytics/src/Impl.cs:45-52` [UNITY]). Its C++ layer
  uses a no-op stub off Android and iOS (`crashlytics/src/cpp/stub/crashlytics_stub.cc`).
- **The C++ SDK** has no Crashlytics at all: there is no `crashlytics/` directory and no mention in its
  build files [CPP].
- **The documentation** [CLS-DOCS] lists Apple, Android, Flutter and Unity, and never mentions desktop.

So the only users who need a Dart client (Windows, Linux, servers; on Android, iOS and macOS the
FlutterFire plugin already works) are exactly the ones the service does not accept. A Dart client
would make their crashes appear in the console as Android or macOS crashes, with the wrong OS, device
and binary data. That is misrepresentation of the client, which [API-TOS] §2(c) forbids, and it would
also mislead the developer reading the console.

## 4. Dart stack traces

How FlutterFire reports a Dart error [FF]:

1. The app installs the handlers itself, as the docs show: `FlutterError.onError =
   FirebaseCrashlytics.instance.recordFlutterFatalError` and a `PlatformDispatcher.instance.onError`
   that calls `recordError(error, stack, fatal: true)` (`docs/crashlytics/_get-started.md:113-141`).
2. `recordError` (`firebase_crashlytics/lib/src/firebase_crashlytics.dart:81-143`) parses the stack with
   `package:stack_trace` (`Trace.parseVM(...).terse`, `lib/src/utils.dart`) into frames of `file`, `line`,
   `class` and `method`.
3. **Obfuscated builds** (`--obfuscate --split-debug-info`) print an AOT stack instead of symbols:
   `#NN abs <hex> virt <hex> <symbol+offset>` lines, after a header with `build_id: '<hex>'` and
   `loading_unit:` lines. FlutterFire matches those frames with a regular expression
   (`lib/src/utils.dart:8`) and sends the raw line as the frame's `method`, with an empty file and line
   0. It extracts the `build_id` and the loading units (`utils.dart:53-74`). "For iOS we use abs address
   for symbolication and for Android we use virt address."
4. **Android** (`FlutterFirebaseCrashlyticsPlugin.kt:107-158`) prefers the GNU build id read from
   `libapp.so` (`ElfBuildIdReader.kt`) over the Dart one, and stores it and the loading units as
   internal keys `com.crashlytics.flutter.build-id.0`, `.1`, … (`FlutterFirebaseCrashlyticsInternal.kt`).
   It wraps the message in a Java `FlutterError` exception with the Dart frames as `StackTraceElement`s,
   and calls `recordException` (non-fatal) or `logFatalException` (on-demand fatal). The Android SDK
   marks the report with development platform "Flutter" when the app has
   `flutter_assets/NOTICES.Z` (`CR/DevelopmentPlatformProvider.java`).
5. **Apple** builds an `ExceptionModel` named `FlutterError`, sets `onDemand = YES`, and calls
   `recordOnDemandExceptionModel` (fatal) or `recordExceptionModel` (non-fatal)
   (`firebase_crashlytics_objc/CrashlyticsPlatformHelpers.m`). It sets development platform "Flutter"
   (`FirebaseCrashlyticsPlugin.swift:46`).

What the console needs to symbolicate an obfuscated Dart stack [CLS-FLUTTER]: on Android, the
`--split-debug-info` directory uploaded with `firebase crashlytics:symbols:upload --app=FIREBASE_APP_ID
PATH/TO/symbols` before the crash is reported, matched by build id; on Apple platforms, the `App.framework`
dSYM, uploaded by a build phase. Both are tied to an Android or Apple app id and to the ELF or Mach-O
build of the Flutter engine for that platform.

**For a Dart client on Windows or Linux this does not carry over.** A desktop AOT build is a PE or ELF
binary that the symbol pipeline is not documented to accept, under an app id it would have to fake. An
unobfuscated build would still show readable Dart frames (file, line, method), because those are sent as
text. But the server groups and symbolicates by platform-specific rules, and there is no documented
contract for how it treats Dart frames labelled as Java or Apple frames. The only way to find out would
be to send test reports to production, which the protocol's status (section 2) rules out.

## 5. The alternatives

### 5.1 Google Cloud Error Reporting

A documented, public REST API in the same Google Cloud project as the Firebase app.

- **Endpoint:** `POST https://clouderrorreporting.googleapis.com/v1beta1/{projectName=projects/*}/events:report`
  [ER-REPORT]. Required: `serviceContext.service` and `message`. The message must contain a stack trace
  in a supported language format, unless `context.reportLocation` (file, line, function) is given
  [ER-FORMAT].
- **Dart is not a listed format.** A client would either rewrite Dart frames into a supported trace
  format (which formats parse cleanly needs a test against a project of the developer's) or send the
  Dart trace as text with `reportLocation` taken from the top frame. Both work within the documented API.
- **Authentication:** OAuth scopes `cloud-platform` or `stackdriver-integration` [ER-REPORT]; the
  formatting page says API-key authentication is possible with this API [ER-FORMAT]. For an app in
  users' hands the same rule as the Analytics relay applies: send reports to a small server the developer
  runs, which holds the credential, checks App Check, and forwards them.
- **Limits:** 6,000 reports per minute per project; data kept 30 days [ER-QUOTA]. The API is still
  `v1beta1`.
- **Cost:** Error Reporting is not billed separately as far as this pass found; the pricing page was not
  checked. Reports sent as Cloud Logging entries instead count toward Logging ingestion.
- **What the developer gets:** errors grouped by stack, counts, first and last seen, a link from the
  Google Cloud console, email and alerting through Cloud Monitoring. What they do not get: the Firebase
  console's Crashlytics view, crash-free-user metrics, breadcrumbs, native crash capture, or
  symbolication of obfuscated Dart.

### 5.2 A Sentry-protocol tracker

`sentry` and `sentry_flutter` on pub.dev (MIT) are an existing, maintained Dart client with Windows,
Linux, macOS, web, Android and iOS listed. They upload obfuscated Dart symbols through `sentry_dart_plugin`.
The protocol is documented. The server is either the hosted service (a free tier of 5,000 errors a
month and 30-day retention; paid plans from about USD 26-29 a month, pricing page read 2026-11-28) or
self-hosted. The self-hosted server is under the Functional Source License (it becomes Apache 2.0 after
two years) and needs at least 4 CPU cores, 16 GB of RAM plus 16 GB of swap, and 20 GB of disk.
Compatible open-source servers exist that accept the same client SDKs.

### 5.3 Comparison

| | Crashlytics from Dart | Cloud Error Reporting | Sentry-protocol tracker |
|---|---|---|---|
| Documented API | no | yes (`v1beta1`) | yes |
| Allowed by the terms | no (section 2) | yes | yes |
| Windows, Linux, servers | only by posing as Android or Apple | yes | yes, with an existing Dart SDK |
| Obfuscated Dart symbols | no path on desktop | no; ship unobfuscated or symbolicate yourself | yes |
| Native (C/C++) crashes | no | no | yes, through the native SDKs |
| Where errors appear | the Firebase console, mislabelled | the Google Cloud console | its own UI |
| Cost | Crashlytics is free | low; no separate charge found | free tier, paid plans, or your own server |
| Work for this repository | a reverse-engineered client that can break any day | a small reporter package and an example relay | none; document it |

## 6. Recommendation

**Do not build a Crashlytics client.** An "unofficial protocol" warning does not fix the problem. The
risk is not only that the client can break. It is that it would ship Google's private API key in an
open-source package, send requests that pretend to be Google's SDK, and file desktop crashes as Android or
Apple crashes. The warning would ask every developer who installs the package to accept terms
violations on their own Firebase project, and the package could not test itself against production
without committing them.

Instead:

1. **Point to the official plugin on Android, iOS and macOS.** FlutterFire's `firebase_crashlytics`
   covers them and is unaffected by any of this.
2. **For Windows, Linux and servers, document the two alternatives** in the repository's guides: Cloud
   Error Reporting for teams that want to stay inside their Google Cloud project, and a Sentry-protocol
   tracker for teams that want symbolicated, native and obfuscated crashes on every platform.
3. **Optional, later, if the owner wants a product here:** a small `firebase_error_reporting_dart`
   package that captures Dart errors (zone, `FlutterError.onError`, `PlatformDispatcher.onError`, an
   isolate error listener), queues them on disk, and sends them to Cloud Error Reporting through a relay
   (the pattern of the Analytics relay), with an example relay on `shelf`. It would be built on a
   documented API and could be tested on the emulator-free path with `MockClient` and a production kit
   the owner runs. It needs its own specification first.

Revisit this document if Google documents a Crashlytics ingestion API, or ships Crashlytics for desktop
in FlutterFire, Unity or the C++ SDK.
