# Data Connect parity with the JS, Android and iOS SDKs and with FlutterFire

This document compares the public API and the behaviour of the Data Connect clients of three official SDKs and of FlutterFire's `firebase_data_connect` with `firebase_data_connect_dart` (`firebase_data_connect/firebase_data_connect_dart`), feature by feature:

- **JS**: `packages/data-connect` of firebase-js-sdk at `a086865` (package 0.7.4). It is the reference for the REST protocol and the web headers.
- **Android**: `firebase-dataconnect` of firebase-android-sdk at `2cfdd03`. It is the reference for the gRPC protocol, the unary retry and the metadata.
- **iOS**: the separate `data-connect-ios-sdk` at `f06f9e3`. Its protos are the ones the Dart package copies.
- **FlutterFire**: `firebase_data_connect` 0.4.2 at `6a80b1b`. It is the surface that `firebase dataconnect:sdk:generate` writes code for.
- **Dart**: `firebase_data_connect_dart` 0.1.0, as specified. The Dart column states what the package does or is specified to do; this document was written before the tests, so a row is checked against the code when the first pull request merges.
- The C++ SDK has no Data Connect: a search of the whole firebase-cpp-sdk tree for `dataconnect`, `data_connect` and `data connect` found nothing.

The sources were read, not run. Line numbers will drift. The reasons for each departure, the alternative that was rejected and the test that pins it are in [data_connect_decisions.md](data_connect_decisions.md); the notes below name departures by their number there.

The Status column compares the Dart behaviour with the SDK named in the cell, or with all of them when it names none:

- **same**: the behaviour of the SDK named in the cell, or of all of them
- **different**: a deliberate change, with the reason in the notes
- **missing**: not in the package yet; the notes say whether it is planned
- **won't do**: the notes give the reason

## Summary

62 feature rows in 8 groups.

| Status | Rows |
|---|---|
| same | 25 |
| different | 27 |
| missing | 6 |
| won't do | 4 |

## What the Dart package is for

The official clients are one per platform: Kotlin for Android, Swift for iOS, TypeScript for the browser and Node, and a Flutter plugin that wraps the first two. `firebase_data_connect` needs Flutter and a native plugin, so it does not run in a Dart program on macOS, Windows or Linux, in a server or in a command-line tool. `firebase_data_connect_dart` is a Data Connect client for the Dart VM (gRPC, the wire the Android and iOS SDKs use) and the web (REST, the wire the JS SDK uses), with no Flutter dependency, and a compatibility library so that generated code runs on it after a rewrite of two imports.

What it does not have yet: realtime subscriptions and the entity cache. Both depend on measurements against a production service that the emulator cannot give; see the "missing" rows and [data_connect_decisions.md](data_connect_decisions.md).

## Instance and configuration

| Feature | JS | Android | iOS | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| Get an instance | `getDataConnect(app?, connectorConfig, settings?)`, cached per config | `FirebaseDataConnect.getInstance(app, config, settings)`, cached | instance store keyed by app, config and settings, cached | `FirebaseDataConnect.instanceFor(...)`, cached per app and config | `DataConnect(app, connector:, ...)` (core); `FirebaseDataConnect.instanceFor` (compat library) | different | The core constructor has no cache: each call is a new instance with its own connection. The compat library caches per app object (by identity) and config, as generated code expects (departure from house rule 4, risk R15). |
| Connector identity | `ConnectorConfig {location, connector, service}` | `ConnectorConfig(connector, location, serviceId)` | `ConnectorConfig(serviceId, location, connector)` | `ConnectorConfig(location, connector, serviceId)`, mutable fields | core `ConnectorConfig({location, serviceId, connector})`, immutable; compat `ConnectorConfig(location, connector, serviceId)` | different | Each part is checked as a host label (`ArgumentError` naming the part). The compat constructor is positional, as generated code calls it. |
| Project id | `app.options.projectId`; missing is `invalid-argument` | `app.options.projectId` | `app.options.projectID`, `fatalError` if missing | from the app | `FirebaseApp.options.projectId`; non-empty, no `/` and no control characters, else `ArgumentError` | same |  |
| Settings object | `DataConnectSettings {cacheSettings}` | `DataConnectSettings(host, sslEnabled, cacheSettings)` | `DataConnectSettings(host, port, sslEnabled, cacheSettings)` | `CacheSettings` argument of `instanceFor` | none; constructor arguments `emulatorHost`, `emulatorSecure`, `requestTimeout`, `callerSdkType`, `httpClient`, `logger` | different | The production host is not configurable. A compat `cacheSettings` is accepted and ignored with a warning. |
| Production host | `firebasedataconnect.googleapis.com` | same | same | same | `firebasedataconnect.googleapis.com:443`, TLS | same |  |
| `app` accessor | `DataConnect.app` | `FirebaseDataConnect.app` | internal | `app` | `DataConnect.app`, `DataConnect.connector`; compat `app`, `connectorConfig` | same |  |
| Close | `terminate(dc)`; does not stop pending work | `close()` and `suspendingClose()` | none | none | `close()`: in-flight and later calls fail with `client-closed`; idempotent; runs when the app is deleted | different | The instance closes itself on `onDeleteApp`, so a deleted app never reaches a call. |
| Caller SDK type | `CallerSdkType` (six values), internal | `CallerSdkType {Base, Generated}` | none | `CallerSDKType {core, generated}` | `CallerSdkType {base, generated}`; compat `CallerSDKType {core, generated}` | same | Only the `x-goog-api-client` header changes (` dart/gen` for generated callers). |
| Logging | `setLogLevel` | `logLevel` flow | logger of the app | none | `logger` constructor argument (a `void Function(String)`) | different | Used for the clear-text emulator warning and the compat warnings; no message holds a token, key, URL query, variables or data. |

## Operations

| Feature | JS | Android | iOS | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| Create a query ref | `queryRef(dc, name, vars?)` | `query(name, vars, deserializer, serializer)` | `query(name:, variables:, resultsDataType:)` | `query(name, dataDeserializer, varsSerializer, vars)` | core `query<Data, Variables>(name, decode:, variables:, encodeVariables:)`; compat `query(...)` as FlutterFire | different | The core ref takes a `decode` over the data map instead of a string deserializer. `operationName` must be non-empty. |
| Create a mutation ref | `mutationRef(dc, name, vars?)` | `mutation(...)` | `mutation(...)` | `mutation(...)` | core `mutation<Data, Variables>(...)`; compat `mutation(...)` | different | As above. |
| Untyped calls | none (the ref functions) | none | none | none | `executeQuery(name, {variables})`, `executeMutation(...)` returning the data map | different | An addition for programs without generated code. |
| Execute a query | `executeQuery(ref, {fetchPolicy})` | `QueryRef.execute()` and `execute(fetchPolicy)` | `execute(fetchPolicy:)` | `QueryRef.execute({fetchPolicy})` | `QueryRef.execute({fetchPolicy})` | same |  |
| Execute a mutation | `executeMutation(ref)` | `MutationRef.execute()` | `MutationRef.execute()` | `MutationRef.execute()` | `MutationRef.execute()` | same | No retry on transient errors. |
| Query result | `QueryResult {data, source, fetchTime, extensions, ref}` | `QueryResult {ref, data, dataSource}` | `OperationResult(data, source)` | `QueryResult {data, source, ref}` | `QueryResult {data, source, ref}` | same | `source` is always `DataSource.server` in 0.1.0. No `fetchTime` or `extensions`. |
| Mutation result | `MutationResult {data, source, fetchTime, ref}` | `MutationResult {ref, data}` | `OperationResult` | `OperationResult` | `MutationResult {data, ref}` | same |  |
| Operation id | query key: JSON with sorted keys | `(operationName, variablesHash)` | request hash | `operationId` (name plus variables) | `operationId`: name, `\|`, canonical JSON of the encoded variables (keys sorted recursively) | same |  |
| Serialised result for SSR | `toJSON()`, `toQueryRef(serialized)` | none | none | none | none | won't do | A web-framework hydration feature; there is no cache to seed. |
| Observable query ref | none | none | `ObservableQueryRef`, Combine and `@Observable` | none | none | won't do | UI-framework glue; a Flutter adapter's concern. |
| Request coalescing | stream transport only | `LiveQuery` merges concurrent executes of one query | none | none | none: every `execute()` is a request | different | Each call is one request; `subscribe()` shares the stream of results only. |

## Values and generated-code runtime

| Feature | JS | Android | iOS | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| Variables type | any JSON object | `Struct` through kotlinx serialization | `Struct` through Codable | string from the serializer, decoded to a map | `Map<String, Object?>` of JSON values; an `int` beyond ±(2^53 − 1), a non-finite `double`, a non-`String` map key or nesting over 100 levels is an `ArgumentError` naming the path | different | Departure 2 of the decisions document: a `Struct` holds doubles, so a larger integer would be rounded. |
| Number results | JSON numbers | `Struct` doubles | `Struct` doubles | decoded JSON | `int` when integral and within ±(2^53 − 1), else `double`, on both platforms | different | Departure 3. Read a `Float` as `(v as num).toDouble()`. |
| Int64 | JSON number or string | `Long` through a double (rounded) | decimal string | `BigInt` as a decimal string through generated helpers | unchanged: the generated helper sends a string | same |  |
| Timestamp, Date, UUID, Any, Optional | plain JSON | serializers per type | Codable types | `Timestamp`, `AnyValue`, `Optional`, `nativeToJson`/`nativeFromJson` | compat library: `Timestamp`, `AnyValue`, `Optional`, `OptionalState`, `nativeFromJson`, `nativeToJson`, ported from FlutterFire (Apache 2.0, in `NOTICE`) | same | `nativeToJson<DateTime>` writes `yyyy-MM-dd` by hand instead of `package:intl`; a test pins it against `DateFormat` for chosen dates. |
| Enums | string | `EnumValue` Known/Unknown | generated | generated `EnumValue`, `Known`, `Unknown` | generated by the generator, nothing in the runtime | same |  |
| Serializers and deserializers | none | kotlinx | Codable | `Serializer<T>`, `Deserializer<T>`, `emptySerializer`, `listSerializer`, `listDeserializer`, `defaultSerializer` | compat library, same names and shapes | same |  |
| `Vector` values | none | none | none | none (the generator refuses them) | none | won't do | The generator refuses `Vector` in variables and selections. |
| Generated-code symbols | `queryRef`, `mutationRef`, `validateArgs` | `GeneratedConnector` | none | the FlutterFire export list | `package:firebase_data_connect_dart/flutterfire.dart` provides every symbol the generator's output uses, with FlutterFire 0.4.2's names and shapes | same | A text test keeps the `show` lists of the two libraries disjoint from the names the generator defines itself. |
| Running generated code without Flutter | n/a | n/a | n/a | needs Flutter | `dart run firebase_data_connect_dart:rewrite_generated <dir>` (idempotent, `--check`, refuses other `package:flutter/` imports) | different | An addition. The generator has no runtime-package option, so its imports are rewritten after each generate. A Flutter override package named `firebase_data_connect` is the second pull request. |

## Fetch policy and cache

| Feature | JS | Android | iOS | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| Fetch policy enum | `QueryFetchPolicy {PREFER_CACHE, CACHE_ONLY, SERVER_ONLY}` | `FetchPolicy` | `QueryFetchPolicy` | `QueryFetchPolicy {preferCache, cacheOnly, serverOnly}` | `QueryFetchPolicy {preferCache, cacheOnly, serverOnly}` (core and compat) | same | Default `preferCache`. |
| `preferCache` with no cache configured | answers from an implicit, never-expiring map of the last result (`source` CACHE) | goes to the server | goes to the server | goes to the server | goes to the server; `DataSource.server` | different | Matches Android, iOS and FlutterFire. JS's implicit map is not done (decision D15). |
| `cacheOnly` on a miss | `other`: no cache entry | internal `CachedDataNotFoundException` | null data | sent to the server | `DataConnectException('cache-miss')`, no network call (compat: `DataConnectErrorCode.cacheMiss`) | different | Departure 4. |
| Cache settings | `CacheSettings` with a memory provider | persistent SQLite cache, `cacheSettings` | persistent SQLite cache | `CacheSettings(storage, maxAge)`, `CacheStorage {persistent, memory}` | compat only: the value types exist, a non-null value logs one warning per instance and is ignored | missing | Planned: needs entity metadata, which the emulator does not send (decision D6, probe P12). |
| Normalised entity cache | `EntityNode`, `ResultTree` | entities and results in SQLite | entities in SQLite | persistent entity cache | none | missing | As above. |
| Server `maxAge` | overwrites the global `maxAgeSeconds` | ignored | ignored | ignored | none | missing | Part of the cache. |

## Errors

| Feature | JS | Android | iOS | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| Error class | `DataConnectError`, `DataConnectOperationError` | `DataConnectException`, `DataConnectOperationException` | `DataConnectError`, `DataConnectOperationError` | `DataConnectError`, `DataConnectOperationError<T>` (extend `firebase_core`'s `FirebaseException`) | `DataConnectException` and `DataConnectOperationException<Data>` (extend `firebase_app_dart`'s `FirebaseException`, plugin `data_connect`); compat `DataConnectError` family | different | Compat errors keep FlutterFire's form (`plugin: 'Data Connect'`, `code: enum.toString()`) and hold the core exception as `cause`. `on FirebaseException` with the `firebase_core` class does not catch them. |
| Codes | `other`, `unauthorized`, `partial-error`, `invalid-argument`, ... | exception classes only | enums | `DataConnectErrorCode {unavailable, unauthorized, cacheMiss, codecFailed, other}` | gRPC status names in kebab case (`unauthenticated`, `not-found`, ...), plus `partial-error`, `invalid-response`, `codec-failed`, `cache-miss`, `client-closed`; compat maps them to FlutterFire's enum | different | A status that the transport reports reaches the caller as itself, on both platforms. |
| Partial errors | any 2xx body with `errors` throws `partial-error` with `{errors, data}` | `DataConnectOperationException` with the response | `DataConnectOperationError` | `DataConnectOperationError` with `response` | `DataConnectOperationException<Data>` with `errors`, `rawData`, decoded `data`; code `partial-error`, for queries and mutations alike | same (JS) | A mutation that reports errors may have written. |
| GraphQL error shape | `message`, `path` | message, locations, path, extensions | same | `DataConnectOperationFailureResponseErrorInfo`, path segments | `GraphqlError {message, path, locations, extensions, code}`; compat has `DataConnectFieldPathSegment`, `DataConnectListIndexPathSegment` | same | Extensions: the six known keys without defaults, the same on both platforms; unknown keys appear on the web only (departure 12). |
| HTTP and transport failure | `>= 400` is `other`, `401` is `unauthorized` | gRPC exception propagates | gRPC error | `other`/`unauthorized` | `WireFailure` mapped to the status; REST codes come from the body (`error.status`, then the gateway `code`) before the HTTP status | different | Departure 5. No exception of `package:http` or `package:grpc` is ever a `cause`. |
| Decode failure | none (raw JSON) | `DataConnectOperationException` | `decodingFailed` | `codecFailed` | `codec-failed` with the thrown object as `cause`; the response data is not in the message | different | If the response also had GraphQL errors the code stays `partial-error`. |
| Retry on `unauthenticated` | once, if this call's token is new, forcing Auth | once, forcing Auth and App Check, always | none | none | once, only if an ID token was sent, forcing Auth at most once per 60 s, never App Check | different | Departure 1. Mutations are retried too (probe P14). |
| Deadline | none | none | none | none | 60 s per attempt, `requestTimeout` | different | Departure 9. |

## Emulator

| Feature | JS | Android | iOS | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| Connect to the emulator | `connectDataConnectEmulator(dc, host, port, ssl)`; throws `already-initialized` if called late | `useEmulator(host, port)` | `useEmulator(host:, port:)` | `useDataConnectEmulator(host, port, {automaticHostMapping, isSecure})` | core: constructor arguments `emulatorHost` (`host:port`) and `emulatorSecure`; compat: `useDataConnectEmulator` | different | The core instance is immutable, so there is no late call. `emulatorHost` is parsed by the shared `EmulatorHost.parse` (host, port 1 to 65535, no scheme, no Google production host); the error names the rule and never repeats the input. |
| Environment variable | `FIREBASE_DATA_CONNECT_EMULATOR_HOST` on Node | none | none | none | `DataConnect.emulatorHostFromEnvironment` reads it (null on the web); the constructor never reads it by itself | same (JS) | The Android host mapping (`10.0.2.2`) is kept in the compat library only. |
| Default port | none | 9399 | 9399 | 9399 | none; the repository's test scripts use 9499 | different | The caller names the port. |
| Plaintext and TLS | `http` unless `sslEnabled` | plaintext unless `sslEnabled` | same | same | plaintext unless `emulatorSecure`; a non-loopback host without TLS gets one clear-text warning | same | The emulator serves h2c only. |
| Cloud Workstations from a browser | `credentials: 'include'` | none | none | none | none | missing | `BrowserClient.withCredentials` is not wired in 0.1.0. |
| `EmulatorService` (issues stream) | none | `GetEmulatorInfo`, `StreamEmulatorIssues` | none | none | none | won't do | Android only logs it. |

## Tokens and headers

| Feature | JS | Android | iOS | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| Auth token header | `X-Firebase-Auth-Token` | `x-firebase-auth-token` | `x-firebase-auth-token` | same | `x-firebase-auth-token` (raw ID token, no `Bearer`) | same | Providers are read per call; each token is sent to one request only. |
| App Check token header | `X-Firebase-AppCheck` | `x-firebase-appcheck` | `x-firebase-appcheck` | same | same | same | A missing or failing App Check token never fails a call. |
| App id header | `x-firebase-gmpid` if set | `x-firebase-gmpid` if not blank | only when data collection is enabled | from the app | `x-firebase-gmpid` always; a missing app id is a `StateError` at the first call | different | A value that is not a header value is an `ArgumentError` naming the option. |
| API key | `?key=` query parameter (REST) | none | none | none (gRPC) | `?key=` on REST only; never on gRPC | same (JS) | Departure 11. Required on the web: a missing key is a `StateError` at the first call that needs it. |
| Routing headers | none (REST) | `x-goog-request-params`, `x-firebase-sqlconnect-affinity` | same | same | both on gRPC; none on REST | same | Whether production requires them is probe P6. |
| Client identification | `X-Goog-Api-Client: gl-js/ fire/<ver>`, `X-Client-Version: web/<ver>` | `gl-kotlin/... fire/<ver> grpc/`, `android/<ver>` | `ios/<ver>` | `gl-dart/<package version> fire/<package version> gl-<os>` (the package version stands where the Dart version belongs), plus an `x-firebase-client` heartbeat | `gl-dart/<runtime> fire/<ver>`, `x-client-version: dart/<ver>` | different | Departure 8. Probe P8. |
| Token failure | `auth/token-not-initialized` is a null token | exception | exception | exception | an Auth provider failure fails the call: `unauthenticated`, `unavailable` (timeout) or `failed-precondition` (token too long); never retried | different |  |

## Subscriptions and transports

| Feature | JS | Android | iOS | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| `subscribe()` | `subscribe(ref, observer)` returns an unsubscribe function | `QueryRef.subscribe()` returns a `QuerySubscription` | `ObservableQueryRef` | `QueryRef.subscribe()` returns a `Stream` | `QueryRef.subscribe()` returns a broadcast `Stream`; the first listener fetches once, and later results of `execute()` on the same instance are emitted to every listener | different | 0.1.0 emits only results this instance fetched, not changes made elsewhere. The first call logs that server push is not supported. |
| Realtime updates | WebSocket `Connect` stream | gRPC bidi `Connect` stream | gRPC bidi `Connect` stream | WebSocket | none | missing | Planned after probes P1 and P2: the emulator never pushes, so no local test could show it works (decision D2). Appendix A of the specification keeps the notes. |
| VM transport | n/a | gRPC | gRPC | gRPC (plugin) | gRPC through `_firebase_transport_grpc_dart`, one HTTP/2 connection per instance; keepalive ping 30 s, 20 s ping timeout, flow-control window 256 KiB | same (Android, iOS) | No REST on the VM, no gRPC on the web. |
| Web transport | REST (`fetch`) | n/a | n/a | REST/WebSocket (web plugin) | REST through `package:http`'s `BrowserClient`; no `package:grpc`, `package:protobuf` or `package:fixnum` in the web build | same (JS) | No redirects followed. A browser needs the preflight to allow the headers the client sends. |
| Response limits | none (`response.json()` is uncapped) | none | none | none | 16 MiB on success, 16 KiB for REST error bodies, data depth 100 | different | Departure 7. On the VM the check runs on the announced length before allocation where the HTTP/2 library lets the wrapper see it. |
| Server-provided `extensions` and entity ids | parsed | parsed | parsed (mutations ignored) | parsed | ignored (the emulator sends `null`) | missing | Needs the cache. |
