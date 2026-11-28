# Cloud Functions

`cloud_functions_dart` calls Firebase callable functions (`onCall` in Node, `on_call` in Python) from pure Dart,
with the signed-in user's ID token and an App Check token attached: unary calls and streaming calls, on the Dart VM
(macOS, Windows, Linux, servers, command-line tools) and the web (dart2js and dart2wasm). It speaks the HTTPS and
JSON callable protocol of the Firebase JS SDK; there is no gRPC service for callables. It is at 0.1.0, not
released. How it compares with the official SDKs is in [functions_parity.md](../functions_parity.md); why it
differs is in [functions_decisions.md](../functions_decisions.md).

It was verified against the Functions emulator (the fixture in `tool/functions_emulator`). The checks against a
real project, `tool/verify_production_functions`, need functions deployed by the project's owner and have not been
run yet: what a deployed project's front end does with streams, CORS preflights, unknown functions and forged
tokens is not measured. Treat those parts as unverified.

## What you add

```yaml
dependencies:
  firebase_app_dart: ^0.2.3
  cloud_functions_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: cloud_functions/cloud_functions_dart
dependency_overrides:
  _firebase_transport_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_core/_firebase_transport_dart
```

`cloud_functions_dart` depends on `_firebase_transport_dart`, the repository's internal request helpers, which is not
on pub.dev yet; the override goes away when both are published, and `dart pub add cloud_functions_dart` does the
rest. For a signed-in user add `firebase_auth_providers_dart` ([Authentication](authentication.md)). No Flutter
dependency; Dart 3.8 or later.

On Flutter, Windows and Linux have no FlutterFire `cloud_functions` implementation; use this package directly on
those platforms. The adapter that lets `cloud_functions`' own API run on it, `cloud_functions_dart_platform`, is
planned and not part of 0.1.0.

## Set up

One `FirebaseFunctions` per app, created once and closed when you are done. The app needs a `projectId`; this
client sends neither the API key nor the app id.

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
final FirebaseFunctions functions = FirebaseFunctions(
  app,
  region: 'europe-west1',
  timeout: const Duration(seconds: 30),
);
```

| Setting | Meaning |
|---|---|
| `region` | `us-central1` by default; one DNS label such as `europe-west1`. A URL is not accepted: use `customDomain` |
| `customDomain` | an `https` URL, or `http` to a loopback host. A path is kept and trailing slashes are removed |
| `emulatorHost` | `host:port`, IPv6 in brackets; no scheme, no path, no Google host. It wins over a custom domain |
| `timeout` | the default of every callable, 70 seconds; any positive duration, clamped to 2147483647 ms |
| `httpClient` | your own `http.Client`; `close()` does not close it |
| `onWarning` | receives the token warnings; by default they go to `dart:developer`'s `log` |

The URL of a call by name is `https://<region>-<projectId>.cloudfunctions.net/<name>`; with a custom domain
`<domain><path>/<name>`; with the emulator `http://<host>:<port>/<projectId>/<region>/<name>`. A project id that
cannot form a host label (`example.com:project`) works only with `customDomain` or `httpsCallableFromUrl`.

## Calling a function

```dart
final HttpsCallable echo = functions.httpsCallable('echo');
final HttpsCallableResult result = await echo.call(<String, Object?>{'name': 'Ada'});
print(result.data);
```

`httpsCallableFromUrl(Uri)` takes the URL as given (the emulator setting does not rewrite it); it must have no query,
fragment or user info, and `http` only for loopback or the configured emulator. A call with no argument sends
`{"data": null}`.

`HttpsCallable.url`, `.options` and `.timeout` describe the callable. Options are fixed when the callable is made:

```dart
final HttpsCallable report = functions.httpsCallable(
  'report',
  options: const HttpsCallableOptions(
    timeout: Duration(minutes: 5),
    limitedUseAppCheckTokens: true,
  ),
);
print(report.timeout);
```

## Values

A request value is `null`, `bool`, a finite `num`, `String`, a `List`, or a `Map` with `String` keys, nested at
most 512 levels. Anything else is an `ArgumentError` thrown by `call` before sending, and its message names the path
(`data.items[3].name`) and the type, never the value. In particular `DateTime` is refused: send an ISO string.

- A whole `double` below 1e21 is written as an integer (`2.0` goes out as `2`), as JavaScript does, so a typed
  server (Go) can read it into an integer field.
- An `int` beyond ±(2^53 − 1) (VM and dart2wasm) is sent as its exact digits. A Node function reads it as a
  JavaScript number and rounds it; a Python function keeps it. Send such ids as strings to a Node function.
- No request value is ever wrapped in `Int64Value`.

A result is decoded as JSON: `null`, `bool`, `int`, `double`, `String`, `List<Object?>`, `Map<String, Object?>`.

```dart
final HttpsCallableResult result = await functions.httpsCallable('profile').call();
final Map<String, Object?> profile = result.data! as Map<String, Object?>;
final int visits = (profile['visits']! as num).toInt();
print('${profile['name']} visited $visits times');
```

Casting to a narrower type such as `Map<String, int>` fails at runtime. Numbers keep the type `jsonDecode` gives
them: a Node function sends a whole double as `1`, Python as `3.0`; read numbers as `num`. A `{"@type":
"type.googleapis.com/google.protobuf.Int64Value", "value": "<digits>"}` map (the protocol's 64-bit wrapper, which
the Node and Python servers do not send) decodes to an `int`; one that the platform cannot hold exactly (above
2^53 − 1 on dart2js) is an `internal` error rather than a rounded number. A map with another `@type` is returned as
a map. A response with bare `NaN` or `Infinity` (Python can send them) is an `internal` error.

Limits: a response body of 32 MiB, an error body of 1 MiB, a stream event of 32 MiB, a stream of 1 GiB. Decoding runs
on the calling isolate; a Flutter app that expects megabytes decodes them in a background isolate.

## Errors

```dart
try {
  await functions.httpsCallable('createItem').call(<String, Object?>{'id': 7});
} on FirebaseFunctionsException catch (error) {
  switch (error.code) {
    case 'already-exists':
    case 'aborted':
      print('conflict (HTTP ${error.httpStatus}): ${error.message}');
    case 'unauthenticated':
      print('sign in first');
    case 'unavailable' || 'deadline-exceeded':
      print('try again later');
    default:
      print('${error.code}: ${error.message}; details: ${error.details}');
  }
}
```

`FirebaseFunctionsException` has `code`, `message`, `details` (the decoded `details` the function passed to
`HttpsError`, or null), `httpStatus` (null when no response arrived) and `cause`, which is always null in 0.1.0.
`toString()` is `[firebase_functions/<code>] <message> (HTTP <n>)`, never with details. There are 16 codes
(`firebaseFunctionsExceptionCodes`): `cancelled`, `unknown`, `invalid-argument`, `deadline-exceeded`, `not-found`,
`already-exists`, `permission-denied`, `resource-exhausted`, `failed-precondition`, `aborted`, `out-of-range`,
`unimplemented`, `internal`, `unavailable`, `data-loss`, `unauthenticated`.

Where a code comes from:

| Source | Code |
|---|---|
| the body of the answer (`{"error": {"status": "ALREADY_EXISTS", ...}}`) | that status, in kebab case. The body decides, not the HTTP status: 409 is used for both `already-exists` and `aborted` |
| an answer with no callable body (a proxy's page, the router's 404, a 400 `text/html` for malformed JSON) | the HTTP status: 400 `invalid-argument`, 401 `unauthenticated`, 403 `permission-denied`, 404 `not-found`, 409 `aborted`, 429 `resource-exhausted`, 499 `cancelled`, 500 `internal`, 501 `unimplemented`, 503 `unavailable`, 504 `deadline-exceeded`, others `unknown` |
| an unknown status name in the body | `internal` |
| socket, DNS, TLS or a broken body, a redirect | `unavailable` (on the web also a response without CORS headers) |
| the timeout | `deadline-exceeded` |
| `abortTrigger`, or `close()` | `cancelled` |
| an Auth provider error | `unauthenticated`; an Auth provider that did not answer in 10 s: `unavailable`; an ID token over 8192 characters: `failed-precondition` |
| a response that is not what the protocol says | `internal` |

The server's message is kept for every code, `internal` included, after control characters are removed and the text
is cut at 1 KiB. A function that throws a plain `Error` gives `internal` with the message "INTERNAL": the server
sends nothing else. A status `OK` in an error body, with no result, is `internal`, not a null result.

Programmer errors are not `FirebaseFunctionsException`: an invalid name, URL, region, option or value is an
`ArgumentError`, a missing `projectId` or a use after `close()` a `StateError`.

## Timeouts and cancellation

The timeout covers the whole call: fetching the tokens, sending, waiting and reading. When it runs out the request
is aborted and the call fails with `deadline-exceeded`. A function that already started may still run to its end on
the server, so a call that timed out may have had its effect. Nothing is retried; a call that is not idempotent must
not be retried blindly.

```dart
import 'dart:async';

final Completer<void> cancel = Completer<void>();
final Future<HttpsCallableResult> pending = functions
    .httpsCallable('slow')
    .call(null, cancel.future);
Timer(const Duration(seconds: 2), cancel.complete);
try {
  await pending;
} on FirebaseFunctionsException catch (error) {
  print(error.code); // cancelled
}
```

Completing `abortTrigger` (with a value or an error) aborts the request and the call fails with `cancelled`; if it
completes before the call sends, nothing is sent. `close()` does the same for every call and stream of the instance
and waits until they settled; it does not wait for a token provider that is still answering.

## Streaming

A streaming callable sends chunks (`response.sendChunk(...)` in Node) before its return value. `stream()` returns
a single-subscription stream of `CallableStreamEvent`: any number of `CallableMessage`s, then one `CallableResult`
as the last event, or an error.

```dart
final Stream<CallableStreamEvent> events = functions
    .httpsCallable('summarize')
    .stream(<String, Object?>{'text': 'long text'});
final StreamSubscription<CallableStreamEvent> subscription = events.listen(
  (CallableStreamEvent event) {
    switch (event) {
      case CallableMessage(:final Object? data):
        print('chunk: $data');
      case CallableResult(:final Object? data):
        print('final: $data');
    }
  },
  onError: (Object error) => print('failed: $error'),
);
await Future<void>.delayed(const Duration(seconds: 5));
await subscription.cancel();
```

The request is sent when the stream is listened to. Cancelling the subscription, completing `abortTrigger` or
closing the instance aborts it; a cancelled subscription gets no error. After the result or an error nothing more
is emitted. Pausing the subscription pauses the reading of the response.

- **Timeouts.** `timeout` bounds the wait for the response headers (the token wait included) and then each silence
  in the body. It does not bound the stream's total time. A Node function sends a `: ping` comment after
  `heartbeatSeconds` of silence (30 by default), which restarts the timer: keep `timeout` above the function's
  `heartbeatSeconds`.
- **Errors arrive in the stream.** A Node function answers a streaming request with HTTP 200 whatever happens and
  writes the failure as a frame, so the error is emitted like any other. A non-2xx answer (the emulator's router, a
  proxy) is handled like a unary response.
- **A function that cannot stream** (a Python function, or a request whose `Accept` header the server did not
  take) answers one JSON body; it arrives as a single `CallableResult`.
- **A stream that ends before its result** is an `internal` error with the message "The stream ended before the
  function returned a result.".

## The emulator

Start the repository's emulator and call its fixture, or point `emulatorHost` at your own `firebase emulators:start`:

```sh
npm ci --prefix tool/functions_emulator/functions    # once
./tool/start_functions_emulator.sh 9501
export FIREBASE_FUNCTIONS_EMULATOR_HOST=127.0.0.1:9501
```

```dart
final FirebaseFunctions emulated = FirebaseFunctions(
  app,
  emulatorHost: FirebaseFunctions.emulatorHostFromEnvironment ?? '127.0.0.1:5001',
);
```

The Firebase CLI does not export a variable for the Functions emulator, so `emulatorHostFromEnvironment` reads
`FIREBASE_FUNCTIONS_EMULATOR_HOST`, which you set (always null on the web). A host that is not loopback works but
logs a warning once, because the user's tokens then travel over plain `http`.

The emulator does not verify ID tokens: it decodes any JWT, an unsigned one included, and shows the user to the
function. A test can therefore hand the client an `AuthTokenProvider` that returns
`<base64url header {"alg":"none"}>.<base64url payload with sub and user_id>.` (an empty signature); the program in
[`example/emulator.dart`](../../cloud_functions/cloud_functions_dart/example/emulator.dart) does it. The emulator
accepts any `X-Firebase-AppCheck` value and shows it as `request.app` without verifying it.

The fixture's functions (`tool/functions_emulator/functions/index.js`) cover echoing values, the server's view of
the caller, every error code, a slow call, streams with chunks, errors, silences and heartbeats, and responses with
64-bit wrappers. Each says what it does in a comment.

## Signed-in users and App Check

The client reads `app.authProvider` and `app.appCheckProvider` at every call. Set them before the first call, or at
any time: a provider installed later is used from the next call.

```dart
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
await auth.signInWithEmailAndPassword(
  email: 'user@example.com',
  password: 'a password',
);
final HttpsCallableResult result = await functions.httpsCallable('whoami').call();
print(result.data);
```

- **ID token.** When a user is signed in the call carries `Authorization: Bearer <ID token>`. With no provider, no
  user, or an API that is not available, the call goes out without it (the function sees a signed-out caller). An
  error from the provider fails the call with `unauthenticated` instead of silently calling as a signed-out user.
- **App Check.** `X-Firebase-AppCheck` carries the provider's token. App Check never fails a call: a token with an
  error (the placeholder the SDKs send when attestation fails) is sent so that the backend can see it; no token, a
  throw or a timeout means no header. With `limitedUseAppCheckTokens: true` the provider must implement
  `LimitedUseAppCheckTokenProvider`, otherwise no App Check header is sent. This repository has no App Check package
  yet, so App Check is optional and unverified against a real project.
- **Where tokens go.** Only to `https` hosts, the configured emulator and loopback. A destination that may not
  receive them fails the call with `failed-precondition` and nothing is sent. Tokens go to any `https` custom domain
  or `httpsCallableFromUrl` URL you give, as in the official SDKs: use hosts you control.
- **After a refusal.** A bare HTTP 401 that has no callable body (a front end refusing the token before the
  function) to a request that carried an ID token makes the next call force a token refresh, at most once a minute.
  The failed call is not resent. A `unauthenticated` answer from the function itself never triggers a refresh.

## The web

The same code compiles with dart2js and dart2wasm; the library imports no `dart:io`. The default `http.Client` is
fetch-based and streams response bodies, so streams and cancellation work. A browser needs the function to answer
the CORS preflight for `content-type`, `authorization`, `x-firebase-appcheck` and `accept`; the emulator does
(`cors: true`), and the answer of a deployed function is unmeasured. A CORS rejection, a network failure and a
crashing backend look alike to a page and are all `unavailable`. dart2js numbers are JavaScript numbers: an `int`
above 2^53 − 1 cannot be held, so a wrapped 64-bit result beyond it is an `internal` error there, and
`emulatorHostFromEnvironment` is null.

## Security notes

- Redirects are never followed, so the `Authorization` header cannot reach a second host.
- Tokens, the request data and URLs with a query never appear in a message, `toString` or warning.
- Response sizes are capped and nesting is limited to 512 levels; a hostile server cannot make the client read an
  endless body.
- A custom domain or a `httpsCallableFromUrl` host sees the user's ID token: only configure hosts you control.
- The API key and the app id are not sent; a function is protected by Auth, App Check and its own checks, not by
  the key.
