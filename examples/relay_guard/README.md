# relay_guard

The checks every relay in this repository makes before it forwards a request with its own credentials. A relay
is a small server of yours: an app in users' hands sends it error reports (`firebase_error_reporting_dart`) or
analytics events, and the relay forwards them to a Google API with a credential the app must not hold. Without
checks anyone could use it to write into your project.

`relayGuard(verifier: ...)` is `package:shelf` middleware that lets a request through only when:

- it is a `POST` of `application/json`, to `path` when one is given, no larger than `maxBodyBytes` (64 KiB by
  default) whether the size is declared or streamed, and the body arrives within `bodyTimeout` (10 s);
- it has a valid App Check token in `X-Firebase-AppCheck` (unless `requireAppCheck: false`, for development);
- a Firebase ID token in `Authorization: Bearer`, when present, is valid; with `requireUser: true` it must be
  present;
- every rate limit has room, each a window of one minute: `maxPerCallerPerMinute` (60) per App Check token
  **and** per user, so many accounts behind one token do not multiply the budget; `maxPerAppPerMinute` (3000)
  per app; `maxPerMinute` (10000) in all. Without an App Check token the address counts instead of the token.
  Behind a proxy (Cloud Run's front end, a load balancer) the connection's address is the proxy's: set
  `trustedProxyHops` to the number of proxies that append to `X-Forwarded-For` (1 on Cloud Run), and the address
  is read that many entries from the right, so a caller cannot choose it. IPv6 counts per /64. The limits are
  per process: with several instances each counts on its own.

It answers 404, 405, 415, 413, 408, 400, 401, 429 (`Retry-After: 60`) or 503 (`Retry-After: 30`, when the keys
that check the tokens could not be fetched), with `Connection: close` and without saying why: the reason goes to
`log`. The handler behind it reads `callerOf(request)` (the verified app id and uid) and `bodyOf(request)`.

Serve it with `serveGuarded(handler, address, port)` instead of `shelf_io.serve`: it destroys every connection
20 seconds after it was accepted, because a client that sends the headers and never the body would otherwise
hold the connection forever (`dart:io` reads the body before it writes any answer). On Cloud Run also set
`--timeout=30` and choose `--concurrency` and `--max-instances`.

Tokens are checked by a `CallerVerifier`. `AdminCallerVerifier(FirebaseAdminApp app)` uses
`firebase_admin_dart`: `app.appCheck().verifyToken` and `app.auth().verifyIdToken`. Checking needs no
credential, only the project id; pass `projectNumber` to make the App Check check exact. Only verdicts about
the token or the user become `CallerRejected` (401); anything else (keys that cannot be fetched, the permission
of the credential with `checkRevoked`) reaches the guard as an error (503). An app made with
`FirebaseAdminApp.emulator` is refused unless `allowEmulator: true`: it accepts unsigned ID tokens for any uid.
ID tokens of every tenant of the project are accepted, and without `checkRevoked` a disabled user's token
passes until it expires (at most an hour). Implement `CallerVerifier` yourself to use another library.

```
dart test        # no emulator needed
```

Used by [`error_reporting_relay`](../error_reporting_relay/). Not done: App Check replay protection
(`consumeAppCheckToken`).
