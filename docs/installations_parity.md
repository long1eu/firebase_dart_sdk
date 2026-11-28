# Installations parity with the JS, Android, iOS and C++ SDKs

This document compares the public API and the behaviour of the Firebase Installations clients of four official SDKs with `firebase_installations_dart` (`firebase_installations/firebase_installations_dart`), feature by feature:

- **JS**: `packages/installations` of firebase-js-sdk at `a086865`. It is the reference for the protocol.
- **Android**: `firebase-installations` of firebase-android-sdk at `2cfdd03`.
- **iOS**: `FirebaseInstallations` of firebase-ios-sdk at `cef246f`. It is the reference for token recovery and the client backoff.
- **C++**: `installations` of firebase-cpp-sdk at `09d2e7a`. Off Android and iOS it compiles a stub that returns `"FakeId"` and `"FakeToken"` (`FC:stub/installations_stub.cc:35-58`).
- **Dart**: `firebase_installations_dart` 0.1.0 and the `FirebaseInstallations` it describes. The Dart column states the behaviour the package is built to have; it was written from the design, before the package was integrated. Audit it against the code before trusting a row. To read a row quickly, start with the Dart and Notes columns.

The four SDKs were read as source clones on 2026-11-27, from GitHub only; their code was read, not run. Line numbers will drift. Remote Config, the first user of this package, has its own document: [remote_config_parity.md](remote_config_parity.md). The reasons for the departures from upstream are in [remote_config_decisions.md](remote_config_decisions.md); the notes below name them as D13 and D14.

The Status column compares the Dart behaviour with the SDK named in the cell, or with all of them when it names none:

- **same**: the behaviour of the SDK named in the cell, or of all four
- **different**: a deliberate change, with the reason in the notes
- **missing**: not in 0.1.0; the notes say whether it is planned
- **won't do**: the notes give the reason

Path shorthand:

- `FJ:` is JS `packages/installations/src`.
- `FA:` is Android `firebase-installations/src/main/java/com/google/firebase/installations`.
- `FI:` is iOS `FirebaseInstallations/Source/Library`.
- `FC:` is C++ `installations/src`.

## Summary

38 feature rows in 4 groups.

| Status | Rows |
|---|---|
| same | 15 |
| different | 21 |
| missing | 0 |
| won't do | 2 |

## Public API

| Feature | JS | Android | iOS | C++ | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| Get an instance | `getInstallations(app)` FJ:api/get-installations.ts:28 | `getInstance(app)` FA:FirebaseInstallations.java:205-209 | `installationsWithApp:` FI:FIRInstallations.m:190-194 | `GetInstance`; a stub on desktop | `FirebaseInstallations(app, store:, headers:, httpClient:, logger:)` | different | No instance cache. The constructor reads and sends nothing. |
| `getId` | returns the local FID and registers in the background FJ:api/get-id.ts:30-44 | waits for local state only | returns the FID; the token refreshes in the background | returns `"FakeId"` | `Future<String> getId()`: returns the stored FID, creating one when there is none, and starts the registration in the background | same (JS) | A registration failure goes to the logger and surfaces at `getToken`. |
| `getToken(forceRefresh)` | a string FJ:api/get-token.ts:31-42 | `InstallationTokenResult` with an expiry | a token result with an expiration date | a string | `Future<String> getToken({forceRefresh})`, and `getIdAndToken({forceRefresh})` returning a matching `(id, token)` pair | different | The pair is read from one record after the token is obtained, so a recovery inside the call replaces both. Remote Config needs it. |
| `delete` | local only if never registered; throws if a registration is pending FJ:api/delete-installations.ts:31-57 | `DELETE`, then a new FID next time | `DELETE` ignoring 404, then a change notification | stub | `Future<void> delete()`: waits for a registration in flight, sends `DELETE` when registered (200, 401 and 404 count as done), removes the record | same (Android) | |
| Id-change events | `onIdChange` on any stored FID change, with a `BroadcastChannel` FJ:helpers/fid-changed.ts:24-110 | `registerFidListener`, for a registered FID that changed FA:FirebaseInstallations.java:434-457 | a notification on create, server change and delete FI:InstallationsIDController/FIRInstallationsIDController.m:498-503 | none | `Stream<String> onIdChange`: emits the new FID when a different one is stored (a new id, a different id from the server, a recovery); tokens never travel in a `BroadcastChannel` message | different | Every SDK uses its own rule. Remote Config reacts by marking its cache stale and reconnecting its stream. |
| Close | none | none | none | destructor | `close()`: idempotent, ends `onIdChange`, closes the HTTP client if the instance created it; later async calls fail with `installations-closed`; runs by itself when the app is deleted | different | Upstream SDKs have no `close`; a Dart client that owns an HTTP client and a stream must be able to release them. |
| Interface for other products | `installations-internal` | an interop API | an instance provider | an internal class | the public `FirebaseInstallations` instance, passed to the product | different | The alternatives (a provider on `FirebaseApp`, a static cache) are in the decisions document. |

## FID, configuration and state

| Feature | JS | Android | iOS | C++ | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| FID format | 22 characters, `/^[cdef][\w-]{21}$/` FJ:helpers/generate-fid.ts:20 | 22 characters | 22 characters | none (Remote Config fakes 8 bytes) | the same pattern; a FID from the server or the store that fails it is rejected | same (JS) | |
| FID generation | 17 secure random bytes, the high nibble `0111` FJ:helpers/generate-fid.ts:27-55 | built from a UUID | built from a UUID | none | `randomBytes(17)` from `Random.secure()`, byte 0 masked as in JS, base64url, first 22 characters | same (JS) | |
| The server returns another FID | overwrite | overwrite | overwrite FI:InstallationsIDController/FIRInstallationsIDController.m:283-288 | none | stored, and emitted on `onIdChange` | same | |
| Required options | `projectId`, `apiKey`, `appId`; `missing-app-config-values` at creation | checked on every call | an exception at init | none | `invalid-app-config` at construction when one is missing, when the API key does not match `^A[A-Za-z0-9_-]{38}$`, when the app id has no `:`, or when the project id does not match `^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$` | different | Stricter than JS: the format checks are those Android and iOS make (FA:Utils.java:33-34). The project id check keeps a hostile value out of the URL. |
| Registration state | `NOT_STARTED`, `IN_PROGRESS`, `COMPLETED` | five persisted ordinals | `Unknown`, `Unregistered`, `Registered` | none | `unregistered`, `registering`, `registered`, persisted; `registering` carries a time stamp | different | The stamp is a marker that matters when tabs share an IndexedDB store (below). |
| Persistence | IndexedDB `firebase-installations-database` FJ:helpers/idb-manager.ts:24-53 | a JSON file in the no-backup directory, temp file and rename FA:local/PersistedInstallation.java:85-193 | keychain and a UserDefaults flag | none | a `KeyValueStore` the app creates and passes in (required): `MemoryKeyValueStore`, `FileKeyValueStore` (VM, a private directory, atomic rename) or `IndexedDbKeyValueStore` (web); record key `installations/<app.persistenceKey>` | different | There is no default store: a memory default would create a new installation at every start without saying so. The web database is this package's own, not JS's. No encryption at rest: the record holds the refresh token. |
| Corrupt record | — | — | — | — | a record that fails validation counts as absent and a new FID is created; a record over 64 KiB (counted in characters, not bytes) is absent; a token must be 1 to 4096 printable ASCII characters, times must lie between 0 and the year 9999, `tokenExpiresIn` must be at least 1000 ms, and the owner fields must match `^[A-Za-z0-9._-]{1,64}$`; the file store refuses a write over 16 MiB and reads a non-regular file as absent (A34) | different | A damaged store should not stop the app; a new FID is the safe recovery. |
| Store write failure | — | — | — | — | the instance keeps the new record in memory, logs once, and retries the write before every later operation as a guarded merge inside `update` (memory applies only if nothing is stored, or the stored record has the same FID and is not further along, and never after another writer's delete); the FID stays the same for the life of the process; a store configuration failure (an owned directory, the directory mode) is thrown as `storage-error` | different | A failed write must not change the FID between calls; a wrong configuration is the app's to fix, so it fails. |
| Concurrency | an IDB transaction, 100 ms polling, 10 s pending timeout | `synchronized` and a `FileLock` | per-operation promise caches FI:InstallationsIDController/FIRInstallationsSingleOperationPromiseCache.m:46-67 | none | one in-flight future per operation, shared by concurrent callers; one process owns a VM store directory (an OS lock); IndexedDB markers: a start time and the owner's nonce, fresh when at most 15 s old, re-stamped by the owner only, before every HTTP attempt of at most 10 s; the directory check of a VM store runs before any await | different | D13: JS's marker and request both allow 10 s, so another tab repeats a slow request. |
| `MemoryKeyValueStore` | — | — | — | — | logs one warning (no values) when an installation is first registered in it, and only if a `logger` was passed | different | A memory store loses the installation at exit; the warning says so, without values. |

## REST API

| Feature | JS | Android | iOS | C++ | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| Base | `https://firebaseinstallations.googleapis.com/v1` FJ:util/constants.ts:9-10 | the same | the same | none | the same; an origin can be changed only through a `@visibleForTesting` constructor argument, and only to https or loopback | same | No emulator exists in any SDK. |
| Create | `POST projects/{p}/installations`; `{fid, authVersion: "FIS_v2", appId, sdkVersion: "w:..."}` | the same, `a:` | the same, a trailing slash, `i:` | none | `POST /projects/{projectId}/installations`, no trailing slash; `sdkVersion` is `d:<packageVersion>` | same (JS) | A `d:` prefix is accepted by the server. |
| Generate a token | `POST .../{fid}/authTokens:generate`; `{installation: {sdkVersion, appId}}` | `{installation: {sdkVersion}}` | the same as Android | none | `{installation: {sdkVersion}}`, without `appId` | same (Android) | The server accepts both. |
| Delete | `DELETE .../{fid}` | 200, 401, 404 are success FA:remote/FirebaseInstallationServiceClient.java:326-342 | a body `{}`; 404 ignored | none | `DELETE .../{fid}`; 200, 401 and 404 count as done | same (Android) | |
| Headers | `x-goog-api-key`; `Authorization: FIS_v2 <refreshToken>` on token and delete | adds gzip, package and certificate headers | adds the bundle id header | none | `Content-Type` (not on `DELETE`), `Accept`, `x-goog-api-key`, `Authorization: FIS_v2 <refreshToken>` on token and delete, and the `headers` argument; no `Content-Encoding`, no `Accept-Encoding` | different | `headers` accepts only `X-Android-Package`, `X-Android-Cert` and `X-Ios-Bundle-Identifier`, for an API key restricted to those apps. All three pass the CORS preflight, so they are sent on every platform. |
| Heartbeat `x-firebase-client` | when a heartbeat service exists | every request | every request | no-op | none | won't do | Omitted when empty by all three clients; this SDK has no heartbeat service. |
| Timeout | the browser default | 10 s FA:remote/FirebaseInstallationServiceClient.java:100 | the URLSession default | none | 10 s per attempt, 60 s for a whole public call (`unavailable`) | same (Android) | |
| `expiresIn` | `"604800s"` FJ:functions/common.ts:104-107 | `[0-9]+s` required | required | none | `^[0-9]{1,9}s$` with a value from 1 s to 400 days; a response that fails the checks is `invalid-response` and nothing is stored | different | Stricter than all three. |
| Response size and redirects | no limit | no limit | no limit | none | a success body is capped at 64 KiB, an error body at 16 KiB, redirects are refused (a 3xx is `invalid-response` and feeds the recoverable backoff); the response is read as text, then `{"error": {code, status, message}}` or `{"error": "<string>"}` | different | D14. A non-JSON error body keeps only the status. |

## Tokens, errors and retry

| Feature | JS | Android | iOS | C++ | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| Expiry buffer | 1 h, and a refresh if the clock went back FJ:helpers/refresh-auth-token.ts:187-193 | 1 h | 1 h | none | a token is valid when `tokenCreatedAt <= now` and it has at least 1 h left | same (JS) | |
| Refresh scheduling | lazy | lazy | lazy | none | lazy, no timers | same | A VM process can exit. |
| 401 or 404 on a token request | remove the entry, throw | regenerate, throw | regenerate, retry once FI:...IDController.m:365-388 | none | remove the record, create a new FID, register it, send `generate` once more in the same call; a second 401 or 404 throws `installation-not-found` | same (iOS) | A 401 or 404 on create is not this recovery (next row). |
| 409 on create | remove the entry FJ:helpers/get-installation-entry.ts:144-147 | a generic error | a generic error | none | remove the record and feed the recoverable backoff (the n-th failure waits `min(2^n + random(0, 1), 1800)` s); the call restarts with a new FID, and its create is sent despite that window; a second 409 in the same call throws `invalid-response` (status 409); a call made inside the window that a 409 started throws `too-many-requests`, not the 409's `bad-config`; a `getToken` caller waiting on the registration restarts it | different | As-built A4, A31: JS has no backoff, and without a limit a server that keeps answering 409 would loop. |
| Create statuses | one error for every status | — | — | none | per endpoint: 400, 401, 403 and 404 on create are `bad-config`, and only 400 and 403 block create for 24 h; 401 and 404 on create are a recoverable failure (the wrong project or key; no installation exists yet); any other 4xx (408, 410, 418 and so on) is `invalid-response` with the status kept, and it feeds the backoff | different | As-built A4, A31. A 401 or 404 on generate keeps the recovery above. An unexpected 4xx is not `bad-config`, so a proxy's 408 does not make Remote Config stop its realtime stream. |
| Retry on a server error | any 5xx, once, at once | two attempts for 5xx and IO | status 500 only, once, after 1 s | none | once after 1 s on 5xx or a transport error | same (iOS) | |
| Client backoff | none | `RequestLimiter`, with a seconds-and-milliseconds mix-up (inferred) FA:remote/RequestLimiter.java:28-100 | `min(2^n + jitter, 30 min)`; 24 h for 400 and 403 FI:InstallationsIDController/FIRInstallationsBackoffController.m:19-130 | none | the iOS model, in memory per instance: after 400 or 403 no create or generate for 24 h (calls rethrow `bad-config` with `retryAfter`); after 429, a 5xx, a 3xx, another 4xx, or a 409 or a 401 or 404 on create, the n-th consecutive failure waits `min(2^n + random(0, 1), 1800)` seconds; success, and 401 or 404 on generate, reset it; a transport error and an unusable 2xx body change nothing | same (iOS) | As-built A31. Behind a captive portal each 3xx adds to the backoff, up to 30 minutes, and nothing clears it when the network returns (L1). |
| Error type | `FirebaseError`, 6 codes; `request-failed` carries the server's code and message FJ:util/errors.ts:21-40 | `BAD_CONFIG`, `UNAVAILABLE`, `TOO_MANY_REQUESTS` | 4 codes | 4 codes, mostly unused | `FirebaseInstallationsException extends FirebaseException`, plugin `firebase_installations`: `invalid-app-config`, `bad-config`, `installation-not-found`, `too-many-requests`, `unavailable`, `network-error`, `invalid-response`, `storage-error`, `installations-closed`; fields `httpStatus`, `serverStatus`, `serverMessage`, `retryAfter`, `cause`; `firebaseInstallationsExceptionCodes` lists them | different | JS maps most of these to `request-failed`; separate codes let Remote Config classify a failure for realtime. |
| Offline | `app-offline` from `navigator.onLine` | a network error | `ServerUnreachable` | none | `network-error` for a transport failure or the 10 s request deadline | different | No `navigator.onLine` check. |
| Messages | — | — | logs FIS bodies FI:InstallationsAPI/FIRInstallationsAPIService.m:296-311 | — | no log line, exception message or `toString` (code, message and HTTP status only) holds a refresh token, an auth token, the API key, a request URL with a query or a body; records and tokens print `<redacted>` | different | D14. |
| Logging | a global log level | the system log | the Firebase logger | none | an `InstallationsLogger` constructor argument with `InstallationsLogLevel`; silent when absent | different | There is no global log level in Dart; a constructor argument keeps loggers per instance. |
| IID migration | none | from the GMS file | from the keychain | none | none | won't do | No instance id ever existed on desktop or the web. |
