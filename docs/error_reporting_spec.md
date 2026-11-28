# Error Reporting client: specification

The plan for `firebase_error_reporting_dart`, a pure-Dart client that captures Dart errors and sends them
to Google Cloud Error Reporting, in the Google Cloud project behind a Firebase app. It follows
[contributing_a_product.md](contributing_a_product.md). This document comes before the code. Once the
code exists, an `error_reporting_decisions.md` in the format of [storage_decisions.md](storage_decisions.md)
replaces it.

Statements marked **(measure)** are expectations the documentation does not settle. Section 11 lists them,
and the production verification kit answers them before the first release.

## 1. Why this package

[crashlytics_feasibility.md](crashlytics_feasibility.md) concluded that a Dart Crashlytics client should
not be built: its protocol is private, its upload uses a key that belongs to Google's SDK, and it accepts
only Android and Apple apps. Its section 6 proposed this package instead: the same job (know when a
Dart program in the field throws) on a documented, public API.

**Who it is for.** Windows and Linux desktop apps, command-line tools, Dart servers and jobs, and the web.
FlutterFire's `firebase_crashlytics` has no implementation on any of these. On Android, iOS and macOS the
official plugin remains the better choice, because it also captures native crashes, ANRs and
symbolicates obfuscated builds; the README says so in its first section. Using both in one Flutter app
(Crashlytics on mobile, this package on desktop) is supported and shown in the guide.

**What it is not.** It captures Dart errors only: no native crash (a segfault in a plugin, an
out-of-memory kill) reaches Dart code, so none is reported. It does not symbolicate obfuscated builds
(section 7).

## 2. Sources

All pages were read on 2026-11-28. Cloud documentation shows its date at the foot of the page.

| Short name | Page | Last updated |
|---|---|---|
| [REPORT] | [`projects.events.report`](https://cloud.google.com/error-reporting/reference/rest/v1beta1/projects.events/report) | 2026-09-18 |
| [REST] | [Error Reporting REST reference](https://cloud.google.com/error-reporting/reference/rest) | 2026-05-28 |
| [CONTEXT] | [`ErrorContext`](https://cloud.google.com/error-reporting/reference/rest/v1beta1/ErrorContext) | 2025-07-14 |
| [SERVICE] | [`ServiceContext`](https://cloud.google.com/error-reporting/reference/rest/v1beta1/ServiceContext) | 2025-07-14 |
| [LOCATION] | [`SourceLocation`](https://cloud.google.com/error-reporting/reference/rest/v1beta1/SourceLocation), [`HttpRequestContext`](https://cloud.google.com/error-reporting/reference/rest/v1beta1/HttpRequestContext) | none shown |
| [FORMAT] | [Format errors in logs](https://cloud.google.com/error-reporting/docs/formatting-error-messages) | 2026-11-23 |
| [GROUPING] | [How errors are grouped](https://cloud.google.com/error-reporting/docs/grouping-errors) | 2026-11-23 |
| [VIEWING] | [View errors](https://cloud.google.com/error-reporting/docs/viewing-errors) | 2026-11-23 |
| [MANAGING] | [Manage errors](https://cloud.google.com/error-reporting/docs/managing-errors) | 2026-11-23 |
| [NOTIFY] | [Configure notifications](https://cloud.google.com/error-reporting/docs/notifications) | 2026-11-23 |
| [SETUP] | [Error Reporting setup overview](https://cloud.google.com/error-reporting/docs/setup) | 2026-11-23 |
| [NODE] | [Instrument Node.js apps](https://cloud.google.com/error-reporting/docs/setup/nodejs) | 2026-11-23 |
| [IAM] | [Access control with IAM](https://cloud.google.com/error-reporting/docs/iam) | 2026-11-23 |
| [QUOTA] | [Quotas and limits](https://cloud.google.com/error-reporting/quotas) | 2026-11-23 |
| [TROUBLE] | [Troubleshooting](https://cloud.google.com/error-reporting/docs/troubleshooting) | 2026-11-23 |
| [PRICING] | [Google Cloud Observability pricing](https://cloud.google.com/products/observability/pricing) | none shown |
| [KEYS] | [Manage API keys](https://cloud.google.com/docs/authentication/api-keys) | not recorded |

No request was sent to any Google API to write this document.

## 3. The API, as documented

### 3.1 The method

- `POST https://clouderrorreporting.googleapis.com/v1beta1/{projectName=projects/*}/events:report`
  [REPORT]. `projectName` is `projects/<project id>`, the `projectId` of the app's `FirebaseOptions`.
- The body is a `ReportedErrorEvent`. "If successful, the response body is empty." [REPORT]
- There is only `v1beta1`; the reference lists no other version [REST]. No deprecation notice.
- The API must be enabled in the project: "Enable the Error Reporting API, if it is not already
  enabled." [TROUBLE]
- One event per request. The documentation has no batch method.

### 3.2 Authentication

- OAuth 2.0 with the scope `https://www.googleapis.com/auth/cloud-platform` or
  `https://www.googleapis.com/auth/stackdriver-integration` [REPORT].
- The caller needs the permission `errorreporting.errorEvents.create`, which the role Error Reporting
  Writer (`roles/errorreporting.writer`) "Provides the permissions to send error events to Error
  Reporting" [IAM].
- **API keys work for this method.** "The projects.events.report method also supports API keys." [NODE]
  "To use an API key, append it to the URL as the value of a key parameter", as `?key=` [REPORT]. "If you
  require API key-based authentication, then you must use the Error Reporting API" rather than Cloud
  Logging [SETUP]. Google recommends "setting both API restrictions and application restrictions" on
  keys, and says "Unrestricted API keys are insecure." [KEYS]

### 3.3 `ReportedErrorEvent`

| Field | What the documentation says | Source |
|---|---|---|
| `eventTime` | Optional, RFC 3339. Without it, "the time when the event was received" is used. With it, "the time must not exceed the logs retention period in the past, or be more than 24 hours in the future. If an invalid time is provided, then an error is returned." | [REPORT] |
| `serviceContext.service` | Required. "An identifier of the service, such as the name of the executable, job, or Google App Engine service name." | [REPORT], [SERVICE] |
| `serviceContext.version` | Optional. "Represents the source code version that the developer provided". | [SERVICE] |
| `serviceContext.resourceType` | "must not be set when reporting errors". | [SERVICE] |
| `message` | Required. "If no context.reportLocation is provided, the message must contain a header (typically consisting of the exception type name and an error message) and an exception stack trace in one of the supported programming languages and formats." | [REPORT] |
| `context.user` | "The user who caused or was affected by the crash." | [CONTEXT] |
| `context.httpRequest` | `method`, `url`, `userAgent`, `referrer`, `responseStatusCode`, `remoteIp`. | [LOCATION] |
| `context.reportLocation` | "The location in the source code where the decision was made to report the error": `filePath`, `lineNumber` (1-based, 0 for unknown), `functionName`. "Required if no stack trace is provided." | [CONTEXT], [LOCATION], [FORMAT] |
| `context.sourceReferences` | Repository and revision of the deployed code. | [CONTEXT] |

No page gives a size limit for `message` or for the whole event **(measure)**.

### 3.4 Stack trace formats

"Supported languages are Java, Python, JavaScript, Ruby, C#, PHP, Go, and Rust." The formats: Java,
`Throwable.printStackTrace()`; JavaScript, "the value of error.stack as returned by V8"; and so on for the
others [REPORT]. **Dart is not one of them.** "The stack trace isn't captured by Error Reporting when an
unsupported format is used." [FORMAT]

### 3.5 Grouping and the console

From [GROUPING]:

- Events with a stack trace are "Grouped by exception type and the five topmost frames." For nested
  exceptions, the innermost exception is used.
- Events "without a stack trace but with a message" are "Grouped by message and (if present) function
  name. Only the first three literal tokens of the message are considered."
- Some environment errors are grouped by exception type alone.

The console shows, per group, "the history of error events, the resolution status, the number of
occurrences, and a timestamped list of error events", each linked to its log entry [VIEWING]. Groups are
Open, Acknowledged, Resolved or Muted; "If an error event occurs in a muted error group, then the error
event isn't recorded and you aren't notified." [MANAGING] Notifications go out for new groups and for
events in a Resolved group, a regression, by email, mobile and webhooks among others [NOTIFY].

### 3.6 Limits, retention and cost

- "Error reports per minute": 6,000 per project [QUOTA].
- "There is a limit of 10,000 deployment-error group pairs, where a deployment is a combination of
  service and version. After you reach this limit, Error Reporting discards the oldest (or less-recently
  modified) deployments and their associated error data." [QUOTA]
- "Information in Error Reporting is retained for 30 days." [QUOTA]
- "There are no charges for using Error Reporting. However, you might incur Cloud Logging costs because log
  entries are generated and then stored by Cloud Logging." [PRICING] "Because log entries are generated by
  calls to report, you might incur Logging ingestion costs." [SETUP] Logging storage is $0.50/GiB after
  the first 50 GiB per project per month [PRICING].

**Consequences for the design.** A version string per build multiplies groups by builds, so
`serviceContext.version` is the release version, not a build number. The client keeps events younger than
30 days and drops older ones from the queue, so the server never refuses them for their `eventTime`.

## 4. Hard limits, said in the README

1. **Credentials.** The API needs an OAuth token with the Error Reporting Writer permission, or an API
   key. A token-granting credential must never ship in an app. An API key can, but anyone who extracts it
   can post errors into the project, and a key with too wide an API restriction can be used for other
   APIs. So the **relay** (section 6) is the recommended transport for apps in users' hands, and the
   **direct** transport is for servers and tools the developer runs.
2. **Dart errors only.** No native crashes, no ANRs, no out-of-memory kills.
3. **No symbolication of obfuscated builds.** Section 7.
4. **No Dart stack trace format on the server.** The client rewrites Dart frames into a supported format
   (section 7) and the kit checks how the console takes it.
5. **`v1beta1`.** The API has no stable version.
6. **30 days of history** and the console of Google Cloud, not the Firebase console.
7. **No emulator.** The Firebase emulator suite has no Error Reporting emulator. Tests use `MockClient`;
   only the production kit talks to the real API, run by the maintainer with their own project.

## 5. Package and public API (proposal)

| Package | Path | Kind |
|---|---|---|
| `firebase_error_reporting_dart` | `firebase_error_reporting/firebase_error_reporting_dart` | Dart, every platform, web included |

The name was free on pub.dev on 2026-11-28 (no package page; no package of that name in a search). One
community package, `stackdriver_dart`, reports to Error Reporting from Flutter with an API key in the app
and does not support the web; this package differs in the relay, the disk queue, the web, and the
`FirebaseApp` integration (project id, App Check, the signed-in user).

Dependencies: `firebase_app_dart`, `http`, `meta`, `stack_trace`. No `dart:io` in the main library. The
file store and the isolate hook live in `lib/io.dart`.

**There is no FlutterFire adapter.** FlutterFire has no platform interface for this job, and
`firebase_crashlytics_platform_interface` describes Crashlytics. Wiring Flutter's error hooks takes three
lines (section 8), shown in the README and the guide, so a Flutter package would add a dependency on
Flutter for no gain.

```dart
final reporter = ErrorReporter(
  app,
  service: 'notes-desktop',                         // serviceContext.service, required
  version: '1.4.0',                                 // serviceContext.version: the release, not the build
  transport: ErrorReportingTransport.relay(Uri.parse('https://example.com/errors')),
  // or ErrorReportingTransport.direct(credentials: oauthTokenProvider)  // servers, jobs
  // or ErrorReportingTransport.direct(apiKey: '...')                     // internal tools only
  store: FileErrorReportingStore(directory),        // from io.dart; ErrorReportingStore.memory() by default
  collectionEnabledByDefault: true,
  beforeSend: (ErrorEvent event) => event,          // return null to drop, or a scrubbed copy
  httpClient: client, clock: clock, random: random,
);

await reporter.runGuarded(() async { /* the program */ });  // a zone that reports uncaught errors
await reporter.recordError(error, stack, reason: 'while syncing', fatal: false);
await reporter.recordError(error, stack, httpRequest: HttpRequestContext(method: 'GET', url: url));
await reporter.setUser('user-123');                 // context.user; null clears it
await reporter.setCollectionEnabled(false);         // persisted; the queue is dropped
await reporter.flush();
await reporter.close();
```

`lib/io.dart` adds `reporter.watchIsolate(Isolate isolate)`, which reports the errors of another isolate
through `Isolate.addErrorListener`.

Decisions behind the proposal:

- **Configuration is immutable** (design rule 4): the service, version, transport, store and hooks go to
  the constructor. The user and the collection switch are runtime state, persisted in the store.
- **`fatal`** has no field in the API. It means "the program is about to end": the event is written to the
  store and sent at once, without waiting for the batch delay. It is also recorded in the message header
  (section 7), so fatal and non-fatal errors of the same type stay apart in the console **(measure)**.
- **No user id by default.** `context.user` is sent only after `setUser`. The client never reads the
  signed-in user on its own, because the console shows the value to everyone with access to the project.
- **`beforeSend`** sees the event after it is formatted and before it is stored, and can scrub it (paths,
  e-mail addresses in messages) or drop it. An exception thrown inside it drops the event and is logged,
  never reported, so a broken hook cannot loop.
- **The client never throws into the caller.** `recordError` completes once the event is stored; a failing
  store or transport is logged.
- **Reentrancy.** An error thrown while reporting (inside the transport, the store or `beforeSend`) is
  logged, not reported.

## 6. Transport

`ErrorReportingTransport` is a sealed class.

- **Relay** (recommended for apps) posts the `ReportedErrorEvent` JSON to a URL of the developer's
  server. It attaches the App Check token from `app.appCheckProvider` and, when a user is signed in, the
  ID token from `app.authProvider`, under design rule 5 (https, a loopback host, or nothing). The server
  checks the tokens, applies a size cap and a rate limit per App Check token or user, sets
  `serviceContext` from an allow-list rather than trusting the body, and forwards the event to
  `events:report` with its own service account, which holds `roles/errorreporting.writer` and nothing else.
  The package ships an example relay in `examples/` on `shelf`, and its README lists these checks.
- **Direct with credentials** (servers and jobs) calls `events:report` with an OAuth access token from an
  `AuthTokenProvider`: `OAuthTokenProvider.serviceAccount(key, scopes: [cloudPlatformScope])` from
  `firebase_auth_providers_dart`, or Application Default Credentials on Google Cloud. On a 401 it asks for
  a new token once (`forceRefresh: true`) and retries.
- **Direct with an API key** calls `events:report?key=…`. Documented as acceptable only for internal tools
  and only with a key restricted to the Error Reporting API. The README states that anyone who extracts
  the key can post errors into the project.

All three:

- send one event per request, in the order captured, one request at a time;
- treat 2xx as delivered;
- retry network errors, 408, 429 and 5xx with injected exponential backoff and jitter, honouring
  `Retry-After`; drop the event on any other 4xx, which means the request is wrong (400, a bad
  `eventTime` or an oversize message), the credential is refused (403), or the API is disabled, and log the
  status and a size-capped body;
- do not follow redirects, read at most 64 KiB of a response, and keep the API key and tokens out of
  exceptions, logs and `toString` (design rule 7);
- never send while collection is disabled.

## 7. Formatting the message

Dart is not a supported format (section 3.4), so the client chooses a format the server parses. Two are
candidates. The kit compares them, and the better one becomes the default before the first release
**(measure)**.

**A. V8 format (the proposal).** The `message` is what `error.stack` looks like in V8, which the
documentation names as the JavaScript format:

    StateError: Bad state: no element
        at NoteRepository.load (package:notes/src/repository.dart:42:7)
        at main.<fn> (package:notes/main.dart:12:3)

- Header: `<runtime type of the error>: <error.toString()>`, plus `[fatal]` when `fatal` is set and
  ` (reason)` when a reason is given.
- Frames: parsed with `package:stack_trace` (`Trace.from(stack)`), one `at member (uri:line:column)` line
  per frame, `<asynchronous suspension>` markers removed, and frames of `dart:` libraries kept so the
  location of a core error stays visible.
- If the server parses it, events group by error type and the top five frames, which is what a developer
  expects.

**B. Raw Dart trace with a location.** The `message` is the header and the Dart trace as Dart prints it,
and `context.reportLocation` holds the first frame from the developer's own package (file, line, member).
This is valid under the documentation whatever the server makes of the trace, but if the trace is not
parsed, grouping falls back to the message's first three tokens and the function name (section 3.5),
which puts different errors of the same type in one group.

Both formats:

- cap the message at 32 KiB of UTF-8, dropping frames from the bottom and saying how many were dropped,
  until the kit measures the real limit **(measure)**;
- always set `reportLocation` when the top frame is known, unless the kit shows it disables trace parsing
  **(measure)**.

**Obfuscated builds.** `--obfuscate` with `--split-debug-info` prints `#NN abs <hex> virt <hex>` frames
and a header with `build_id`. No symbol pipeline exists for them in Error Reporting. The client sends such
a trace in format B with the build id in the header, so the developer can symbolicate it by hand with
`flutter symbolize` and the saved debug info. The README recommends building without `--obfuscate` when
readable reports matter.

**What the console shows for a Dart error**, as far as the documentation tells: in format A, the
header and the parsed frames, grouped by type and frames; in format B, the message text with the source
location, grouped by the message's first tokens and the function. Whether `package:` URIs show as source
links, whether frames from `package:flutter` or `dart:` count as "public library" frames removed before
grouping, and how `reportLocation` combines with a parsed trace are all questions for the kit.

## 8. Capture hooks

The client does not install global hooks by itself. Each one is one call, documented in the README:

- **Zone:** `reporter.runGuarded(body)` runs `body` in `runZonedGuarded` and reports what escapes as
  `fatal: false`. The program keeps running, as Dart's own behaviour for zone errors is.
- **Flutter:** the app sets the hooks, as FlutterFire's documentation does for Crashlytics:

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        reporter.recordError(details.exception, details.stack,
            reason: details.context?.toString(), fatal: true);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        reporter.recordError(error, stack, fatal: true);
        return true;
      };

- **Isolates (VM):** `watchIsolate(isolate)` in `io.dart` listens with `Isolate.addErrorListener`. The
  error arrives as two strings (the error and the stack), so the header uses the error string and the
  frames are parsed from the stack string.
- **Errors logged rather than thrown:** `recordError` directly, for example from a `package:logging`
  handler at `Level.SEVERE`.

## 9. Queue and storage

The store pattern of the Analytics specification:

- `ErrorReportingStore` is an interface that loads and saves the user, the collection switch and the
  queue. Three stores: `ErrorReportingStore.memory()`, `FileErrorReportingStore` in `io.dart`, and a
  `localStorage` store on the web behind a conditional import.
- The queue is capped (default 100 events; the oldest go first) and events older than 30 days are dropped
  (section 3.6).
- **A rate limit in the client**: at most 30 events a minute and, within that, at most 5 a minute with the
  same header and top frame. An error inside a frame callback can otherwise fire 60 times a second and
  use up the project's 6,000 a minute. Dropped events are counted, and the count goes into the header of
  the next event of that kind (`[+12 similar dropped]`).
- Events are sent after a short delay (default 2 s), on `flush()`, on `close()`, and at once for `fatal`.
  On start, a queue left by an earlier run is sent.
- A store that cannot be read starts empty and logs a warning. It never throws into `recordError`.

## 10. The production verification kit

`tool/error_reporting_probe.dart` with `tool/error_reporting_probe.md`, in the style of
`tool/analytics_probe.dart`. **The maintainer runs it**, with a project where they enabled the Error
Reporting API and a credential they hold: Application Default Credentials from
`gcloud auth application-default login`, or an API key they created and restricted. Nothing in this
repository creates a project, a service account, a key or a role binding.

It sends, each with a unique marker in the message:

1. the same Dart error in format A and in format B;
2. format A with and without `reportLocation`;
3. two different errors of the same type, and one error thrown from two places;
4. a fatal and a non-fatal copy of one error;
5. messages of 16, 64 and 256 KiB;
6. an obfuscated trace;
7. an event with `context.user` and one with `httpRequest`;
8. a request with an API key restricted to another API, to show the refusal.

Then it prints what to check in the console for each marker.

## 11. What the kit must answer

1. Does the server parse format A (the V8 shape with `package:` URIs) as a stack trace?
2. How does it group: by type and top frames for A, by the first tokens for B?
3. Does `reportLocation` change how a parsed trace is grouped or shown?
4. Do `package:flutter` and `dart:` frames count as library frames that grouping skips?
5. Do fatal and non-fatal copies of one error land in separate groups with the `[fatal]` header?
6. What is the largest `message` the API accepts, and what does it answer above that?
7. How do `context.user` and `httpRequest` appear in the console?
8. What does the API answer for a key restricted to another API (status and body), so the transport's
   handling of that refusal is pinned by a test?

Until the kit has run, the defaults above (format A, a 32 KiB cap, `reportLocation` always set) stand,
and the README marks them as unverified.

## 12. Order of work, one PR each

1. **This specification** and the platform guide (`docs/guides/crash_reporting.md`). Documentation only.
2. **The probe** (section 10), brought forward as in the Analytics work: the format question decides
   the shape of the core. **Step 3 does not start until the maintainer has run it** or decided to go ahead
   with the defaults.
3. **The client core:** the model, formatting, the stores, the queue and rate limit, the three
   transports, the zone and isolate hooks. Unit tests with `MockClient` and `fake_async`; security tests
   (no key or token in a message or log; tokens only where design rule 5 allows; no redirects; response
   size cap; a failing hook cannot loop); a web compile checked with `tool/check_web_imports.dart`; the
   browser leg on dart2js and dart2wasm.
4. **Docs and wiring:** README, CHANGELOG, `tool/test_all.sh`, the `others` leg of the CI unit jobs, the
   guide updated to the published API.
5. **The example relay** in `examples/` on `shelf`, with its own tests (token checks, size cap, rate
   limit, the service allow-list).
6. **The production kit** in its final form, covering the transports of step 3.
7. **Independent review** of the transport, the relay and the security tests, by a reviewer who did not
   write them.

Releases are the maintainer's manual step: the package is not added to `release.yml` or `publish.yml` in
any of these PRs.
