# firebase_app_check_dart

An unofficial pure-Dart client of Firebase App Check. It gets App Check tokens, caches them, replaces them before they
expire, and hands them to the other Firebase clients of this repository through the `FirebaseApp`. It is meant for
programs the official SDKs do not cover: Linux and Windows desktop apps, command-line tools, Dart servers and web
apps. It runs on the Dart VM and in the browser (dart2js and dart2wasm).

**Status: in development, not released.** Depend on it from this repository. The
[App Check guide](../../docs/guides/app_check.md) covers setup step by step, the comparison with the official SDKs is
in [docs/app_check_parity.md](../../docs/app_check_parity.md), and the reasons for each choice are in
[docs/app_check_decisions.md](../../docs/app_check_decisions.md).

There are two providers:

- **Debug**: exchanges a debug token, which you register in the Firebase console, for App Check tokens.
- **Custom**: calls a function of your app, usually one that asks your own server for a token.

There is no reCAPTCHA provider and no native attestation (Play Integrity, App Attest, DeviceCheck). On Android, iOS and
macOS use FlutterFire's `firebase_app_check`. A FlutterFire adapter for Linux and Windows,
`firebase_app_check_dart_platform`, is planned and not part of this release.

## Install

The package is not on pub.dev. In a checkout of this repository, depend on it by path:

```yaml
dependencies:
  firebase_app_check_dart:
    path: firebase_app_check/firebase_app_check_dart
```

## Use

Create `FirebaseAppCheck` **before** Firestore, Auth and Database. Those three read the app's provider when they are
created and keep it; one created earlier sends no App Check token and reports nothing, until it is created again.
Storage, Analytics, Error Reporting, Functions, AI Logic and Data Connect read the provider at each request and have no
such order.

```dart
import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';
import 'package:firebase_app_check_dart/io.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

Future<void> main() async {
  final FirebaseApp app = await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'my-api-key',
      appId: '1:1234567890:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );
  final FirebaseAppCheck appCheck = FirebaseAppCheck(
    app,
    provider: debugProviderFromEnvironment(),
    logger: (AppCheckLogLevel level, String message) => print('[${level.name}] $message'),
  );
  final AppCheckToken token = await appCheck.getToken();
  print('token of ${token.token.length} characters, expires ${token.expireTime}');
  await appCheck.close();
}
```

The constructor reads and sends nothing. By default the instance installs itself as `app.appCheckProvider`, so the
clients created afterwards send the token without further code; `install: false` leaves the app alone.

## The debug provider

A debug token is a version 4 UUID that you register for your app in the Firebase console (App Check, Apps, Manage debug
tokens). Whoever holds it gets App Check tokens for that app until you delete it, so it is a **secret**:

- Do not ship it in an app that other people run. The Dart package does not detect a release build, because servers
  and tools use debug tokens on purpose. For apps you distribute, use a custom provider backed by your own server, or
  FlutterFire's native providers on mobile.
- `DebugAppCheckProvider(debugToken: …)` takes it from the constructor; nothing else is read. There is no global switch,
  no page variable and the Firebase CLI's configuration file is not read.
- On the VM, `debugProviderFromEnvironment()` from `package:firebase_app_check_dart/io.dart` reads the variable
  `FIREBASE_APPCHECK_DEBUG_TOKEN`. When it is unset, empty or not a version 4 UUID it throws a `StateError` that names
  the variable, never its value.
- `DebugAppCheckProvider.generateDebugToken()` returns a new random UUID for you to register. The package never logs
  or stores it, and nothing prints it for you.
- Pass a `logger` while developing. Without one the package prints and logs nothing. With one it writes a warning that
  a debug provider is in use, a debug line for each token received, and a warning for each failed request. No line
  ever contains a token, the API key or a response body.

A web app has no environment: pass the token to the constructor. A token given through `--dart-define` is compiled into
the JavaScript file, so such a build must never be deployed.

## The custom provider

```dart
import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';

Future<String> mintTokenOnMyServer({required bool limitedUse}) async {
  // Ask your own server; it decides who gets a token.
  return 'a-token-from-your-server';
}

final FirebaseAppCheck appCheck = FirebaseAppCheck(
  app,
  provider: CustomAppCheckProvider(
    getToken: ({required bool limitedUse, required bool forceRefresh}) async {
      final String token = await mintTokenOnMyServer(limitedUse: limitedUse);
      return AppCheckToken(
        token: token,
        expireTime: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
    },
  ),
);
```

- The callback is called for every exchange. `limitedUse` is true for `getLimitedUseToken()`: mint a token for one use.
  `forceRefresh` is true when a service says the backend refused the previous token: return a different one. A
  callback that returns the token it was asked to replace gets a `provider-error`.
- It is not called while a gate window is open (after a failure, calls fail with `throttled` until the window ends).
- It has 7 seconds. After that the call fails with `provider-timeout`, but a **late answer to a session request is
  kept**: a valid token becomes the session token and is announced. A late answer to a limited-use request is dropped.
- The token must be 1 to 8192 printable ASCII characters and expire at least 60 seconds from now; an expiry more than
  7 days away counts as 7 days. The package does not read the JWT.

## Limited-use tokens

`getLimitedUseToken()` makes a new exchange on every call and returns a token meant to be consumed once by a backend
with replay protection. It is never cached, never shared between callers and never announced on `onTokenChanged`.
Each call costs one exchange; do not call it in a loop.

## Refresh, `close()` and the process

- The session token is reused while it has at least `min(5 minutes, lifetime / 2)` left. Concurrent calls share one
  exchange.
- Auto-refresh is on by default and starts with the first token: about 35 minutes after a one-hour token was issued
  the instance gets a new one. `autoRefresh: false` or `setTokenAutoRefreshEnabled(false)` turns it off.
- `onTokenChanged` emits each new session token. It does not replay to a new listener and never emits an error.
- **An instance that holds a token keeps a timer, so the process does not exit until `close()` is called.** A
  command-line tool calls `close()` when done, or passes `autoRefresh: false`. After `close()`, services created
  earlier send no App Check header until a new `FirebaseAppCheck` is created for the same app.
- An idle process with auto-refresh on spends one exchange per refresh, every 35 minutes for a one-hour token.

## Errors

A failed public call throws `FirebaseAppCheckException` (plugin `firebase_app_check`, kebab-case `code`, a fixed
`message`). Server text and the cause are in fields (`serverMessage`, `cause`), never in the message. A token is never
in a message, a `toString` or a log line.

| Code | When |
|---|---|
| `fetch-network-error` | The exchange could not be sent or read (a refused redirect included). |
| `fetch-timeout` | No complete response in 7 seconds. |
| `fetch-status-error` | The server answered with a status other than 200 (`httpStatus`, `serverStatus`, `serverMessage`). |
| `fetch-parse-error` | A 200 whose body is oversized, not JSON, has no valid token or has an invalid `ttl`. |
| `throttled` | A gate refused the call after a failure (`retryAfter`). |
| `provider-error` | The custom callback threw or broke a rule (`cause`). |
| `provider-timeout` | The custom callback did not answer in 7 seconds. |
| `app-check-closed` | A call after `close()`. |

A malformed API key, app id or project id is an `ArgumentError` in the constructor (it names the option, never the
value); a missing or empty one is a `StateError` at the first exchange. `firebaseAppCheckExceptionCodes` lists the
codes.

## Persistence

Without a `store` the token lives in memory: every process start and every page load costs one exchange, and every
browser tab holds its own token. With a `store` the session token survives a restart and is shared by the tabs of a
web origin. The store is a `KeyValueStore` of `firebase_installations_dart`, whose type and `MemoryKeyValueStore` this
package re-exports:

| Platform | Store |
|---|---|
| Dart VM | `FileKeyValueStore` from `package:firebase_installations_dart/io.dart` |
| Browser | `IndexedDbKeyValueStore` from `package:firebase_installations_dart/web.dart` |
| Tests, or no persistence | `MemoryKeyValueStore` |

Only the session token is stored (its token string, issue time and lifetime), under a key made from the app. Limited-use
tokens, debug tokens and the rate-control state are never written. The record is **not encrypted**: other processes of
the same user on a desktop, and every script of a web origin, can read it. A pure-Dart app that also uses Installations
passes both the same store object, because one process owns a file store's directory.

## Limits

- Only the debug and custom providers exist. On a desktop or a server nothing else can.
- A debug token is a shared secret; see above.
- Rate control is forgotten at restart. A misconfigured app (a wrong app id, an unregistered debug token) sends one
  refused exchange per process start or page load; nothing here bounds a restart loop.
- After repeated refusals an instance waits up to 4 hours between attempts, also after the cause was fixed on the
  server. Closing the instance and creating a new one starts open.
- Against a backend that refuses every token while services keep forcing a refresh, an instance exchanges once per 30
  seconds: 2 880 exchanges a day.
- On Linux and macOS a file store's lock does not separate isolates. A second isolate of one process passes
  `store: MemoryKeyValueStore()` or its own directory.
- Token strings longer than 8192 characters are refused. A token lifetime under 60 seconds is refused.

## Emulators

The Firebase CLI has no App Check emulator. A program that talks only to the emulators should create no
`FirebaseAppCheck`, or use a `CustomAppCheckProvider` that returns a fixed string: a debug provider calls the real
exchange endpoint. A fixed-string callback answers a forced refresh with the same token, which is a `provider-error`;
the caller still gets the cached token.

## Restricted API keys

A debug exchange sends the API key of the app in the `X-Goog-Api-Key` header and nothing that identifies a platform: no
Android package, certificate or iOS bundle id, because a value typed by the app on another platform would be a false
claim. A key restricted to an Android or iOS application, or to browser referrers, may therefore refuse the request
from a desktop or a server. Use an unrestricted key for those programs, or a custom provider, which needs no API key.

## What is not here

- reCAPTCHA v3 and reCAPTCHA Enterprise on the web: later.
- Play Integrity, App Attest and DeviceCheck: not planned.
- gRPC: the exchange is a plain HTTPS request.
- The FlutterFire bridge: `firebase_app_check_dart_platform`, planned.

Examples are in [example/](example/): `main.dart` is the one pub.dev shows; the others cover the debug provider,
limited-use tokens and a custom provider that asks an HTTP endpoint.
