# relay_guard

The checks every relay in this repository makes before it forwards a request with its own credentials. A relay
is a small server of yours: an app in users' hands sends it error reports (`firebase_error_reporting_dart`) or
analytics events, and the relay forwards them to a Google API with a credential the app must not hold. Without
checks anyone could use it to write into your project.

`relayGuard(verifier: ...)` is `package:shelf` middleware that lets a request through only when:

- it is a `POST` of `application/json` no larger than `maxBodyBytes` (64 KiB by default), whether the size is
  declared or streamed;
- it has a valid App Check token in `X-Firebase-AppCheck` (unless `requireAppCheck: false`, for development);
- a Firebase ID token in `Authorization: Bearer`, when present, is valid; with `requireUser: true` it must be
  present;
- the caller has sent fewer than `maxPerMinute` requests in the last minute. The caller is the user when an ID
  token was given, else the app and the address of the connection, else the address.

It answers 405, 415, 413, 401, 429 (`Retry-After: 60`) or 503 (`Retry-After: 30`, when the keys that check the
tokens could not be fetched), without saying why: the reason goes to `log`. The handler behind it reads
`callerOf(request)` (the verified app id and uid) and `bodyOf(request)`.

Tokens are checked by a `CallerVerifier`. `AdminCallerVerifier(FirebaseAdminApp app)` uses
`firebase_admin_dart`: `app.appCheck().verifyToken` and `app.auth().verifyIdToken`. Checking needs no
credential, only the project id; pass `projectNumber` to make the App Check check exact. Implement
`CallerVerifier` yourself to use another library.

```
dart test        # no emulator needed
```

Used by [`error_reporting_relay`](../error_reporting_relay/). Not done: App Check replay protection
(`consumeAppCheckToken`).
