# cloud_functions_dart

Unofficial pure-Dart client of Firebase callable Cloud Functions: unary calls and streaming calls (server-sent
events), with the signed-in user's ID token and an App Check token attached, on the Dart VM (macOS, Windows,
Linux, servers, command-line tools) and the web (dart2js and dart2wasm). It follows the callable protocol of the
Firebase JavaScript SDK and needs no Flutter and no native code. FlutterFire's `cloud_functions` has no
implementation for Windows and Linux; this client does.

Status: 0.1.0, first release, not published yet. Verified on the emulator (the fixture in
`tool/functions_emulator`, the unit tests, and the production kit in its emulator mode); the checks against a real
project are in `tool/verify_production_functions` and have not been run yet.

## Install

`firebase_app_dart` is on pub.dev; this package is not yet. Depend on it from this repository:

```yaml
dependencies:
  firebase_app_dart: ^0.2.3
  cloud_functions_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: cloud_functions/cloud_functions_dart
```

The `ref: main` line assumes the package has landed on `main`. It depends on `_firebase_transport_dart`, an
internal helper package of this repository that is not on pub.dev either; add the same kind of `git` entry as
an override while neither is published:

```yaml
dependency_overrides:
  _firebase_transport_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_core/_firebase_transport_dart
```

Once both are published, `dart pub add cloud_functions_dart firebase_app_dart` does the same and the override goes
away. Dart 3.8 or later.

## Create an instance

An instance belongs to one `FirebaseApp`. The app needs a `projectId`; Functions sends neither the API key nor
the app id.

```dart
import 'package:cloud_functions_dart/cloud_functions_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

final FirebaseApp app = FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: '<the API key of the app>',
    appId: '1:1234567890:web:0123456789abcdef',
    projectId: 'my-project',
  ),
);
final FirebaseFunctions functions = FirebaseFunctions(app);
```

Settings are fixed at construction:

- `region`: where the function runs, `us-central1` by default. A region is one DNS label (`europe-west1`), not a
  URL.
- `customDomain`: an `https` URL (or `http` to a loopback host) that serves your functions, for example through
  Hosting rewrites. A path is kept: `https://example.com/api/` calls `https://example.com/api/<name>`.
- `emulatorHost`: `host:port` of the Functions emulator. It wins over a custom domain. A scheme, a path, a
  missing port or a Google host is an `ArgumentError`.
- `timeout`: the default of every callable of the instance, 70 seconds. Any positive duration; one above
  2147483647 ms is clamped to it.
- `httpClient`: your own `http.Client`, which `close()` does not close. Without it the instance creates one and
  closes it.
- `onWarning`: receives the warnings about tokens (a non-loopback emulator host, a placeholder App Check token).
  Without it they go to `dart:developer`'s `log` under the name `cloud_functions_dart`, which reaches DevTools and
  the IDE, not stdout; a command-line program that wants them on screen passes `print`.

`close()` aborts the calls and streams in flight (they fail with `cancelled`), waits until they settle and closes
the HTTP client the instance created. It also runs when the app is deleted. After it, `httpsCallable` and `call`
throw a `StateError`.

### The emulator

```dart
final FirebaseFunctions emulated = FirebaseFunctions(
  app,
  emulatorHost: FirebaseFunctions.emulatorHostFromEnvironment ?? '127.0.0.1:5001',
);
```

`emulatorHostFromEnvironment` reads `FIREBASE_FUNCTIONS_EMULATOR_HOST` (always null on the web). The Firebase CLI
does not set it for other processes: export it yourself, or pass the host as above. The repository has a fixture
and a script for tests: `tool/start_functions_emulator.sh` (see `tool/README.md`). The emulator does not verify
ID tokens; it accepts an unsigned JWT, which an `AuthTokenProvider` of your own can hand out (`example/emulator.dart`).

## Call

```dart
final HttpsCallable echo = functions.httpsCallable('echo');
final HttpsCallableResult result = await echo.call(<String, Object?>{
  'hello': 'world',
  'numbers': <int>[1, 2, 3],
});
print(result.data);
```

`httpsCallableFromUrl(Uri)` calls a function by its URL (a Cloud Run service, or a function of another project);
the emulator setting does not rewrite it. A URL must not have a query, a fragment or user info, and an `http` URL
must point to a loopback host or the configured emulator.

`HttpsCallableOptions` sets a `timeout` for one callable and `limitedUseAppCheckTokens`:

```dart
final HttpsCallable slow = functions.httpsCallable(
  'report',
  options: const HttpsCallableOptions(timeout: Duration(minutes: 5)),
);
print('${slow.url} ${slow.timeout}');
```

`name` is 1 to 63 characters, not `.` or `..`, and has none of `/ ? # % :`, whitespace or control characters.

## Values and limits

- Request values: `null`, `bool`, finite `num`, `String`, `List` and `Map` with `String` keys, nested at most 512
  levels. Anything else (`DateTime`, `BigInt`, `Set`, your own classes) is an `ArgumentError`, thrown by `call`
  before anything is sent; the message names the path and the type, never the value.
- Large integers: on the VM and in dart2wasm an `int` beyond ±(2^53 − 1) is sent as its exact digits. What the
  server keeps depends on its language: a Node function reads it as a JavaScript number and rounds it, a Python
  function keeps it exact. Send such values as strings to a Node function.
- Whole doubles with an absolute value below 1e21 are sent without `.0`, as JavaScript sends them: `2.0` goes out
  as `2`.
- The result `data` is `null`, `bool`, `int`, `double`, `String`, `List<Object?>` or `Map<String, Object?>`. A
  cast such as `as Map<String, int>` fails at runtime; read what you need and convert. Numbers keep the type
  `jsonDecode` gives them (a Node function sends a whole double as `1`, Python as `3.0`): read numbers as `num`
  and convert.
- A raw integer beyond 64 bits in a response decodes to a rounded `double`. A wrapped 64-bit value beyond what the
  platform holds exactly (more than 2^53 − 1 on dart2js) is an `internal` error instead of a rounded number.
- A response with a bare `NaN` or `Infinity` (a Python function can send them) fails with `internal`.
- A unary response over 32 MiB, an error body over 1 MiB, a stream event over 32 MiB and a stream over 1 GiB are
  not read.
- Decoding runs on the calling isolate; a caller that expects large results calls from a background isolate.

## Errors

Every failure of a call is a `FirebaseFunctionsException` (a `FirebaseException` with plugin `firebase_functions`)
with a `code`, a `message`, `details` (decoded, or null) and the `httpStatus` of the answer when there was one.
`toString()` is `[firebase_functions/<code>] <message>` plus ` (HTTP <n>)`, without details.

```dart
try {
  await functions.httpsCallable('fail').call(<String, Object?>{'code': 'aborted'});
} on FirebaseFunctionsException catch (error) {
  print('${error.code}: ${error.message} (${error.httpStatus}) ${error.details}');
}
```

The 16 codes (`firebaseFunctionsExceptionCodes`): `cancelled`, `unknown`, `invalid-argument`,
`deadline-exceeded`, `not-found`, `already-exists`, `permission-denied`, `resource-exhausted`,
`failed-precondition`, `aborted`, `out-of-range`, `unimplemented`, `internal`, `unavailable`, `data-loss`,
`unauthenticated`.

| Situation | Code |
|---|---|
| The function threw an `HttpsError` | its code, from the answer body (not the HTTP status: 409 serves both `already-exists` and `aborted`) |
| An answer without a callable body (an HTML page, a proxy) | from the HTTP status: 400 `invalid-argument`, 404 `not-found`, ... |
| The request did not reach the server, the connection broke, a redirect (on the web also a response without CORS headers) | `unavailable` |
| The timeout ran out (token wait, headers, whole call, or silence on a stream) | `deadline-exceeded` |
| `abortTrigger` completed, or the instance was closed | `cancelled` |
| The Auth provider failed | `unauthenticated` |
| The Auth provider did not answer in 10 seconds | `unavailable` |
| The ID token is longer than 8192 characters, or tokens may not go to the URL | `failed-precondition` |
| The answer is not what the protocol says (not JSON, no result, invalid value, too large) | `internal` |

Messages never hold a token, the request data or a URL with a query. A bad argument, an unknown region or a call
after `close()` is an `ArgumentError` or a `StateError`, not a `FirebaseFunctionsException`.

## Timeouts and cancellation

The timeout covers the whole call, the token fetch included, and aborts the request when it runs out. The function
on the server may still run to its end, so a call that timed out may have had its effect: do not retry a call that
is not idempotent. Nothing is retried automatically.

```dart
import 'dart:async';

final Completer<void> cancel = Completer<void>();
final Future<HttpsCallableResult> pending = functions
    .httpsCallable('slow')
    .call(null, cancel.future);
cancel.complete();
try {
  await pending;
} on FirebaseFunctionsException catch (error) {
  print(error.code); // cancelled
}
```

## Signed-in users and App Check

The client reads `app.authProvider` and `app.appCheckProvider` at every call, so a provider set after the
instance was created is used from the next call. With `firebase_auth_providers_dart`, `FirebaseUserAuth.forApp(app)`
makes the signed-in user the app's provider; without a user the call goes out without an `Authorization` header.

- An Auth provider that throws (other than "no signed-in user") fails the call with `unauthenticated`; it does not
  silently call as a signed-out user.
- App Check never fails a call: a token is sent when the provider gives one, even the placeholder it returns with
  an error, and the call proceeds without the header when it gives none.
- `HttpsCallableOptions(limitedUseAppCheckTokens: true)` asks for a limited-use token. It needs a provider that
  implements `LimitedUseAppCheckTokenProvider`; with another one no App Check header is sent. App Check itself
  is optional: there is no App Check package in this repository yet.

## Streaming

```dart
final Stream<CallableStreamEvent> events = functions.httpsCallable('stream').stream(null);
await for (final CallableStreamEvent event in events) {
  switch (event) {
    case CallableMessage(:final Object? data):
      print('message: $data');
    case CallableResult(:final Object? data):
      print('result: $data');
  }
}
```

A stream is single-subscription, sends its request when it is listened to, emits `CallableMessage`s and ends with
one `CallableResult` or an error. Cancelling the subscription or completing `abortTrigger` aborts the request.

- `timeout` is the wait for the response headers and the longest silence in the body, not the stream's total time.
  A stream may run for hours while the function keeps sending. Keep `timeout` above the function's
  `heartbeatSeconds` (30 seconds by default for a Node function): its `: ping` comments restart the idle timer.
- A non-2xx answer (a router or proxy) is handled like a unary response; a JSON answer to a stream request (a
  function that cannot stream, a Python function) arrives as the one `CallableResult`.
- A stream that ends before its result is an `internal` error.

## Web

The default client is fetch-based and streams response bodies, so calls, streams and cancellation work in
Chrome with dart2js and dart2wasm. A browser calls a function only if the function answers the CORS preflight
for the headers it sends (`content-type`, `authorization`, `x-firebase-appcheck`, `accept`). A response without
CORS headers, a network failure and a crashed backend look alike to a page: all are `unavailable`.

## Security

- Tokens go only over `https`, to the configured emulator and to loopback hosts. An `http` custom domain or URL
  to another host is refused when you configure it.
- Any `https` custom domain or `httpsCallableFromUrl` target receives the user's ID token and App Check token, as in
  the official SDKs: use hosts you control.
- A redirect is never followed: the `Authorization` header never goes to a second host.

## Differences from FlutterFire's `cloud_functions`

- No global instance: create `FirebaseFunctions(app)` and close it; `region` and `customDomain` are separate
  parameters.
- The default timeout is 70 seconds (FlutterFire's is 60), and the timeout aborts the request.
- A call can be cancelled with `abortTrigger` on every platform; a stream's result is its last event.
- `DateTime` is refused instead of encoded; results are not generic.
- An Auth provider error fails the call instead of being ignored.
- No FCM token header, no Cloud Workstations emulator, no typed (Codable) layer.

The comparison with the JS, Android, iOS and C++ SDKs, row by row, is in
[docs/functions_parity.md](../../docs/functions_parity.md); the guide is
[docs/guides/functions.md](../../docs/guides/functions.md).
