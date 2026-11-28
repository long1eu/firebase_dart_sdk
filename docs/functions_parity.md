# Functions parity with the JS, Android, iOS and C++ SDKs and FlutterFire

This document compares the public API and the behaviour of the callable-function clients of the official SDKs and of FlutterFire's `cloud_functions` with `cloud_functions_dart` (`cloud_functions/cloud_functions_dart`), feature by feature:

- **JS**: `packages/functions` of firebase-js-sdk at `a086865`. It is the reference for the protocol, the error mapping and the URL rules.
- **Android**: `firebase-functions` of firebase-android-sdk at `2cfdd03`. It is the reference for the stream result shape and for sending the App Check placeholder.
- **iOS**: `FirebaseFunctions` of firebase-ios-sdk at `cef246f`. It is the reference for the rule that tokens do not travel over clear text and for the separate custom-domain parameter.
- **C++**: `functions` of firebase-cpp-sdk at `09d2e7a`. Its desktop code speaks the same HTTPS protocol itself; it has no streaming, no custom domain and no timeout.
- **FlutterFire**: `cloud_functions` 7.1.0 and `cloud_functions_platform_interface` 6.2.0 at bbdc38e.
- **Dart**: `cloud_functions_dart` 0.1.0 and the `FirebaseFunctions` it describes. The Dart column states the behaviour the package is specified to have; it is not run against a deployed project yet (see below).

The five SDKs were read as source clones on 2026-11-28; their code was read, not run. The behaviour of a Node and a Python callable server was measured on the emulator the same day (firebase-tools 15.18.0, firebase-functions 7.4.0 and 0.6.0). Line numbers will drift. The reasons for each departure from upstream, the alternative that was rejected and the test that pins it are in [functions_decisions.md](functions_decisions.md); the notes below name the departures as D1 to D26 and the decisions as "decision n".

The Status column compares the Dart behaviour with the SDK named in the cell, or with all of them when it names none:

- **same**: the behaviour of the SDK named in the cell, or of all of them
- **different**: a deliberate change, with the reason in the notes
- **missing**: not in the package; the notes say whether it is planned
- **won't do**: the notes give the reason

Path shorthand:

- `J:` is JS `packages/functions/src`.
- `AND:` is Android `firebase-functions/src/main/java/com/google/firebase/functions`.
- `IOS:` is iOS `FirebaseFunctions/Sources`.
- `CPP:` is C++ `functions/src`.

## Summary

74 feature rows in 7 groups.

| Status | Rows |
|---|---|
| same | 35 |
| different | 34 |
| missing | 2 |
| won't do | 3 |

## What the Dart package is for

FlutterFire's `cloud_functions` has implementations for Android, iOS, macOS and the web only: on Windows and Linux a call throws `MissingPluginException`. The C++ SDK's desktop path has no streaming, no custom domain and no timeout. The JS SDK runs in a browser or Node, and the Admin SDKs have no callable client. `cloud_functions_dart` is a callable-function client for the Dart VM (macOS, Windows, Linux) and the web (dart2js, dart2wasm), with the user's ID token and an App Check token attached, streaming calls, and one way of reporting failures.

## Gaps

What the other SDKs have that this package does not, in 0.1.0:

- **The FCM registration token header** (`Firebase-Instance-ID-Token`): there is no Messaging package; a function sees `request.instanceIdToken` as null.
- **The Cloud Workstations emulator**: JS only, for one hosted IDE.
- **A typed (Codable) layer**: iOS only.
- **`withTimeout`**: Android's copy of a callable with another timeout; options are immutable here.
- **The FlutterFire adapter** `cloud_functions_dart_platform`: planned for a second pull request.
- **A run against a deployed project**: the production kit exists and has not been run (needs the Blaze plan and the owner's approval).

## Instance, URLs and the emulator

| Feature | JS | Android | iOS | C++ | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| Get an instance | `getFunctions(app?, regionOrCustomDomain)` J:api.ts:46-63, cached per app and region | `getInstance(app?, regionOrCustomDomain?)` AND:FirebaseFunctions.kt:405-439 | `functions(app:region:)`, `functions(app:customDomain:)` IOS:Functions.swift:84-144 | `Functions::GetInstance(app, region?)` functions.h:65-82 | `instanceFor({app, region})` | `FirebaseFunctions(app, region:, customDomain:, emulatorHost:, timeout:, httpClient:, onWarning:)` | different | No instance cache and no global state: two instances are two clients. Settings are fixed at construction. |
| Default region | `us-central1` J:service.ts:35 | `us-central1` | `us-central1` | `us-central1` | `us-central1` | `us-central1` | same | |
| Region and custom domain | one string; a URL is sniffed out of it J:service.ts:129-138 | the same AND:FirebaseFunctions.kt:85-99 | two parameters | none | `region` may be a URL | two parameters, validated; a URL as `region` is refused with "use customDomain" | different (iOS) | A typo silently becoming a host is the failure it fixes (D21). The adapter does the URL sniffing FlutterFire needs. |
| Custom domain path | strips only a lone `/`, so `https://x/api/` gives `https://x/api//name` | the same | iOS: `<domain>/<name>` | none | as the platform | trailing slashes and empty segments dropped; `https://x/api/` gives `https://x/api/name` | different | D22. |
| Project id as a host | not checked | not checked | not checked | not checked | | must form one DNS label with the region; otherwise `ArgumentError` naming `customDomain` and `httpsCallableFromUrl` | different | A domain-scoped id such as `example.com:p` cannot form the host. |
| Emulator | `connectFunctionsEmulator(f, host, port)` J:api.ts:74 | `useEmulator(host, port)` | `useEmulator(withHost:port:)` | `UseFunctionsEmulator(origin)` | `useFunctionsEmulator(host, port)` | `emulatorHost: 'host:port'` constructor argument, parsed once; a scheme, path, missing port or Google host is refused | different | It wins over a custom domain, as upstream. A non-loopback host works and warns once. |
| Emulator from the environment | `__FIREBASE_DEFAULTS__` J:api.ts:58-61 | none | none | `FUNCTIONS_EMULATOR_HOST` in the integration test only | none | `FirebaseFunctions.emulatorHostFromEnvironment` reads `FIREBASE_FUNCTIONS_EMULATOR_HOST`; null on the web | different | firebase-tools exports no variable for Functions; the name follows the other emulators of this repository (decision 20). |
| Cloud Workstations emulator | https origin, `credentials: 'include'`, a `/backends` ping J:service.ts:174-187 | none | none | none | none | none | won't do | A convenience for one hosted IDE; `emulatorHost` is plain `http`. |
| By name | `httpsCallable(f, name, options?)` J:api.ts:91 | `getHttpsCallable(name[, options])` | `httpsCallable(_ name[, options])` | `GetHttpsCallable(name[, options])` | `httpsCallable(name, {options})` | `httpsCallable(name, {options})` | same | The name is validated (1-63 characters, no `/ ? # % :`, whitespace, `.` or `..`). |
| By URL | `httpsCallableFromURL(f, url, options?)` J:api.ts:112 | `getHttpsCallableFromUrl(URL)` | `httpsCallable(_ url: URL)` | `GetHttpsCallableFromURL(url)` | `httpsCallableFromUrl` | `httpsCallableFromUrl(Uri, {options})` | same | Used as given; the emulator setting does not rewrite it. Query, fragment and user info are refused (D23). |
| Instance properties | `app`, `region`, `customDomain` J:public-types.ts:104-121 | none | `emulatorOrigin` | none | `app`, `region` | `app`, `region`, `customDomain`, `emulatorHost`, `timeout` | same | |
| Closing an instance | deleting the app cancels unary calls J:service.ts:122-127 | none | none | the destructor | none | `close()`: aborts calls and streams, waits for them, closes the client it created; also runs when the app is deleted | different | JS cancels only unary calls (D8). |

## Calls and options

| Feature | JS | Android | iOS | C++ | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| Call | `callable(data?)` returns `{data}` | `call([data])` returns a `Task` | `call(_ data) async throws` | `Call([Variant])` returns a `Future` | `call<T>([parameters])` | `Future<HttpsCallableResult> call([Object? data, Future<void>? abortTrigger])` | same | |
| Result type | `any` | `Any?` | `Any` | `Variant` | generic `T` | `Object?`; maps are `Map<String, Object?>` | different | A generic cast such as `Map<String, int>` fails at runtime; users cast what they read (decision 23). |
| Typed (Codable) layer | none | none | `httpsCallable(_:requestAs:responseAs:)` | none | none | none | won't do | Users convert maps themselves. |
| Default timeout | 70 s J:service.ts:394 | 70 s (the doc says 60) AND:HttpsCallOptions.kt:70-71 | 70 s IOS:HTTPSCallable.swift:46 | none | 60 s | 70 s; the adapter passes FlutterFire's 60 s | same (JS) | |
| What the timeout covers | the call after the tokens; only rejects, the fetch keeps running J:service.ts:73-90 | OkHttp `callTimeout`, the whole call | the URLRequest timeout | none | passed down | the whole call, token fetch included; aborts the request | different | D9, D10. |
| Timeout values | 0 becomes 70 s silently | any | any | | | zero or negative: `ArgumentError`; above 2147483647 ms clamped | different | D11. |
| Cancel a call | `options.signal` (an `AbortSignal`) J:service.ts:253-261 | none for unary | Task cancellation | none | `webAbortSignal` (web only) | `abortTrigger`, a future, on `call` and `stream`; subscription cancel for streams | different | The same name and type as `package:http`'s `AbortableRequest`. Only JS and iOS can cancel a unary call today. |
| Limited-use App Check tokens | `limitedUseAppCheckTokens` J:public-types.ts:74 | `setLimitedUseAppCheckTokens` | `requireLimitedUseAppCheckTokens` | `limited_use_app_check_token` | `limitedUseAppCheckToken` | `HttpsCallableOptions.limitedUseAppCheckTokens` | same | Needs a provider that implements `LimitedUseAppCheckTokenProvider`; otherwise no App Check header is sent. |
| Per-callable timeout | `options.timeout` | `setTimeout`, `withTimeout` | `timeoutInterval` | none | `HttpsCallableOptions.timeout` | `HttpsCallableOptions.timeout` | same | |
| `withTimeout` (a copy with another timeout) | none | `withTimeout(...)` shares options with the original | none | none | none | none | won't do | Options are immutable; make another callable. |
| Automatic retry | none | none | none | none | none | none | same | A callable may not be idempotent. |

## Tokens and the request

| Feature | JS | Android | iOS | C++ | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| Method, body and content type | `POST`, `{"data": ...}`, `application/json` J:service.ts:279,387 | the same | the same | the same | | the same, four headers and no others | same | |
| ID token | `Authorization: Bearer` J:service.ts:348-350 | `Bearer` AND:FirebaseFunctions.kt:234-236 | `Bearer` IOS:Functions.swift:655-658 | `Bearer` CPP:functions_desktop.cc:315-319 | | `Authorization: Bearer <token>` | same | Not Storage's `Firebase <token>`, which the callable server refuses. |
| Auth provider errors | swallowed: the call goes out signed out J:context.ts:94-106 | the call fails | the call fails | | | the call fails with `unauthenticated`; a timeout is `unavailable` | different (JS) | No user and "API not available" still mean no header. D18. |
| ID token length | none | none | none | none | | over 8192 characters fails the call with `failed-precondition` | different | A header value must stay a plain token. |
| App Check token | `X-Firebase-AppCheck` J:service.ts:354-356 | the same | the same | the same | | the same | same | |
| App Check error | header omitted J:context.ts:138-143 | placeholder sent AND:FirebaseContextProvider.kt:125-131 | placeholder sent IOS:FunctionsContext.swift:92 | | | the placeholder is sent; empty, a throw or a timeout means no header; App Check never fails a call | same (Android, iOS) | D19. |
| FCM token header | `Firebase-Instance-ID-Token` with notification permission J:context.ts:108-126 | when the manifest does not register FCM with the installation id | sent | never | | never | missing | There is no Messaging package. `request.instanceIdToken` is null on the server. |
| `X-Firebase-GMPID`, `x-goog-api-key`, `x-goog-api-client` | not sent | not sent | not sent | not sent | | not sent | same | The emulator ignores them; whether a deployed preflight allows them was not tested. |
| Tokens over clear text | attached to any URL | attached to any URL | refused for a non-loopback host, fails `unauthenticated` IOS:Functions.swift:743-785 | | `allowInsecureTokenAttachment` (Apple debug only) | tokens go only to `https`, the configured emulator and loopback; an `http` URL elsewhere is refused when configured | different | D20. A LAN emulator the app configured gets its tokens, with a warning. `allowInsecureTokenAttachment` is ignored by the adapter. |
| Redirects | followed | followed | followed | | | never followed; `unavailable` | different | D24. |
| Refresh after a bare 401 | none | none | none | | | the next call forces an Auth refresh, at most once a minute; the call is not resent | different | D26. Defensive and unmeasured. |
| Client identification headers | none | none | none | none | | none | same | |

## Values

| Feature | JS | Android | iOS | C++ | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| 64-bit integers in a request | raw numbers J:serializer.ts:48-52 | every `Long` wrapped in `Int64Value` AND:Serializer.kt:39-50 | every `Int` wrapped IOS:FunctionsSerializer.swift:94-106 | every int64 wrapped | | raw numbers; an `int` beyond ±(2^53 − 1) as its exact digits | same (JS) | Node rounds raw numbers and wrappers alike; Python keeps raw integers exact and does not decode wrappers (decision 4). |
| Whole doubles | `JSON.stringify`: `1.0` is `1` | `1.0` | | | | written as integers below 1e21 on every compiler | same (JS) | A typed server cannot read `2.0` into an integer field (decision 30). |
| Wrappers in a response | decoded to a lossy `Number` J:serializer.ts:84-95 | decoded to `Long` | decoded | `Int64Value` only | | decoded to `int`; a value the platform cannot hold exactly is `internal` | different | No measured server sends them (D14). |
| Unknown `@type` | throws J:serializer.ts:96-98 | returned as a map | returned as a map | | | returned as a map | same (Android, iOS) | D13. |
| `NaN` and infinities in a request | throws | rejected | | | | `ArgumentError` | same | Checked before `is int`, because an infinity passes it on dart2js. |
| `NaN` and infinities in a response | | | | | | `internal`, with a message that names the likely cause | different | A Python function can send bare `NaN`. |
| `DateTime` | `toISOString()`, never decoded back | throws | throws | | | `ArgumentError` | different | D12. |
| Map keys that are not strings | | rejected AND:Serializer.kt:69 | | | | `ArgumentError` with the path | same (Android) | |
| Nesting depth | none | none | none | none | | 512 levels, in requests and responses | different | Also stops cycles. |
| Response size | `response.json()` without a cap | none | none | none | | 32 MiB; error body 1 MiB | different | D25. |

## Responses and errors

| Feature | JS | Android | iOS | C++ | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| Success statuses | any 2xx J:error.ts:103-106 | 200 only | 200 only | 200 only | | any 2xx | same (JS) | |
| Result field | `data`, then `result` J:service.ts:445-450 | the same | the same | `result` first | | `data`, then `result`; neither is `internal` | same (JS) | The server sends only `result`. |
| Status `OK` in an error body | no error, then a missing result is `internal` | | | | | no error, then a missing result is `internal` | same (JS) | `HttpsError("ok")` gives HTTP 200 with such a body. |
| The body decides the code | yes J:error.ts:141-205 | yes | yes | yes | | yes; 409 serves both `already-exists` and `aborted` | same | |
| HTTP status table without a body | 409 `aborted`, 2xx ok, others `unknown` J:error.ts:102-136 | the same | 409 `already-exists`, others `internal` | | | JS's table plus 416 `out-of-range` | same (JS) | Decision 8. |
| Unknown status name | `internal` J:error.ts:160-169 | `internal` | `internal` | | | `internal`, "Unknown backend error status." | same | |
| Non-JSON error body | status table | `internal` | status only | | | status table: a 400 HTML page is `invalid-argument`, a 404 page `not-found` | same (JS) | Decision 26. |
| Error type | `FunctionsError`, code `functions/<kebab>` | `FirebaseFunctionsException` with a `Code` enum | `NSError` | `Error` enum | `FirebaseFunctionsException` | `FirebaseFunctionsException` (a `FirebaseException`), kebab-case `code` | same (FlutterFire) | Plugin `firebase_functions`. |
| Message | `<message> [<http status>]` J:error.ts:198-204 | server text | server text | | | the sanitized server text; `httpStatus` is a field | different | D16, D17. |
| Details | decoded | decoded | decoded, dropped for `INTERNAL` IOS:FunctionsError.swift:196-203 | | | decoded and kept for every code | same (JS, Android) | |
| Transport failure | status 0 becomes `internal` J:error.ts:108-110 | `internal` or `deadline-exceeded` | `unknown` | | | `unavailable`, with `cause` null | different | D15. |
| Server text in `toString` | | | | | | never details or cause | different | |

## Streaming

| Feature | JS | Android | iOS | C++ | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| Stream API | `stream()` returns `{stream, data}`; the result only on `data` J:public-types.ts:53-56 | `Publisher<StreamResponse{Message,Result}>` | `AsyncThrowingStream<StreamResponse>` | none | `Stream<StreamResponse{Chunk,Result}>` | `Stream<CallableStreamEvent>`: `CallableMessage`s, then `CallableResult` last | same (Android, FlutterFire) | Decision 3. One subscription owns one request. |
| Request | `Accept: text/event-stream` J:service.ts:501-502 | the same | the same | | | the exact value; the server streams only for it | same | |
| Framing | `data: <json>` lines, errors ignored J:service.ts:631-660 | `data:` and `result:` prefixes, multi-line joined | strict, a stray line is `dataLoss` | | | as the server writes it (`data: <one line>`); comments, other fields and keyless objects ignored | different | Decision 6. |
| HTTP status of a stream | never checked: a non-2xx stream never settles J:service.ts:504-603 | non-2xx is `internal` | must be 200 | | | a non-2xx answer is handled like a unary response | different | D1. |
| JSON answer to a stream request | the result never settles | | | | | one `CallableResult` | different | D3. |
| Error frame with status `OK` | rejects with null J:service.ts:647-651 | | | | | `internal` | different | D5. |
| Non-JSON event | ignored | | `dataLoss` | | | `internal`, the stream closes | different | D4. |
| End without a result | never settles J:service.ts:682-689 | | | | | `internal` | different | D2. |
| Timeout on a stream | none | `callTimeout`: the whole stream, 70 s | idle (URLRequest) | none | | idle: the wait for headers, then each silence; pings restart it | different | D6. Keep `timeout` above `heartbeatSeconds`. |
| Reading after the result | keeps reading | | | | | stops and aborts | different | D7. |
| `close()` and streams | cancels unary calls only | | | | | aborts streams too | different | D8. |
| Backpressure | a `ReadableStream` | Reactive Streams | `AsyncThrowingStream` | | | pausing the subscription pauses reading the response | same | |

## Platforms and adapters

| Feature | JS | Android | iOS | C++ | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| Browser | yes | | | | web | dart2js and dart2wasm, one code path over `package:http` | same | A CORS rejection is `unavailable`, as it is indistinguishable from a network error to a page. |
| Windows and Linux | no | | | desktop REST, no streaming, no custom domain, no timeout | no implementation (`MissingPluginException`) | the Dart VM | different | The reason this package exists. |
| Servers and command-line tools | Node (the Admin SDK has no callable client) | | | | | the Dart VM | same | |
| FlutterFire adapter | | | | | `cloud_functions_platform_interface` | `cloud_functions_dart_platform`, planned for the second pull request | missing | Not part of 0.1.0. |
| Emulator fixture and production kit | | | | | | `tool/functions_emulator`, `tool/verify_production_functions` | same | The kit has not run against a real project. |
