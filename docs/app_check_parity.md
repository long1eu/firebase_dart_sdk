# App Check parity with the official SDKs

This document compares the public features of the official App Check SDKs with `firebase_app_check_dart`:

- **The Dart client**: `firebase_app_check/firebase_app_check_dart`, in development (not released). Each row says what
  the first release does.
- **The FlutterFire adapter** `firebase_app_check_dart_platform` is a later pull request and is not covered by the
  rows; see [FlutterFire](#flutterfire).

The decisions behind the differences, with the alternatives that were rejected and the test that pins each
departure, are in [app_check_decisions.md](app_check_decisions.md). How to use the package is in the
[guide](guides/app_check.md).

## Status words

| Word | Meaning |
|---|---|
| same | The Dart client behaves as the official SDKs do, or as the one the row names. |
| different | The Dart client does the same job in another way, on purpose. The note says how and the decision (`D<n>`) says why. |
| missing | The feature exists in an official SDK, and the Dart client has less of it. |
| not applicable | The feature exists for a platform or a service the Dart client does not have. |

`D<n>` numbers are those of [app_check_decisions.md](app_check_decisions.md).

## Sources

Read on 2026-11-28.

| Short name | Source | Version |
|---|---|---|
| JS | firebase-js-sdk, `packages/app-check/src` | `@firebase/app-check` 0.13.2, commit a086865 |
| Android | firebase-android-sdk, `appcheck/` (the SDK, `firebase-appcheck-debug`, `-playintegrity`, `-recaptcha`, `-interop`) | commit 2cfdd03 |
| iOS | firebase-ios-sdk, `FirebaseAppCheck/Sources`, and `google/app-check` (`AppCheckCore`, the core the iOS SDK wraps) | commits cef246f and b5dc4a3 |
| C++ | firebase-cpp-sdk, `app_check/src` | commit 09d2e7a |

The C++ SDK has an App Check implementation for desktop that has only the debug provider and no proactive refresh.
The other native SDKs ship closed or platform-bound attestation providers; the Dart package has none of them.

## Summary

| Group | Rows | same | different | missing | not applicable |
|---|---|---|---|---|---|
| Instance and configuration | 11 | 3 | 7 | 0 | 1 |
| Main calls | 14 | 5 | 8 | 0 | 1 |
| Caching and refresh | 14 | 4 | 9 | 0 | 1 |
| Providers | 9 | 1 | 5 | 1 | 2 |
| Errors | 6 | 0 | 6 | 0 | 0 |
| Other products and the wire | 5 | 3 | 1 | 1 | 0 |
| **All** | **59** | **16** | **36** | **2** | **5** |

## Instance and configuration

| Feature | JS | Android | iOS | C++ | Dart client | Status | Notes |
|---|---|---|---|---|---|---|---|
| Get an instance | `initializeAppCheck(app, options)` activates and returns the service | `FirebaseAppCheck.getInstance(app)` | `AppCheck.appCheck(app:)`, created lazily | `AppCheck::GetInstance(app)` | `FirebaseAppCheck(app, provider:, …)` | different | One object per constructor call, no global instance cache; the provider is a constructor argument. |
| Install a provider | `options.provider` (per app) | `installAppCheckProviderFactory(factory)` (per instance) | `setAppCheckProviderFactory` (process-global static, before `configure`) | `SetAppCheckProviderFactory` (static, global) | `provider:` constructor argument | different | No factory and no `activate()`; a provider is a value (D16, D17). |
| Provider type | `CustomProvider`, `ReCaptchaV3Provider`, `ReCaptchaEnterpriseProvider` | factories for Play Integrity, debug and reCAPTCHA | factories for App Attest, DeviceCheck, debug and reCAPTCHA | factories for debug and the mobile providers | `AppCheckProvider` (`abstract final`): `DebugAppCheckProvider`, `CustomAppCheckProvider` | different | A closed set in one library, so a provider added later breaks no exhaustive `switch` (D17). |
| Default provider when none is installed | none; `getToken` throws `use-before-activation` | none; the result carries "No AppCheckProvider installed." | debug on the simulator, DeviceCheck on a device | none on desktop | none: the provider is required | different | Nothing is installed for the app on its own. |
| Auto-refresh option | `isTokenAutoRefreshEnabled`, default `false` in code, tied to data collection | second argument of install, default the app's data-collection flag | property, default the data-collection flag, persisted in `UserDefaults` | `SetTokenAutoRefreshEnabled`, default `true` on desktop | `autoRefresh: true` by default, not tied to data collection | different | Kept in memory only; it is not persisted (D10). |
| Runtime toggle of auto-refresh | `setTokenAutoRefreshEnabled(appCheck, bool)` | `setTokenAutoRefreshEnabled(bool)` | the property setter | `SetTokenAutoRefreshEnabled` | `setTokenAutoRefreshEnabled(bool)` and `isTokenAutoRefreshEnabled` | same | |
| Lifecycle and delete | the service's `_delete()` removes the observers | none public | none public | `delete` of the instance | `close()`, idempotent; it also runs when the app is deleted | same | Cancels the refresher, answers pending calls with `app-check-closed`, aborts a request in flight. |
| Several apps | state keyed by `FirebaseApp` | per `FirebaseApp` | per `FIRApp` | map keyed by `App*` | one instance per app; the stored record's key carries `app.persistenceKey` | same | A second instance with `install: true` for one app is a `StateError`. |
| Required `FirebaseOptions` fields | none checked | `projectId` | API key, project id and app id for the network providers | not validated | with a debug provider: a malformed value is an `ArgumentError` at construction, a missing or empty one a `StateError` at the first exchange; a custom provider needs none | different | The message names the option, never the value. |
| A pre-minted token for server apps | `FirebaseServerApp.settings.appCheckToken`, read by Functions, Data Connect and Database | none | none | none | a `CustomAppCheckProvider` that returns the token | different | |
| Emulator | none | none | none | none | none | not applicable | There is no App Check emulator. |

## Main calls

| Feature | JS | Android | iOS | C++ | Dart client | Status | Notes |
|---|---|---|---|---|---|---|---|
| Get a token | `getToken(appCheck, forceRefresh?)`, `{token}` | `getAppCheckToken(forceRefresh)` | `token(forcingRefresh:)` | `GetAppCheckToken(force)` | `getToken({forceRefresh})`, an `AppCheckToken` | same | Throws `FirebaseAppCheckException`. |
| Token result fields | `{token}` public; `expireTimeMillis` on the custom provider | `token`, `expireTimeMillis` | `token`, `expirationDate` | `token`, `expire_time_millis` | `token` and `expireTime` (UTC) | same | `toString` prints `<redacted>`. |
| Token for other products | internal `getToken` always resolves; on failure a placeholder and an error | interop `getToken` always succeeds, the error is in `getError()` | interop result with a placeholder and an error | a future with an error code, no placeholder | the seam object (`app.appCheckProvider`): never throws; a token, a token with an error, or the placeholder with the error | same | The placeholder is `eyJlcnJvciI6IlVOS05PV05fRVJST1IifQ==`, as in JS and iOS. |
| Limited-use token | `getLimitedUseToken(appCheck)` | `getLimitedUseAppCheckToken()` | `limitedUseToken(completion:)` | `GetLimitedUseAppCheckToken()` | `getLimitedUseToken()` | same | Never cached, never shared, never announced. |
| `limited_use` on the wire | only when requested | only when true | always | always | only when true | same | JSON key `limited_use` (snake_case). |
| Custom provider and limited use | not told; served as a normal token | the default delegates to `getToken` | an optional method that falls back | logs, then calls `GetToken` | the callback is told `limitedUse` and `forceRefresh`; no fallback | different | A fallback would hand a consumed session token to later calls (D29). |
| Token listeners | `onTokenChanged(appCheck, observer)`; replays; errors go to the observer | `addAppCheckListener`; called at once with a valid cached token | a notification on a fresh exchange | a listener registry | `onTokenChanged`, a broadcast `Stream<AppCheckToken>` | different | No replay for a new listener and no error events (D25). |
| What drives refresh | a refresher exists while a listener does | refresh only with listeners | not tied to listeners | no refresh | not tied to listeners | different | The same as iOS. |
| Invalidate or clear a token | none | none | none | none | none | not applicable | A forced `getToken` replaces it. |
| Validity test | until the last millisecond | at least 5 minutes left | at least 5 minutes left | until expiry | at least `min(5 min, ttl/2)` left | different | A short custom lifetime stays usable for half its life (D9). |
| In-flight de-duplication | one exchange per app | one cached task | non-forced calls share one | none | one session exchange at a time; forced calls join it | different | A forced call that got back the token it was rejecting runs one more forced exchange (D32). |
| Forced-refresh limit | none | none | none | none | one exchange per 30 seconds for all callers together (the forced floor) | different | No official SDK has one (D13). |
| Debug helpers | the `FIREBASE_APPCHECK_DEBUG_TOKEN` global; a generated, stored token | a test helper and an instrumentation argument | `localDebugToken`, environment variables | `SetDebugToken` | `DebugAppCheckProvider`, `generateDebugToken()`, `debugProviderFromEnvironment()` (VM) | different | No implicit source, and nothing generated and stored without being asked (D7). |
| Logging of the debug token | printed to the console at initialize | logged at debug level | logged as a warning | logged as a warning | never logged, printed or stored | different | The only debug-related line is the warning L1, and only when a `logger` is passed. |

## Caching and refresh

| Feature | JS | Android | iOS | C++ | Dart client | Status | Notes |
|---|---|---|---|---|---|---|---|
| Memory cache | yes | yes | no (reads the Keychain on each call) | yes | yes | same | |
| Persistence | IndexedDB, always | SharedPreferences, always | Keychain, always | none | an optional `store:` (`KeyValueStore`); none by default | different | The debug token is never stored (D8). The stored token is not encrypted. |
| Persistence format | `{token, expireTimeMillis, issuedAtTimeMillis}` | JSON with `receivedAt` and `expiresIn` | an `NSSecureCoding` object | n/a | JSON `{v, token, issuedAt, ttl}`, at most 16 384 characters | different | Ordered by issue time; a bad record is removed, never trusted. |
| Storage failures | swallowed and logged | cleared, never thrown | mapped to an error, falls through to an exchange | n/a | logged once per operation (L6); the instance carries on in memory | same | The first load waits at most 500 ms. |
| Several tabs or processes on one record | independent | n/a | n/a | n/a | adopt a later-issued record; one exchange per period through a random lead | different | No leader election, as in JS. `store.changes` fires only for IndexedDB. |
| Expiry computation | `ttl` by regular expression, counted from after the response | `ttl` parsed, counted from after the response | counted from before the request | `strtol`, truncated | a digit-by-digit grammar, a 60 s floor, a 7-day clamp, counted from before the request | different | A malformed `ttl` is `fetch-parse-error` (D14, D30). |
| Custom provider token times | `iat` of the JWT | `iat` and `exp` of the JWT | explicit dates | the JWT `exp` | the callback's `expireTime`; no JWT is parsed | different | An `expireTime` under 60 s ahead is `provider-error`; over 7 days it is clamped (D15). |
| Proactive refresh | half life plus 5 minutes, capped at expiry minus 5 minutes | the same, at the latest 60 s before expiry | the same in effect when under 5 minutes remain | none | half life plus 5 minutes, clamped, minus a random lead; not sooner than 30 s after issue | same | 35 minutes for a one-hour token (D24). |
| Refresh retry | 30 s doubling to 16 minutes | 30 s doubling to 16 minutes | 30 s doubling to 16 minutes, plus jitter | none | none of its own: it runs again when the gate opens, not sooner than 30 s | different | One backoff, the gate's (D28). |
| Backgrounding | no logic | cancels the refresh in the background | none | none | none | not applicable | A timer that fires late only delays the proactive refresh. |
| Failed refresh while a token is valid | returns the token with an internal error | returns the token | returns the token | n/a | returns the token; in its last minutes it returns the token together with the error | same | The seam's result carries both. |
| Throttling | reCAPTCHA providers only; 403 and 404 block for 24 hours | 400 and 404 block for 24 hours, others back off exponentially to 4 hours | 400 and 404 block for 24 hours, others back off exponentially to 4 hours | none | every failure of either provider backs off to 4 hours (refused) or 5 minutes (unreachable); no day block; two gates | different | Debug exchanges are gated too (D5, D12, D36). |
| Throttle error codes | `initial-throttle`, then `throttled` | "Too many attempts." | an error code | n/a | the failing call keeps its own code; later calls get `throttled` with `retryAfter` | different | |
| Time sources | wall clock | wall clock | wall clock | wall clock | waits on a monotonic clock; a token's age on both, the larger | different | A forward jump of the clock ends no window (D21). |

## Providers

| Feature | JS | Android | iOS | C++ | Dart client | Status | Notes |
|---|---|---|---|---|---|---|---|
| Debug provider | a global mode, not a provider | `DebugAppCheckProviderFactory` | `AppCheckDebugProviderFactory` | `DebugAppCheckProviderFactory` | `DebugAppCheckProvider(debugToken:)` | different | A version 4 UUID, checked at construction; no getter returns it. |
| Debug token sources | the global, then IndexedDB, then a generated token | a secret provider, a resource, preferences, a generated token | environment variables, a stored or generated token | `SetDebugToken`, the environment, the Firebase CLI's file | the constructor, or `debugProviderFromEnvironment()` (VM) | different | The Firebase CLI's configuration file is not read (D7). |
| Debug exchange request | `POST content-firebaseappcheck.googleapis.com/v1/…:exchangeDebugToken?key=…` | `firebaseappcheck.googleapis.com`, key in the URL | `firebaseappcheck.googleapis.com`, key in a header | the same as iOS | `POST firebaseappcheck.googleapis.com/v1/projects/…/apps/…:exchangeDebugToken`, header `X-Goog-Api-Key`, body `{"debug_token"}` | different | One host on every platform, key in a header (D2, D3). |
| Custom provider | `CustomProvider({getToken})` | the provider interface | the provider protocol | an `AppCheckProvider` subclass | `CustomAppCheckProvider(getToken:)` | same | 7-second deadline; a late answer to a session request is kept. |
| reCAPTCHA v3 and Enterprise | yes (web) | yes | yes | none | none | missing | Planned for the web later, through `secure_flow` (D19). |
| Play Integrity | none | yes | none | none | none | not applicable | Not planned (D18). |
| App Attest and DeviceCheck | none | none | yes | none | none | not applicable | Not planned (D18). On mobile use FlutterFire's providers. |
| Identity headers for restricted keys | none | `X-Android-Package`, `X-Android-Cert` | `X-Ios-Bundle-Identifier` | none | none | different | A value typed by the app is a false claim to the key restriction (D31). A restricted key may refuse a desktop request. |
| Heartbeat header `X-Firebase-Client` | sent | sent | sent | not sent | not sent | different | Whether the backend needs it for the debug exchange is checked by the production kit. |

## Errors

| Feature | JS | Android | iOS | C++ | Dart client | Status | Notes |
|---|---|---|---|---|---|---|---|
| Error type | `FirebaseError`, codes `appCheck/<code>` | `FirebaseException` | a public-domain `NSError` | an error enum | `FirebaseAppCheckException`, plugin `firebase_app_check`, kebab-case codes | different | Programming errors are `ArgumentError` and `StateError`. |
| Codes | `fetch-network-error`, `fetch-parse-error`, `fetch-status-error`, `initial-throttle`, `throttled`, `storage-*`, `recaptcha-error`, `use-before-activation`, `already-initialized` | message text | a five-value enum | a five-value enum | `fetch-network-error`, `fetch-timeout`, `fetch-status-error`, `fetch-parse-error`, `throttled`, `provider-error`, `provider-timeout`, `app-check-closed` | different | `firebaseAppCheckExceptionCodes` lists them. |
| Messages | include the original error text | include the response body | not compared | include the response body | fixed texts; server text only in the `serverMessage` field, with the debug token replaced by `<redacted>` | different | A token never appears in a message, a `toString` or a log line (D20). |
| Status accepted | exactly 200 | any 2xx | not compared | not compared | exactly 200 | different | Any other status is `fetch-status-error` (D33). |
| Response size | read without a cap | not compared | not compared | not compared | 16 KiB; a redirect is never a response | different | |
| Request deadline | none | none | none | none | 7 seconds, one attempt | different | The seam must answer within 8 seconds (D23). |

## Other products and the wire

| Feature | JS | Android | iOS | C++ | Dart client | Status | Notes |
|---|---|---|---|---|---|---|---|
| How a product gets the token | the `app-check-internal` component | the interop provider | the interop methods | the internal getter | `FirebaseApp.appCheckProvider`, the seam object | different | Firestore, Auth and Database read it when they are created; Storage, Analytics, Error Reporting, Functions, AI Logic and Data Connect read it at each request. |
| Header sent by products | `X-Firebase-AppCheck` | `X-Firebase-AppCheck` | `X-Firebase-AppCheck` | `X-Firebase-AppCheck` | the same, by each product's client | same | |
| After `close()` | n/a | n/a | n/a | n/a | the seam answers an empty token, so services send no header, until a new instance is created | missing | Services created earlier keep the seam object and reach the next instance (D40). |
| Transport | REST over `fetch` | REST | REST | REST | REST over `package:http` on the VM and the web | same | No gRPC: there is no published contract. |
| Web support | yes | n/a | n/a | n/a | the main library has no `dart:io`; `io.dart` is VM only | same | Tested with dart2js and dart2wasm. |

## FlutterFire

The FlutterFire adapter, `firebase_app_check_dart_platform`, is a second pull request and is not in this release.
Until it exists, a Flutter app on Android, iOS and macOS uses the official `firebase_app_check` plugin and its native
providers, and the Dart package is for Linux and Windows apps, command-line tools, servers and the web.

## Gaps

What the Dart package does not do, in one list:

1. reCAPTCHA v3 and reCAPTCHA Enterprise on the web (later).
2. Play Integrity, App Attest and DeviceCheck (not planned).
3. A leader across tabs, and change events from a store other than IndexedDB.
4. Persistence of the gates: every process start and page load begins with open gates.
5. The FlutterFire adapter (second pull request).
6. An emulator: there is none to support.
