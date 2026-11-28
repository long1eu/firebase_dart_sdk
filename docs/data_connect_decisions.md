# Data Connect decisions

The decisions behind `firebase_data_connect_dart` (`firebase_data_connect/firebase_data_connect_dart`): where the
package differs from the official SDKs and why, and which alternatives were considered and rejected.
[remote_config_decisions.md](remote_config_decisions.md), [database_decisions.md](database_decisions.md) and
[storage_decisions.md](storage_decisions.md) are the models of this document; [contributing_a_product.md](contributing_a_product.md)
has the rules every product client follows. The comparison with the official SDKs, feature by feature, is in
[data_connect_parity.md](data_connect_parity.md); the user-facing description is the
[guide](guides/data_connect.md).

The document has four parts:

1. departures from the upstream SDKs (numbers 1 to 10 and 12 of the specification, section 6.1);
2. departures from the repository's shared rules (number 11, section 6.2);
3. the alternatives considered, D1 to D17 (section 7);
4. the facts still to be measured against a real service, P1 to P15 (section 10).

Which SDK each area follows:

- the REST protocol and the web headers: the JS SDK;
- the gRPC protocol, the routing headers and the protos: the iOS SDK (its protos are a superset of Android's);
- unary retry: none of them (see departure 1);
- the generated-code surface: FlutterFire's `firebase_data_connect` 0.4.2, which is what the generator targets.

Every entry ends with a status line:

- **designed**: the behaviour is specified and the code is not merged yet;
- **built**: the code does this, and a test named under "Pinned by" pins it.

At the time of writing every entry is **designed**: the tests are written after the closing review of the first pull
request, and this document is updated then.

Path shorthand for upstream code:

| Short | Meaning |
|---|---|
| `JS/` | `firebase-js-sdk/packages/data-connect/src/` at a086865 |
| `AND/` | `firebase-android-sdk/firebase-dataconnect/src/main/kotlin/com/google/firebase/dataconnect/` at 2cfdd03 |
| `IOS/` | `data-connect-ios-sdk/Sources/` at f06f9e3 |
| `FF/` | `flutterfire/packages/firebase_data_connect/firebase_data_connect/` at 6a80b1b (0.4.2) |

"Pinned by" names a test file under `firebase_data_connect/firebase_data_connect_dart/test/`.

## Departures from upstream

### 1. Retry after `unauthenticated`

**What differs.** The client retries a unary call after `unauthenticated` only if it sent an ID token. It then
invalidates the Auth token (forced at most once per 60 seconds), never the App Check token in 0.1.0, and sends the
call once more if a different token came back.

**The failure it fixes.** Android forces both tokens and retries unconditionally, spending an App Check attestation
per failure; its own TODO says so (`AND/core/DataConnectGrpcClient.kt:109-136`, comment at `:128-129`). JS retries
only when this call's token differs from the previous call's (`JS/network/transport.ts:315-332`), so a cached token
revoked on the server fails every call until it expires. iOS never retries.

**Consequences.** A signed-out user calling an `@auth(level: USER)` operation costs one request and no attestation.
A second refusal within 60 seconds of a forced refresh is not retried: the token source does not force again, the
tokens come back unchanged and the call ends `unauthenticated`. Mutations follow the same rule on the assumption that
the server refuses before it runs the operation (Android does the same; the assumption is probe P14).

Pinned by: `retry_test.dart`, including "second refusal within 60 s: no retry". Status: designed.

### 2. Integers beyond ±(2^53 − 1) in variables

**What differs.** An `int` outside ±(2^53 − 1) in variables throws `ArgumentError` from `execute()`, naming the path
and not the value.

**The failure it fixes.** A `google.protobuf.Struct` holds numbers as doubles, so the value would be rounded on its
way to the server. GraphQL `Int64` is not affected: generated helpers send it as a decimal string.

Pinned by: `values_test.dart` "2^53". Status: designed.

### 3. Integral doubles become `int`

**What differs.** In results, a number is an `int` when it is integral and within ±(2^53 − 1), on gRPC and on REST.

**The failure it fixes.** gRPC would give `3.0` where JSON gives `3`, so one app would decode differently on the VM
and on the web. The rule makes both platforms agree; a `Float` is read as `(v as num).toDouble()`. Whether
production writes `3` or `3.0` is probe P5; the rule handles both.

Pinned by: `values_test.dart` "numbers". Status: designed.

### 4. `cacheOnly` with no cache

**What differs.** With no cache, `QueryFetchPolicy.cacheOnly` throws `DataConnectException('cache-miss')` without a
network call. `preferCache` and `serverOnly` go to the server and report `DataSource.server`.

**The failure it fixes.** FlutterFire sends `cacheOnly` to the server (`FF/lib/src/core/ref.dart:281-296`); iOS
returns null data, which typed code cannot tell from an empty result. JS answers a later `preferCache` from an
implicit last-result map that never expires (`JS/core/query/QueryManager.ts:77-91,262-271`); that is not done here.

Pinned by: `fetch_policy_test.dart`. Status: designed.

### 5. REST error codes from the body first

**What differs.** On REST the status of a failed call is taken from the body (`error.status`, then the
grpc-gateway form's integer `code`) before the HTTP status.

**The failure it fixes.** JS maps every status but 401 to `other` (`JS/network/rest/fetch.ts:130-136`), so a caller
cannot tell `not-found` from `permission-denied`.

Pinned by: `rest_errors_test.dart`. Status: designed.

### 6. Compat: refs made before `useDataConnectEmulator` use the emulator

**What differs.** In the FlutterFire-compatible library, `useDataConnectEmulator` closes the core client and the next
operation creates one for the emulator; references made earlier use it.

**The failure it fixes.** FlutterFire references keep the old transport (`FF/lib/src/firebase_data_connect.dart:184-199`),
so a ref made at import time of generated code keeps talking to production after the emulator is selected.

Pinned by: `compat/compat_emulator_test.dart`. Status: designed.

### 7. Security rules

**What differs.** Response caps (16 MiB on success, 16 KiB for REST error bodies), refused redirects, a data depth
limit of 100, redaction (no token, key, URL query, variables or result data in a message, `toString` or log line) and
the shared token rules (providers read per call, tokens bound to one origin and single-use).

**The failure it fixes.** JS reads `response.json()` with no cap (`JS/network/rest/fetch.ts:118`) and logs the whole
error body (`:131`). `package:http` prints the request URI in a `ClientException`, and the REST URL carries the API
key, so no transport exception ever becomes a `cause`: for a transport failure `cause` is null and the message names
only the failure.

Pinned by: `security/*`. Status: designed.

### 8. Client identification headers

**What differs.** `x-client-version: dart/<package version>` and `x-goog-api-client` with `gl-dart/<runtime>`.

**The failure it fixes.** FlutterFire writes its package version where the Dart version belongs
(`FF/lib/src/common/common_library.dart:30-31`), and the headers say `flutter/` on a program that has no Flutter.
Production's acceptance of `dart/<version>` is probe P8.

Pinned by: `metadata_test.dart`. Status: designed.

### 9. A deadline for every attempt

**What differs.** Each attempt has a deadline of 60 seconds by default (`requestTimeout`), token wait included; a
call retried after `unauthenticated` can take up to twice that.

**The failure it fixes.** No SDK sets a unary deadline. A REST request has no keepalive, so without a deadline its
wait has no bound. A timed-out mutation may have run; it is never retried.

Pinned by: `deadline_test.dart`. Status: designed.

### 10. Compat: subscribe streams across an emulator switch

**What differs.** Subscribe streams made before `useDataConnectEmulator` end with `client-closed`.

**The failure it fixes.** FlutterFire's keep the old transport and stay attached to production.

Pinned by: `compat/compat_emulator_test.dart`. Status: designed.

### 12. Error extensions differ between platforms

**What differs.** An unknown key of a GraphQL error's `extensions` appears on the web (REST keeps every key of the
JSON object) and not on the VM (gRPC drops fields newer than the copied protos).

**Why it is listed.** It is not a fix: it is the cost of two decoders (D3 below). It is listed so the asymmetry is
known. For the six known keys (`file`, `code`, `debugDetails`, `resource`, `warningLevel`, `workarounds`) both
platforms drop the default values and agree.

Pinned by: `extensions_test.dart` "unknown key, web only". Status: designed.

## Departure from the shared rules

### 11. The API key in the REST URL

**What differs.** On REST the API key goes in the `key` query parameter, as JS does. It never goes on gRPC and never
into a message or log. The shared rule is "no secret in a URL" (SHARED 5.10, its listed departure 1).

**Why.** JS sends it this way (`JS/util/url.ts:67-75`), and a header that JS does not send may fail the browser's CORS
preflight. The key is dropped or moved to `X-Goog-Api-Key` if stage A of the production kit shows that the service
accepts that (probe P4).

Pinned by: `metadata_test.dart` "key only in the REST query". Status: designed.

## Alternatives considered

Each row gives the reason against every candidate not chosen.

| # | Question | Candidates | Chosen | Why |
|---|---|---|---|---|
| D1 | Transports in 0.1.0 | (a) gRPC on the VM, REST on the web; (b) REST everywhere, gRPC with the realtime stream later; (c) both on the VM | (a) | The owner's line ("prefer gRPC where possible, Firestore already uses it") rejects (b). A second VM transport doubles the VM test matrix and puts departure 11 on the VM (c). (a) costs the protoc pipeline, the gRPC package, the Struct codec and its recursion limit, departures 3 and 12, the extensions normaliser and two decoder test tables. (c) returns as an option only if the gRPC round trip against production (P9) or the routing headers (P6) fail |
| D2 | Realtime in 0.1.0 | (a) yes; (b) later, behind production probes | (b) | The emulator never pushes after the first result, so no local test can show it works, and the production WebSocket path is unmeasured (P1) |
| D3 | Message classes on the web | (a) generated classes via proto3 JSON on both platforms; (b) generated classes on the VM, a JSON decoder on the web | (b) | (a) puts `package:protobuf` into every web build, round-trips data through `Struct` doubles, and drops unknown error-extension keys on the web too, where (b) keeps them |
| D4 | gRPC channel | (a) the shared `_firebase_transport_grpc_dart`; (b) copy Firestore's three files into this package | (a) | Against (b): a third copy of the keepalive code, outside the package the shared design owns |
| D5 | Service stubs | (a) generate them; (b) messages only | (b) | Calls go through `GrpcCaller` with an `RpcMethod`, so stubs would be dead generated code |
| D6 | Entity cache in 0.1.0 | (a) none; (b) memory; (c) persistent | (a) | The emulator sends no entity metadata, so neither (b) nor (c) could be tested locally; (c) also needs a store per platform. Queries are correct without a cache |
| D7 | Unary retry rule | (a) Android's (force both, always retry); (b) JS's (force Auth, retry if this call's token is new); (c) no retry (iOS); (d) departure 1 | (d) | Against (a): an attestation per failure; against (b): a token revoked server-side is never refreshed; against (c): one expired token fails the call |
| D8 | Package name | (a) `firebase_data_connect_dart`; (b) `firebase_dataconnect_dart` | (a) | The repository names packages `<FlutterFire name>_dart`, and FlutterFire's is `firebase_data_connect` |
| D9 | `x-client-version` | (a) `dart/<ver>`; (b) `flutter/<ver>` (FlutterFire); (c) `web/<ver>` on the web (JS) | (a) | (b) is wrong for programs without Flutter; (c) is wrong on the VM and different per platform. Acceptance is probe P8 |
| D10 | Where the compat surface lives | (a) a library of the core package (`flutterfire.dart`); (b) a separate pure-Dart package | (a) | One more package to publish and pin, with no user of the core package that must avoid the compat code |
| D11 | Generated code in Flutter apps | (a) an override package named `firebase_data_connect`; (b) the rewrite command only | (a), with (b) documented | (b) alone makes the app create and wire the `firebase_app_dart` app by hand and rerun the command after each generate; (a) maps the FlutterFire app with its providers and needs no edit. The generator has no runtime-package option. (a) is the second pull request |
| D12 | API key on REST | (a) `?key=` as JS; (b) `X-Goog-Api-Key` header; (c) none | (a) | (b): a header JS does not send may fail the browser preflight; (c): it is unmeasured whether production accepts it. Revisit after probe P4 |
| D13 | Per-attempt deadline | (a) none (every SDK); (b) 60 s, configurable | (b) | Departure 9 |
| D14 | Proto source | (a) the Android copy; (b) the iOS copy | (b) | The Android copy is a subset of the iOS one, without the error-extension fields the emulator sends |
| D15 | Fetch policies with no cache | (a) JS (implicit last-result map); (b) Android (server; `cacheOnly` throws); (c) iOS (server; `cacheOnly` returns null) | (b) | Two SDKs go to the server for `preferCache`; a throw with a public code is the only `cacheOnly` result typed code can handle |
| D16 | App mapping in the override package | (a) Storage's `dartAppFor`; (b) Database's; (c) a shared library | (b) | (a) cannot add a token provider to an app another package created; (c) cannot live in the pure-Dart shared packages and would change five adapters (a follow-up idea) |
| D17 | gRPC buffering before the size cap | (a) accept it; (b) check the announced length in the shared connection wrapper | (b), falling back to (a) | Against (a) when (b) is possible: a peer could make the client allocate up to 4 GiB. If `package:http2` does not let the wrapper see a stream's incoming frames, the cap is applied after buffering and the limit is documented |

## Facts still to be measured

Only the lead runs these, against a real project, with the owner's word (the
[production kit](../tool/verify_production_data_connect/README.md)). None of them gates the first release except
as noted.

| # | Fact | Stage | Blocks |
|---|---|---|---|
| P1 | The production WebSocket path: JS's dot form or the slash form | A | realtime |
| P2 | Push after a mutation; the meaning of `resume`, `data_etag`, `cancelled` | B | realtime |
| P3 | The production REST error body form | A | nothing (both forms are accepted) |
| P4 | REST without `?key=`; gRPC with no key | A | D12 |
| P5 | Whether production writes integral numbers without a fraction | B | nothing (departure 3 handles both) |
| P6 | Whether `x-goog-request-params` and `x-firebase-sqlconnect-affinity` are required on gRPC | A | nothing (both are sent) |
| P8 | `x-client-version: dart/<ver>` accepted | A | D9 |
| P9 | A Dart `package:grpc` round trip against production | B | nothing |
| P10 | `Uri(pathSegments:)` keeps `:` in `{connector}:executeQuery` on the VM, dart2js and dart2wasm | unit test | the REST URL |
| P11 | The REST mapping is a supported interface | owner | the web support claim |
| P12 | Entity metadata with and without `clientCache` | B | the cache release |
| P14 | `UNAUTHENTICATED` on a mutation is returned before the operation runs | B | departure 1 for mutations |
| P15 | The form of a refusal caused by App Check, so that the App Check token can be invalidated when the backend names it | B | departure 1 |
