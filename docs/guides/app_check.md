# App Check

`firebase_app_check_dart` is an unofficial pure-Dart client of Firebase App Check for programs the official SDKs do
not cover: Linux and Windows desktop apps, command-line tools, Dart servers and web apps. It is **in development and
not released**: depend on it from this repository. It has two providers, **debug** (exchanges a debug token that you
register in the Firebase console) and **custom** (a token from your own server). It has no reCAPTCHA provider and no
native attestation (Play Integrity, App Attest, DeviceCheck); on Android, iOS and macOS use FlutterFire's
`firebase_app_check`. The comparison with the official SDKs is in [app_check_parity.md](../app_check_parity.md) and
the reasons for each choice in [app_check_decisions.md](../app_check_decisions.md).

## What App Check does

App Check lets a Firebase backend tell requests from your registered app from requests from anything else. The app
gets an **App Check token**, a signed JWT valid for about an hour, and sends it in the header `X-Firebase-AppCheck`
with every request to Firestore, Storage, Functions, the Realtime Database and the other products. A product that
has App Check **enforcement** turned on refuses requests without a valid token.

This package does three things:

1. It gets tokens from a provider, caches them and replaces them before they expire.
2. It plugs into the `FirebaseApp`: the other clients of this repository (Firestore, Auth, Database, Storage,
   Analytics, Error Reporting, Functions, AI Logic, Data Connect) read the token through
   `FirebaseApp.appCheckProvider`, so you create `FirebaseAppCheck` once and nothing else needs to know about it.
3. It backs off after failures, so a misconfigured app does not hammer the App Check service.

A token is a bearer credential: whoever holds it can use it. The package never logs a token, never puts one in an
exception message or a `toString`, and never writes one anywhere unless you give it a `store`.

## Choosing a provider

| Provider | Use it for | The secret |
|---|---|---|
| `DebugAppCheckProvider(debugToken:)` | Development, tests and your own servers and tools that you trust. | A debug token. Whoever holds it gets App Check tokens for the app until you delete it in the console. |
| `CustomAppCheckProvider(getToken:)` | Apps that you distribute: your own server decides who gets a token and mints it. | None in the app. |

An app distributed to other people **must not contain a debug token**: anyone can extract it, and App Check is then
bypassed for your app until you delete the token. The Dart package does not detect a release build, because servers
and tools use debug tokens on purpose. Use a custom provider backed by your own server, or FlutterFire's native
providers on mobile.

Create `FirebaseAppCheck` **before** Firestore, Auth and Database. Those three read the app's provider when they are
created and keep it, so one created earlier sends no App Check token and reports nothing, until it is created again.
Storage, Analytics, Error Reporting, Functions, AI Logic and Data Connect read the provider at each request and have
no such order.

```dart
import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';

final FirebaseAppCheck appCheck = FirebaseAppCheck(
  app,
  provider: DebugAppCheckProvider(debugToken: '00000000-0000-4000-8000-000000000000'),
);
```

The value above is an obvious placeholder; a real debug token comes from the next section. The constructor reads and
sends nothing. It checks the provider's configuration (a malformed API key, app id or project id is an
`ArgumentError` that names the option and never its value), and with `install: true`, the default, it sets the
provider on the app. A second instance with `install: true` for the same app throws a `StateError` while the first
is open.

## Debug tokens, step by step

1. Create a token. The console accepts one you supply, so generate it in your program or with any UUID tool:

   ```dart
   import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';

   final String debugToken = DebugAppCheckProvider.generateDebugToken();
   ```

   Printing it once to copy it into the console is the only time it should appear anywhere. The package never logs
   or stores it.

2. Register it: Firebase console, App Check, Apps, the app's menu, **Manage debug tokens**, Add debug token.

3. Give it to the program through the environment, not through source code or a command line (other users can see
   command lines in the process list). On the VM, `io.dart` reads the variable `FIREBASE_APPCHECK_DEBUG_TOKEN`:

   ```dart
   import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';
   import 'package:firebase_app_check_dart/io.dart';

   final FirebaseAppCheck appCheck = FirebaseAppCheck(
     app,
     provider: debugProviderFromEnvironment(),
     logger: (AppCheckLogLevel level, String message) => print('[${level.name}] $message'),
   );
   final AppCheckToken token = await appCheck.getToken();
   print('token of ${token.token.length} characters, expires ${token.expireTime}');
   ```

   `debugProviderFromEnvironment()` throws a `StateError` that names the variable, never its value, when it is unset,
   empty or not a version 4 UUID. A web app has no environment: pass the token to the constructor, and remember that
   a token compiled in with `--dart-define` is in the JavaScript file, so such a build must never be deployed.

4. Pass a `logger` while you develop. Without one the package prints nothing. With one you see a warning that a
   debug provider is in use, a debug line for each token received and when the next refresh is, and a warning for
   each failed request, with the error code and the next attempt.

5. Delete the token in the console when you are done.

A debug provider calls the real exchange endpoint, so a program that talks only to the Firebase emulators should
create no `FirebaseAppCheck` at all. There is no App Check emulator.

## A custom provider with a server

A custom provider has no secret in the app. Your server checks that the caller is your app by whatever means you
have (a sign-in, a purchase, an attestation of its own), mints an App Check token with the Firebase Admin SDK
(`appCheck().createToken(appId)`) and answers with the token and its expiry. The callback asks for it:

```dart
import 'dart:convert';

import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';
import 'package:http/http.dart' as http;

final FirebaseAppCheck appCheck = FirebaseAppCheck(
  app,
  provider: CustomAppCheckProvider(
    getToken: ({required bool limitedUse, required bool forceRefresh}) async {
      final http.Response response = await http.post(
        Uri.https('example.com', '/app-check-token', <String, String>{
          if (limitedUse) 'limitedUse': 'true',
          if (forceRefresh) 'forceRefresh': 'true',
        }),
      );
      final Map<String, Object?> body = jsonDecode(response.body) as Map<String, Object?>;
      return AppCheckToken(
        token: body['token']! as String,
        expireTime: DateTime.fromMillisecondsSinceEpoch(
          body['expireTimeMillis']! as int,
          isUtc: true,
        ),
      );
    },
  ),
);
```

The rules of the callback:

- It is called for every exchange, not once. The package caches the token and calls it again when the token is
  about to stop being usable, or when a forced refresh needs a new one.
- `limitedUse` is true when the token is for `getLimitedUseToken()` and must be minted for one use. `forceRefresh` is
  true when a service says the backend refused the previous token: return a different one. A callback that returns
  the token it was asked to replace gets a `provider-error`, and the caller keeps the cached token while it is still
  usable.
- It has **7 seconds** to answer. A callback that does not answer in time causes a `provider-timeout`. Its late
  answer to a session request is not wasted: when it is a valid token it becomes the session token and is announced.
  A late answer to a limited-use request is dropped, because nobody is waiting for it.
- A token must be 1 to 8192 printable ASCII characters and must expire at least 60 seconds from now. An expiry more
  than 7 days ahead is treated as 7 days. The package does not read the JWT.
- A callback that throws gives a `provider-error`; the thrown object is kept in the exception's `cause` and is never
  put into a message.
- The callback is not called during a gate window (see [Troubleshooting](#troubleshooting)): after a failure, calls
  fail with `throttled` until the window ends.

For tests, and for apps that talk only to the emulators, a callback that returns a fixed string is enough. It
answers a forced refresh with the same token, which is a `provider-error` by the rule above; the caller still gets
the cached token.

## Limited-use tokens

A limited-use token is for one request to a backend that does replay protection: it is consumed when the backend
checks it. `getLimitedUseToken()` always makes a new exchange, never reads or replaces the session token, is never
cached and is never announced on `onTokenChanged`. The Functions client asks for one when it is configured to use
limited-use App Check tokens; the package does not send it anywhere by itself.

```dart
import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';

final AppCheckToken limitedUse = await appCheck.getLimitedUseToken();
```

Each call costs one exchange, so do not call it in a loop. A failure feeds a separate gate from the session token's:
a burst of failed limited-use requests does not stop session tokens for the other clients.

## Lifetime and `close()`

`getToken()` returns the cached token while it is **usable**: it has at least `min(5 minutes, lifetime / 2)` left.
Otherwise it exchanges. Concurrent calls share one exchange, and a call with `forceRefresh: true`, which says the
backend rejected the cached token, joins it too. A forced call less than 30 seconds after the token was issued gets
that token back: this floor bounds a backend that rejects every token to one exchange per 30 seconds.

**Auto-refresh** is on by default and starts with the first token. About 35 minutes after a one-hour token was
issued, minus a small random amount so that browser tabs do not all exchange together, the instance gets a new one
by itself. `autoRefresh: false` or `setTokenAutoRefreshEnabled(false)` stops it; every token is then fetched inside
the call that needs it. `onTokenChanged` emits each new session token, with no replay for a new listener and no
errors.

An instance that holds a token keeps a timer for the next refresh, so **the process does not exit** until you call
`close()`. A command-line tool calls `close()` when it is done, or passes `autoRefresh: false`.

```dart
import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';

final FirebaseAppCheck appCheck = FirebaseAppCheck(
  app,
  provider: CustomAppCheckProvider(
    getToken: ({required bool limitedUse, required bool forceRefresh}) async {
      return AppCheckToken(
        token: 'a-token-from-your-server',
        expireTime: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
    },
  ),
  autoRefresh: false,
);
try {
  final AppCheckToken token = await appCheck.getToken();
  print('expires ${token.expireTime}');
} finally {
  await appCheck.close();
}
```

`close()` cancels the timer, answers pending calls with `app-check-closed`, aborts a request in flight and closes the
stream. It is idempotent, never closes a `store` you passed in, and also runs when the app is deleted. After it,
services created earlier send **no** App Check header until you create a new `FirebaseAppCheck` for the same app: the
package keeps its seam object on the app, and the next instance binds it again.

### Keeping the token across restarts

Without a `store` the token lives in memory: every process start and page load costs one exchange, and every browser
tab holds its own token. With a `store` (a `KeyValueStore`) the session token survives a restart and is shared by
the tabs of a web origin. Only the session token is stored: never a limited-use token, a debug token or the gate
state.

```dart
import 'package:firebase_app_check_dart/firebase_app_check_dart.dart';

final FirebaseAppCheck appCheck = FirebaseAppCheck(
  app,
  provider: DebugAppCheckProvider(debugToken: '00000000-0000-4000-8000-000000000000'),
  store: store,
);
```

The store is the one of `firebase_installations_dart`: `FileKeyValueStore` and `MemoryKeyValueStore` on the VM,
`IndexedDbKeyValueStore` in a browser (`MemoryKeyValueStore` and the `KeyValueStore` type are re-exported by this
package). The token is **not encrypted**: other processes of the same user on a desktop, and every script of a web
origin, can read it. Three rules for the file store:

- One process owns a file store's directory. A pure-Dart app that also uses Installations passes both the same
  store object.
- On Linux and macOS the lock does not separate isolates of one process. A second isolate passes
  `MemoryKeyValueStore()` or its own directory.
- A store that fails is logged once and the instance carries on in memory; a stored record that is expired,
  malformed or issued in the future is ignored and removed.

## With FlutterFire

The adapter that lets `package:firebase_app_check` run on this package, `firebase_app_check_dart_platform`, is not
part of this release. On Android, iOS and macOS use the official plugin with its native providers.

## Troubleshooting

Every failure of a public call is a `FirebaseAppCheckException` with plugin `firebase_app_check`, a `code`, a fixed
`message`, and fields for what the server said. Server text and the cause of a failure are in fields only, never in
the message or in `toString`. `firebaseAppCheckExceptionCodes` lists the codes.

| Code | Cause | What to do |
|---|---|---|
| `fetch-network-error` | The exchange could not be sent or read: no network, a refused redirect, or, in a browser, a failed preflight. | Check the network. In a browser check that the host allows the request from your origin. |
| `fetch-timeout` | No complete response in 7 seconds. | Retry later; the gate does it for you. |
| `fetch-status-error` | The server answered with a status other than 200. `httpStatus`, `serverStatus` and `serverMessage` (with the debug token replaced by `<redacted>`) say more. | 400 or 403: check the app id, the API key and its restrictions (an unrestricted key works from a desktop; a restricted one may refuse it), and that the debug token is registered for this app and not deleted. 404: check the project id and app id. |
| `fetch-parse-error` | A 200 whose body is oversized, not JSON, has no valid token, or has an invalid `ttl` (under 60 seconds is refused). | Report it; the server did not answer as documented. |
| `throttled` | A gate refused the call: an exchange failed recently and the window is not over. `retryAfter` says when it is expected to end. | Wait, or fix the cause. After repeated refusals the window grows up to 4 hours, also after the cause was fixed on the server; closing the instance and creating a new one starts open. |
| `provider-error` | The custom callback threw, returned an invalid token, returned a token that expires within 60 seconds, or returned the token it was asked to replace. The thrown object is `cause`. | Fix the callback or your server. |
| `provider-timeout` | The custom callback did not answer in 7 seconds. | Make your server faster, or answer from a cache; a late answer to a session request is still kept. |
| `app-check-closed` | A call after `close()`. | Create a new `FirebaseAppCheck`. |

Two further failures are not `FirebaseAppCheckException`s, because they are mistakes in the program: a **malformed**
API key, app id or project id is an `ArgumentError` when the debug provider is constructed, and a **missing or empty**
one is a `StateError` at the first exchange, before any request is sent.

The services that use the token never see these exceptions. For them the package answers through the app's provider:
a usable token, a token in its last minutes together with the error, or a placeholder token (the base64 of
`{"error":"UNKNOWN_ERROR"}`) together with the error. The placeholder is what the backend then refuses, so under
enforcement a failing App Check shows up as a refused request in the product, not as an exception here.

### Limits to know

- Only the debug and custom providers exist. On a desktop or a server nothing else can.
- Rate control is forgotten at restart. A misconfigured app, such as a wrong app id or an unregistered debug token,
  sends one refused exchange per process start or page load; nothing in the package bounds a restart loop.
- Against a backend that refuses every token while services keep forcing a refresh, an instance exchanges once per
  30 seconds: 2 880 exchanges a day.
- Token strings longer than 8192 characters are refused, and so is a token lifetime under 60 seconds.
