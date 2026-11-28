# Functions decisions

The decisions behind `cloud_functions_dart` (`cloud_functions/cloud_functions_dart`): where the package differs from the official SDKs and why, and which alternatives were considered and rejected. [remote_config_decisions.md](remote_config_decisions.md) and [storage_decisions.md](storage_decisions.md) are the models of this document; [contributing_a_product.md](contributing_a_product.md) has the rules every product client follows. The comparison with the official SDKs, feature by feature, is in [functions_parity.md](functions_parity.md).

The first part lists the departures from upstream, D1 to D26. The second part lists what is kept on purpose. The third part lists the design decisions, 1 to 32. The fourth part lists the alternatives rejected. A departure needs a written failure that it fixes.

Which SDK each area follows:

- the protocol, the error mapping and the URL rules: JS;
- the stream result shape: Android (and FlutterFire);
- the rule that tokens do not travel over clear text, and the separate custom-domain parameter: iOS;
- the framing of a stream and the error bodies: what the server was measured to send (the Node callable server on the emulator; a Python one for the differences), not any one SDK, because the SDKs disagree with each other;
- token failures and the failure of a destination: the shared helpers of this repository (`_firebase_transport_dart`).

Every D section ends with a status line:

- **designed**: the behaviour is specified and the code is not written yet;
- **built**: the code does this, and the test named under "Pinned by" pins it.

All sections are **designed** until the library lands; the tests are written after the review.

Path shorthand for upstream code (read at the commits named in [functions_parity.md](functions_parity.md)):

| Short | Meaning |
|---|---|
| `J:` | `firebase-js-sdk/packages/functions/src/` |
| `AND:` | `firebase-android-sdk/firebase-functions/src/main/java/com/google/firebase/functions/` |
| `IOS:` | `firebase-ios-sdk/FirebaseFunctions/Sources/` |

"Pinned by" names a test file; a path without a prefix is relative to `cloud_functions/cloud_functions_dart/`. The owner of a departure is where its code lives: "Functions" is code in `cloud_functions_dart` (and reverted in the revert check of the build); "S" is code in `_firebase_transport_dart`, pinned by its own suite and re-asserted through Functions' API.

## Departures from upstream

### D1. Streams check the HTTP status first

**Decision.** A stream whose answer is not 2xx is read like a unary response: an error body gives the error, a body without one gives the code of the HTTP status. In-band error frames on HTTP 200 stay the main error path.

**Why.** JS never looks at the status (`J:service.ts:504-603`). A non-2xx answer from a router or a front end (the emulator's 404 `text/html`) has no `data:` line, so the JS stream ends empty and its `data` promise never settles.

**What we gave up.** Nothing known: the callable layer always answers 200 to a stream request.

**Pinned by.** `test/stream_test.dart`, "non-2xx HTML becomes not-found". Owner: Functions.

Status: designed.

### D2. A stream that ends without a result is an error

**Decision.** The end of the body before a `result` or `error` event gives `internal`, "The stream ended before the function returned a result."

**Why.** JS leaves the `data` promise unsettled (`J:service.ts:682-689`): a caller waits forever.

**What we gave up.** Nothing.

**Pinned by.** `test/stream_test.dart`, "ends without result". Owner: Functions.

Status: designed.

### D3. A JSON answer to a stream request is one result

**Decision.** A 2xx answer whose media type is `application/json` is handled like a unary body: one `CallableResult`, or the error.

**Why.** The Node server answers JSON when the `Accept` header is not exactly `text/event-stream` (a proxy may add a charset), and a Python callable always does, because it has no streaming. JS finds no `data:` line and its result never settles.

**What we gave up.** A function that cannot stream looks the same as one that sent only a result.

**Pinned by.** `test/stream_test.dart`, "JSON answer to a stream request". Owner: Functions.

Status: designed.

### D4. A non-JSON event closes the stream with `internal`

**Decision.** A `data:` line that is not a JSON object gives `internal`, "The server sent an event that is not valid JSON.", and the stream closes.

**Why.** JS ignores it (`J:service.ts:653-660`). The server never sends one (measured), so one means corruption, and carrying on would hide it.

**What we gave up.** A proxy that injects a line into the stream breaks it instead of being skipped.

**Pinned by.** `test/stream_test.dart`, "invalid event". Owner: Functions.

Status: designed.

### D5. An error frame with status `OK` is `internal`

**Decision.** An `{"error": {"status": "OK"}}` frame gives `internal`, "The server sent an error event with status OK.", details kept.

**Why.** JS's `_errorForResponse` returns null for `OK`, so JS then calls `controller.error(null)` and rejects `data` with null (`J:service.ts:647-651`).

**What we gave up.** Nothing.

**Pinned by.** `test/stream_test.dart`, "error frame with status OK". Owner: Functions.

Status: designed.

### D6. An idle timeout on streams

**Decision.** The call's timeout is the wait for the response headers and then the longest silence in the body; a `: ping` heartbeat restarts it. The timer itself is the shared helper's (`sendStreaming`); the value is Functions'.

**Why.** JS has none: a half-open connection hangs forever. Android caps the whole stream at 70 s (`callTimeout` and `readTimeout`, `AND:HttpsCallOptions.kt:60-66`), which ends legitimate long streams such as model output.

**What we gave up.** A function that sets `heartbeatSeconds` above the timeout fails with `deadline-exceeded`; the README says to keep the timeout above it.

**Pinned by.** `test/stream_test.dart`, "idle timeout, heartbeat resets it", "long stream with pings outlives the timeout". Owner: Functions.

Status: designed.

### D7. Reading stops at the `result` event

**Decision.** After the `result` event the stream closes and the request is aborted.

**Why.** JS keeps reading and would enqueue messages after the result.

**What we gave up.** Nothing: the server closes the connection after the result.

**Pinned by.** `test/stream_test.dart`, "nothing after result". Owner: Functions.

Status: designed.

### D8. `close()` aborts streams too

**Decision.** Closing the instance, or deleting the app, aborts every call and every stream in flight.

**Why.** JS's delete cancels only unary calls, so a stream keeps its connection open after the app is gone.

**What we gave up.** Nothing.

**Pinned by.** `test/close_test.dart`, "close aborts a stream". Owner: Functions.

Status: designed.

### D9. The timeout aborts the request

**Decision.** When the timeout runs out the request is aborted.

**Why.** JS only rejects the promise; the fetch keeps running and holds the connection (`J:service.ts:73-90,396-414`). The server sees the disconnect when the client aborts.

**What we gave up.** The function may still run to its end on the server, and the client cannot know. A timed-out call is not safe to retry unless the function is idempotent.

**Pinned by.** `test/timeout_test.dart`, "deadline aborts the request". Owner: Functions.

Status: designed.

### D10. The timeout covers the token fetch

**Decision.** The call's time is counted from the start of `call` or `stream`; the token wait gets the time left, and the request gets what remains. For a stream the headers deadline is the time left.

**Why.** JS starts its timer after the tokens (`J:service.ts:391-396`): a slow token provider delays the call beyond its timeout.

**What we gave up.** A call with a very short timeout and a provider that needs a refresh fails with `deadline-exceeded` before it is sent.

**Pinned by.** `test/timeout_test.dart`, "slow auth provider counts against the deadline", "stream headers deadline is the time left". Owner: Functions.

Status: designed.

### D11. Timeout bounds

**Decision.** A zero or negative timeout is an `ArgumentError`; one above 2147483647 ms is clamped to it. Any positive value, 10 seconds or less included, is accepted.

**Why.** JS turns 0 into 70 s silently (`J:service.ts:394`); a dart2js timer longer than 2^31 − 1 ms fires at once.

**What we gave up.** A caller who wants "no timeout" passes a very long one.

**Pinned by.** `test/options_test.dart`, "timeout bounds". Owner: Functions.

Status: designed.

### D12. `DateTime` is refused

**Decision.** `call` throws an `ArgumentError` for a `DateTime`, naming its path.

**Why.** JS sends `toISOString()` and never decodes it back, and Dart's `toIso8601String` differs from it. Node turns a `Date` into `{}` (measured), Python into an RFC 822 string.

**What we gave up.** The caller converts dates to strings.

**Pinned by.** `test/serializer_test.dart`, "DateTime refused". Owner: Functions.

Status: designed.

### D13. An unknown `@type` map is returned as a map

**Decision.** A response map whose `@type` is not Int64Value or UInt64Value is returned as a `Map<String, Object?>`.

**Why.** JS throws (`J:serializer.ts:96-98`), so user data that happens to hold an `@type` key can never be returned. Android and iOS return the map.

**What we gave up.** A function that returns a map shaped like a wrapper gives the client an `int`, not the map.

**Pinned by.** `test/serializer_test.dart`, "unknown @type kept". Owner: Functions.

Status: designed.

### D14. A wrapper past 2^53 on dart2js is `internal`

**Decision.** On a JavaScript-number platform an `Int64Value` or `UInt64Value` wrapper beyond ±(2^53 − 1) is an `internal` error.

**Why.** JS returns a rounded `Number` silently (`J:serializer.ts:84-95`); an id that rounds is the failure this avoids.

**What we gave up.** A function that returns 64-bit ids as wrappers cannot be read on dart2js. No measured server sends wrappers.

**Pinned by.** `test/browser/functions_browser_test.dart`, "dart2js precision". Owner: Functions.

Status: designed.

### D15. A transport failure is `unavailable`

**Decision.** A socket, TLS or DNS failure, a broken body and a redirect all give `unavailable`.

**Why.** JS reports status 0 as `internal` (`J:error.ts:108-110`), the code also used for a function's own bugs. `unavailable` is gRPC's "transient, retry with backoff".

**What we gave up.** Code that matched JS's `internal` for network failures sees another code.

**Pinned by.** `test/errors_test.dart`, "network error is unavailable". Owner: S (`_firebase_transport_dart`).

Status: designed.

### D16. The message has no ` [<status>]` suffix

**Decision.** `message` is the server's sanitized text; the HTTP status is the field `httpStatus`.

**Why.** JS appends the status to the message (`J:error.ts:198-204`), which mixes server text with transport data.

**What we gave up.** A caller that parsed the suffix reads the field instead.

**Pinned by.** `test/errors_test.dart`, "message and httpStatus". Owner: Functions.

Status: designed.

### D17. The server's message is sanitized

**Decision.** Control characters are removed and the text is cut at 1 KiB.

**Why.** JS passes any text through, control characters and escape sequences included, into logs and terminals.

**What we gave up.** A long server message is cut.

**Pinned by.** `test/errors_test.dart`, "message sanitized". Owner: S.

Status: designed.

### D18. An Auth provider error fails the call

**Decision.** An error from `app.authProvider` (other than "no user" and "API not available") fails the call with `unauthenticated`; a provider that does not answer in 10 s gives `unavailable`. The codes are Functions'; the rule is the shared one.

**Why.** JS swallows every auth error and calls anonymously (`J:context.ts:94-106`): the function then sees a signed-out user and may do the wrong thing.

**What we gave up.** A function that accepts signed-out callers is not reached while the provider is broken.

**Pinned by.** `test/tokens_test.dart`, "provider error fails the call", "slow provider is unavailable". Owner: S (the codes are Functions').

Status: designed.

### D19. The App Check placeholder is sent

**Decision.** When the provider returns a token with an error, that token (the placeholder, or an unexpired real token) is sent; an empty token, a throw or a timeout means no header. App Check never fails a call.

**Why.** JS omits the header, so the backend cannot tell that attestation failed. Android and iOS send the placeholder.

**What we gave up.** Nothing known.

**Pinned by.** `test/tokens_test.dart`, "placeholder sent". Owner: S.

Status: designed.

### D20. Tokens go only over https, the emulator and loopback

**Decision.** `http` URLs are refused when configured, unless the host is loopback or the configured emulator; tokens are attached only to those destinations. This is iOS's rule (`IOS:Functions.swift:743-785`).

**Why.** JS and Android attach tokens to every URL, in clear text for `http` (`J:service.ts:340-358`).

**What we gave up.** Unlike iOS, a LAN emulator the app configured gets its tokens, with a warning, where iOS fails with `unauthenticated`.

**Pinned by.** `test/urls_test.dart`, "http to another host refused". Owner: Functions (the URL rules; the token rule is S's).

Status: designed.

### D21. `region` and `customDomain` are separate parameters

**Decision.** A region is one DNS label; a custom domain is a validated URL. The FlutterFire adapter does the URL sniffing.

**Why.** JS and Android parse a URL out of the region string (`J:service.ts:129-138`); a typo silently becomes a host that receives the user's tokens.

**What we gave up.** The call site is a little longer; the adapter keeps FlutterFire's one-string form.

**Pinned by.** `test/urls_test.dart`, "region table". Owner: Functions.

Status: designed.

### D22. Trailing slashes of a custom domain are removed

**Decision.** `https://x/api/` calls `https://x/api/<name>`; empty path segments are dropped.

**Why.** JS strips only a lone `/`, so the call goes to `https://x/api//<name>`.

**What we gave up.** Nothing.

**Pinned by.** `test/urls_test.dart`, "domain path with trailing slash". Owner: Functions.

Status: designed.

### D23. `httpsCallableFromUrl` refuses a query, a fragment and user info

**Decision.** Such a URL is an `ArgumentError`.

**Why.** A secret in a query would appear in logs; no callable needs one.

**What we gave up.** A function URL that needs a query cannot be called.

**Pinned by.** `test/urls_test.dart`, "FromUrl refuses query". Owner: Functions.

Status: designed.

### D24. Redirects are refused

**Decision.** A 3xx answer is never a response: `unavailable`.

**Why.** `fetch`, OkHttp and URLSession follow redirects, possibly with the `Authorization` header to another host.

**What we gave up.** A function behind a redirecting URL cannot be called; configure the final URL.

**Pinned by.** `test/security/hosts_test.dart`, "3xx not followed". Owner: S.

Status: designed.

### D25. Response size caps

**Decision.** A 2xx body is read up to 32 MiB, an error body up to 1 MiB, a stream event up to 32 MiB and a stream up to 1 GiB; beyond that the call fails with `internal`.

**Why.** JS reads `response.json()` without a cap, so a hostile or broken server can exhaust memory.

**What we gave up.** A function that really returns more than 32 MiB cannot be called with this client.

**Pinned by.** `test/security/limits_test.dart`, "endless 2xx body stops at 32 MiB". Owner: Functions (the values; the caps are S's).

Status: designed.

### D26. A refresh after a bare 401

**Decision.** After an HTTP 401 with no callable error body, to a request that carried an ID token, the next call forces a token refresh, at most once a minute. The failed call is not resent. A 401 envelope or an `UNAUTHENTICATED` stream frame never triggers it. Defensive and unmeasured.

**Why.** If a front end refused an expired token with a bare 401, no SDK would refresh it (JS, Android and iOS fetch tokens without forcing a refresh and never invalidate), and every call would fail until the token expired.

**What we gave up.** Whether a production front end ever answers that way is unmeasured (kit check K12 measures it); until then the rule may never fire.

**Pinned by.** `test/tokens_test.dart`, "bare 401 forces an Auth refresh on the next call", "401 envelope does not". Owner: Functions (the call; the limit is S's).

Status: designed.

## Kept on purpose

These are not departures; the parity is deliberate:

- Integers and whole doubles are written as JS writes them.
- The server's message and details are kept for `INTERNAL` (JS and Android; iOS drops them).
- Any 2xx answer is a success (JS; iOS's fetcher also accepts 2xx; Android treats a non-200 2xx as `unknown`).
- Nothing is resent after `unauthenticated`: no official SDK does.
- HTTP 416 without an envelope is `out-of-range`: the shared status table adds that row to JS's; no callable server sends 416, so it changes nothing for Functions.

## Decisions

| # | Question | Options | Decision | Why |
|---|---|---|---|---|
| 1 | Transport | HTTPS and JSON; gRPC; the admin `CallFunction` RPC | HTTPS and JSON | No callable gRPC service exists in any SDK or proto tree; the callable library serves only `POST` with a JSON body. The admin RPC is IAM-gated, rate-limited, test-only and carries no Auth or App Check context. |
| 2 | Streaming in 0.1.0 | in 0.1.0; in 0.2.0 | in 0.1.0, as its own phase | JS, Android, iOS and FlutterFire all have it; the server's framing was measured; the SSE decoder is shared with other products; `package:http` 1.6.0 streams on the web. As its own phase it can slip without blocking unary calls. |
| 3 | Stream result shape | one stream with the result last (Android, FlutterFire); a stream and a separate future (JS) | one stream, result last | One subscription owns one request; the FlutterFire adapter maps it directly; two listeners kept in step invite JS's unsettled-future bug. |
| 4 | Integers in requests | raw (JS); wrap every `int` (Android, iOS); wrap past ±(2^53 − 1); refuse past ±(2^53 − 1) with an option | raw | Node rounds raw numbers and wrappers alike; Python keeps raw integers exact and treats wrappers as plain maps; wrapping would break exact values on Python and, on dart2js, wrap doubles such as `1.0`. The README tells users to send ids as strings to a Node function. |
| 5 | Wrappers in responses | decode to `int`, error when not representable; JS's lossy `Number`; leave the map | decode, error when not representable | No measured server emits them, so this is conformance with the Android, iOS and C++ clients and other server languages; silent rounding of an id is the failure to avoid. |
| 6 | Strict or lenient decoding | keep unknown `@type` maps or throw; ignore unknown SSE fields and keyless objects or fail; ignore or fail on a non-JSON event; fail or hang on a stream without a result | keep `@type` maps, ignore other SSE fields, comments and keyless objects, fail on a non-JSON event and on an end without a result | The server sends `data: {}` for `sendChunk(undefined)` and `: ping` heartbeats, which must not fail a stream; it never sends a non-JSON event and always ends with a result or an error. |
| 7 | `DateTime` | refuse; an ISO string (JS) | refuse | Encoding is asymmetric (never decoded back), the format differs from JS, Node turns a `Date` into `{}` and Python into an RFC 822 string. |
| 8 | Status table for answers without an envelope | JS's table (409 `aborted`); iOS's (409 `already-exists`, others `internal`) | JS's, as the shared `RpcStatus.fromHttpStatus` | The body decides the code for every callable answer; the table applies only to responses from outside the callable layer, where JS, Android and C++ agree. |
| 9 | Envelope status `OK` on a unary call | JS's flow: no error, then read data and fail with `internal` when it is missing; success with null | JS's flow | `HttpsError("ok")` gives HTTP 200 with an error body and no result; the caller gets `internal` instead of a null that looks like success. |
| 10 | Code for a transport failure | `unavailable`; `internal` (JS); `unknown` (iOS) | `unavailable` | The shared helpers' choice and gRPC's meaning ("transient, retry with backoff"); keeps `internal` for server bugs. |
| 11 | Unary timeout | a total deadline including tokens, aborting; a JS race without abort; an idle timeout (iOS) | total, including tokens, aborting | The caller's timeout is about waiting; the abort frees the connection and the server sees the disconnect. |
| 12 | Default timeout | 70 s (JS, Android, iOS); 60 s (FlutterFire) | 70 s in the client; the adapter passes FlutterFire's value | FlutterFire apps keep the behaviour they have on Android and iOS, where FlutterFire passes its 60 s down. |
| 13 | Stream timeout | idle; none (JS); the whole call (Android, 70 s) | idle | Long streams (model output) are legitimate, silence is not; the server pings every 30 s of silence by default. |
| 14 | Cancellation | an `abortTrigger` future on `call` and `stream` plus subscription cancel; a cancellation-token class; none | an `abortTrigger` future | The same name and type as `package:http`'s `AbortableRequest`; only JS and iOS can cancel a unary call today. |
| 15 | Auth and App Check failures | JS: drop the header on any error; Android and iOS: fail on an auth error and send the placeholder; one shared rule | the shared rule: for auth it equals Android and iOS, with a timeout as `unavailable`; for App Check it equals them too | A client that calls anonymously after a provider error hides the error (D18); one behaviour across the products of this repository. |
| 16 | Limited-use token unavailable | no header and proceed; fall back to the session token; fail the call | no header and proceed | A backend that consumes limited-use tokens would consume the session token; App Check enforcement is the backend's setting, so the client never fails a call for a missing App Check token. |
| 17 | Retry and refresh after a refusal | neither; invalidate after any `unauthenticated`; invalidate only after a bare transport 401 that carried an ID token; one resend with a forced refresh | invalidate after a bare 401 only, no resend | An `UNAUTHENTICATED` envelope may be the application's own `HttpsError`, which invalidating after any `unauthenticated` would treat as a refused token. Whether a bare 401 means the request never reached the function is unmeasured, and all four SDKs resend nothing. |
| 18 | Clear-text tokens and refused destinations | refuse `http` except loopback and the emulator at creation, and fail with `failed-precondition` if a refused destination still occurs; send without tokens (Storage); fail at call with `unauthenticated` (iOS) | refuse at creation | Fails at the line that is wrong; no call goes out unauthenticated by surprise; the code is the shared one, so the products agree. |
| 19 | Region and custom domain | two parameters (iOS); one string sniffed for a URL (JS, Android) | two parameters | Validation is possible; the adapter does the sniffing FlutterFire needs. |
| 20 | Emulator | the environment variable `FIREBASE_FUNCTIONS_EMULATOR_HOST` through a static getter; `FUNCTIONS_EMULATOR_HOST` (the C++ test only); none; the shared host parser or a local one; warn or refuse a non-loopback host; support Cloud Workstations or not; rewrite `FromUrl` or not | the variable `FIREBASE_FUNCTIONS_EMULATOR_HOST`; the shared parser; warn once; no Workstations; `FromUrl` not rewritten | The `FIREBASE_<PRODUCT>_EMULATOR_HOST` rule of this repository; firebase-tools exports none for Functions, and the README says so; one parser means the URL builder and the token rule cannot disagree. |
| 21 | Client-identification headers | none; send `X-Goog-Api-Client`, `X-Firebase-GMPID` and an API key | none | No Functions SDK sends them and the emulator ignores them; whether a deployed preflight allows them was not tested. |
| 22 | Success field order | `data` then `result` (JS, Android, iOS); `result` first (C++) | `data` then `result` | The server sends only `result`, so the order matters only for other servers; three SDKs agree. |
| 23 | Typed layer | `Object? data` only; `call<T>` with a cast (FlutterFire); converters (iOS) | `Object? data` only | Decoded maps are `Map<String, Object?>`; a generic cast fails at runtime for narrower types; converters are user code. |
| 24 | FCM header | never; adapter-only from `firebase_messaging` | never in 0.1.0 | There is no Messaging package; the parity gap is listed. |
| 25 | Errors for bad input | `ArgumentError` thrown synchronously; `FirebaseFunctionsException('invalid-argument')` | `ArgumentError` | Programmer errors are not server errors; the adapter maps them to `invalid-argument`. |
| 26 | A non-JSON error body | the HTTP status table; always `internal` | the HTTP status table | The status is the only information in such a body, and in both measured cases (the body parser's 400 and the router's 404) it names the cause; JS does the same. |
| 27 | Shared helpers | the shared package with `decodeGuardedBytes(maxDepth:)` and `rpcErrorBodyOf`; per-package copies; a Functions decode path built from lower-level helpers | the shared package | Two hooks in the shared helpers mean Functions carries no second decode path. |
| 28 | Adapter platforms | Linux and Windows; Linux only (Storage) | Linux and Windows | `cloud_functions` has no Windows implementation, unlike Storage. |
| 29 | `webAbortSignal` in the adapter | honoured on every platform with `TimeLimit` folded into the timeout; web only | every platform | The adapter is the only implementation on desktop and would otherwise drop a cancel the app asked for. |
| 30 | Whole doubles in requests | integers within ±(2^53 − 1), as JS writes them; `jsonEncode`'s `1.0` | integers below 1e21 | A typed server (Go) cannot unmarshal `2.0` into an `int`; JS sends `2`; one rule for every compiler. |
| 31 | Adapter without a token provider | warn once per app; refuse to send; bridge to `firebase_auth` | warn once per app | A function may allow signed-out calls, so refusing breaks valid apps; bridging adds a dependency with no Linux implementation. |
| 32 | Bare `NaN` and `Infinity` in a response | `internal` with a message naming the likely cause; a lenient decoder | `internal` | The encoder refuses non-finite numbers too, and Node answers 500 for the same value; a lenient decoder needs a hand-written parser in front of every response. |

## Alternatives rejected

- **gRPC through Cloud Run's HTTP/2.** The callable library serves only `POST` with a JSON body, so there is no gRPC method to call.
- **Reusing Firestore's REST or WebChannel transport.** It is Firestore-specific; the shared HTTP helpers are the reusable part.
- **Separate stream time limits** (`streamIdleTimeout`, `streamDeadline`), or an idle floor of `max(timeout, heartbeat floor)`. One `timeout` serves the headers wait and each silence; a second field doubles the option surface FlutterFire's single `timeout` maps onto, and a floor would hard-code the Node server's 30 s heartbeat default, which a function changes with `heartbeatSeconds`. The README tells callers to keep `timeout` above the function's heartbeat.
- **Decoding large bodies in `Isolate.run`.** It doubles peak memory for big bodies and adds a VM and web branch; a caller that expects large results calls from a background isolate. A later change may add it.
