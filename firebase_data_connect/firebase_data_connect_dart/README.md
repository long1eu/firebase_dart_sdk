# firebase_data_connect_dart

Unofficial pure-Dart client of Firebase Data Connect: run the queries and mutations of a connector, with typed
references, GraphQL errors that carry the partial data, Auth and App Check tokens, and the emulator, on the Dart
VM (macOS, Windows, Linux, servers, command-line tools) over gRPC and on the web (dart2js and dart2wasm) over
REST. A compatibility library lets the Dart code that `firebase dataconnect:sdk:generate` writes run on the VM
without Flutter.

Status: 0.1.0, first release, not published yet. The client was built against the emulator and the official SDKs'
source; it has not run against a production service yet. The production verification kit
(`tool/verify_production_data_connect/`) checks a real project, and only after the owner's approval.

Not in 0.1.0: server-pushed (realtime) subscriptions and the normalised entity cache. See [Limits](#limits).

## Install

Only `firebase_app_dart` may already be on pub.dev; the two internal transport packages are not. Depend on
all of them from this repository:

```yaml
dependencies:
  firebase_app_dart: ^0.2.3
  firebase_data_connect_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_data_connect/firebase_data_connect_dart
dependency_overrides:
  _firebase_transport_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_core/_firebase_transport_dart
  _firebase_transport_grpc_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_core/_firebase_transport_grpc_dart
  firebase_app_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_core/firebase_app_dart
```

The `ref: main` lines assume the packages have landed on `main` with this change (until then, use the branch that
carries them). The overrides are needed because pub refuses one package from two sources; once the packages are
published, `dart pub add firebase_data_connect_dart` does the same and the overrides go away.

Dart 3.8 or later. No Flutter dependency.

## Use

A `DataConnect` is one connector of one `FirebaseApp`. The three parts of the connector are the ones in
`dataconnect.yaml` (`location`, `serviceId`) and `connector.yaml` (`connectorId`).

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_data_connect_dart/firebase_data_connect_dart.dart';

Future<void> readAndWrite() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'AIzaSyDummyDummyDummyDummyDummyDummyDum', // placeholder: use your own key
      appId: '1:123456789012:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );
  final DataConnect dataConnect = DataConnect(
    app,
    connector: const ConnectorConfig(
      location: 'us-central1',
      serviceId: 'my-service',
      connector: 'my-connector',
    ),
  );

  final QueryRef<List<String>, void> listItems = dataConnect.query<List<String>, void>(
    'ListItems',
    decode: (Map<String, Object?> data) => <String>[
      for (final Object? item in data['items']! as List<Object?>)
        (item! as Map<String, Object?>)['name']! as String,
    ],
  );
  final QueryResult<List<String>, void> result = await listItems.execute();
  print(result.data);

  await dataConnect.executeMutation('CreateItem', variables: <String, Object?>{'name': 'first'});
  await dataConnect.close();
}
```

`executeQuery` and `executeMutation` take an operation name and a variables map and return the raw `data` map.
`query` and `mutation` return typed references: `decode` turns the data map into your type, and
`encodeVariables` turns your variables object into the map the server expects. `app` needs the `projectId`; the
app id is sent on every call and the API key on the web.

### Errors

Every failure is a `DataConnectException` with a kebab-case `code`: the gRPC status names (`unauthenticated`,
`not-found`, `unavailable`, ...), and `partial-error`, `invalid-response`, `codec-failed`, `cache-miss` and
`client-closed`. GraphQL errors in a successful response arrive as a `DataConnectOperationException` with code
`partial-error`, the `errors`, and the data the server returned:

```dart
import 'package:firebase_data_connect_dart/firebase_data_connect_dart.dart';

Future<void> handleErrors(DataConnect dataConnect) async {
  try {
    await dataConnect.executeQuery('ListItems');
  } on DataConnectOperationException<Object?> catch (e) {
    print('partial result: ${e.rawData}, first error: ${e.errors.first.message}');
  } on DataConnectException catch (e) {
    print('${e.code}: ${e.message}');
  }
}
```

A mutation that reports GraphQL errors may still have written: read `rawData` before you retry it. No message,
`toString` or log line holds a token, the API key, a URL with a query, variables or result data. Server text
reaches you only as `serverMessage`.

## The emulator

`firebase emulators:start --only dataconnect` serves REST and gRPC (plaintext) on one port, 9399 by default.
Pass `emulatorHost` to the constructor, for example `127.0.0.1:9399`; the constructor never reads the environment
by itself, so a program that wants the usual variable says so:

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_data_connect_dart/firebase_data_connect_dart.dart';

DataConnect emulatorClient(FirebaseApp app) => DataConnect(
  app,
  connector: const ConnectorConfig(
    location: 'us-central1',
    serviceId: 'test-service',
    connector: 'test-connector',
  ),
  emulatorHost: DataConnect.emulatorHostFromEnvironment ?? '127.0.0.1:9399',
);
```

`DataConnect.emulatorHostFromEnvironment` reads `FIREBASE_DATA_CONNECT_EMULATOR_HOST` (null on the web). The
emulator does not check token signatures: an ID token whose payload has `sub` or `user_id` is accepted, a token
without it is `unauthenticated`, and no token is accepted for an operation with `@auth(level: PUBLIC)`. A test can
therefore use an app with a test token provider. `emulatorSecure: true` uses TLS; a non-loopback host without it
sends tokens in clear text and the client logs one warning.

This repository ships a ready service for tests: `tool/start_data_connect_emulator.sh [port]` (default 9499) starts
the emulator on the fixture in `tool/data_connect_emulator/dataconnect/` and prints the variable to export. The
emulator binary downloads once with `firebase setup:emulators:dataconnect`.

## Transports

| Platform | Transport | Notes |
|---|---|---|
| Dart VM | gRPC (`ConnectorService/ExecuteQuery`, `/ExecuteMutation`) | one HTTP/2 connection per `DataConnect`, through `_firebase_transport_grpc_dart` |
| Web | REST (`POST .../connectors/{connector}:executeQuery`) | `package:http`'s `BrowserClient`; the API key goes in the `key` query parameter, as in the JS SDK |

The two are not interchangeable: the web build does not include `package:grpc`, `package:protobuf` or
`package:fixnum` (`tool/check_web_imports.dart` checks that in CI), and the VM does not use REST.

## Generated code

`firebase dataconnect:sdk:generate` writes Dart code for FlutterFire's `firebase_data_connect`. The generator has
no option for another runtime package, so the code imports `package:firebase_data_connect/firebase_data_connect.dart`
and `package:flutter/foundation.dart`. Two ways to run it with this package:

1. **Without Flutter** (VM programs, servers, command-line tools): run the rewrite command on the generated
   directory after every `firebase dataconnect:sdk:generate`:

       dart run firebase_data_connect_dart:rewrite_generated lib/generated

   It replaces the first import with `package:firebase_data_connect_dart/flutterfire.dart` and the second with
   `package:meta/meta.dart`, and refuses (exit 1, nothing written) when a file imports another `package:flutter/`
   library. It is idempotent; `--check` writes nothing and exits 1 when a file would change. The app depends on
   `firebase_data_connect_dart` and `meta`.
2. **In a Flutter app**: an override package named `firebase_data_connect` (a later release of this repository)
   lets the generated code compile unchanged.

`package:firebase_data_connect_dart/flutterfire.dart` provides the symbols the generator uses with FlutterFire
0.4.2's names (`FirebaseDataConnect`, `ConnectorConfig`, `CallerSDKType`, `QueryRef`, `MutationRef`,
`OperationResult`, `Optional`, `Timestamp`, `AnyValue`, the serializers and `DataConnectError`). Both libraries
define `ConnectorConfig`, `QueryRef`, `MutationRef`, `QueryResult`, `QueryFetchPolicy` and `DataSource`: import one,
or the other with a prefix. `FirebaseDataConnect.instanceFor` uses the default app of `firebase_app_dart`
(`Firebase.app()`), so initialise it first.

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_data_connect_dart/flutterfire.dart' as compat;

Future<void> useGeneratedCode() async {
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyDummyDummyDummyDummyDummyDummyDum', // placeholder: use your own key
      appId: '1:123456789012:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );
  final compat.FirebaseDataConnect dataConnect = compat.FirebaseDataConnect.instanceFor(
    connectorConfig: compat.ConnectorConfig('us-central1', 'my-connector', 'my-service'),
  );
  dataConnect.useDataConnectEmulator('127.0.0.1', 9399);
}
```

Differences from FlutterFire that matter to generated code:

- `QueryRef.subscribe()` exists, but in 0.1.0 it emits only the results this instance fetched (the first call
  fetches once, and every later `execute()` of the same query feeds the listeners). The first `subscribe()` of an
  instance logs that server push is not supported.
- `cacheSettings` is accepted and ignored with a warning: every query goes to the server, and `cacheOnly` throws
  `DataConnectError` with the code `cacheMiss`.
- `DataConnectError` extends this repository's `FirebaseException` (from `firebase_app_dart`), not
  `firebase_core`'s: `on FirebaseException` with the FlutterFire class does not catch it.
- Not provided because they expose FlutterFire plugin types: `cachedInstances`, `auth`, `appCheck`, `transport`,
  `transportOptions`, `options`, `cacheManager`, `checkTransport()`, `checkAndInitializeCache()`.
- References made before `useDataConnectEmulator` use the emulator, and subscribe streams from before the switch
  end with `client-closed`.

## Tokens and retries

The Auth ID token and the App Check token are read from the `FirebaseApp` before each attempt, never cached by this
package. A failure of the Auth provider fails the call (`unauthenticated`); a missing or failed App Check token
never does. A call that the server refuses with `unauthenticated` after sending an ID token invalidates the Auth
token (at most once per 60 seconds) and is sent once more if a new token came back. This applies to mutations too:
a mutation is retried on `unauthenticated` on the assumption that the server refuses before the operation runs
(measured nowhere yet; probe P14 in the production kit). Other errors are never retried, because a retried
mutation may run twice. Each attempt has a 60 second deadline (`requestTimeout`), including its token wait, so a
call retried after `unauthenticated` can take up to twice that.

## Limits

- One `DataConnect` is one connector; on the VM it holds one HTTP/2 connection. Two instances are two connections.
- Response bodies over 16 MiB fail with `invalid-response`. On the VM the check runs on the announced length before
  allocation, where the HTTP/2 library lets the wrapper see it. Results deeper than data depth 100 fail with
  `invalid-response`.
- Integers in variables must lie within ±(2^53 − 1); a larger one throws `ArgumentError`. GraphQL `Int64` travels
  as a decimal string through generated helpers, so it is not affected.
- Numbers in results arrive as `int` when integral and `double` otherwise. Read a `Float` as
  `(v as num).toDouble()`.
- Integers in results beyond ±(2^53 − 1) arrive rounded on both platforms (on the VM through gRPC, as a `Struct`
  holds doubles; on the web as a JavaScript number). Schemas carry such values as strings (`Int64` does).
- A call retried after `unauthenticated` can take up to twice `requestTimeout`.
- `QueryRef.subscribe()` emits only results this instance fetched, not changes made elsewhere.
- Generated code on the VM needs the rewrite command after every `firebase dataconnect:sdk:generate`.
- A `cacheSettings` value is accepted and ignored with a warning; every query goes to the server.
- No `Vector` values (the generator refuses them as well).
- The error extensions of a GraphQL error come from the copied protos on the VM and from the JSON body on the web,
  so a key newer than the protos appears on the web only.

## Documentation

- The guide: [docs/guides/data_connect.md](../../docs/guides/data_connect.md).
- How the client compares with the JS, Android and iOS SDKs and with FlutterFire:
  [docs/data_connect_parity.md](../../docs/data_connect_parity.md); why it differs and what was rejected:
  [docs/data_connect_decisions.md](../../docs/data_connect_decisions.md).
- Examples in [example/](example): `main.dart` (VM, against the emulator), `web/main.dart` (browser) and
  `generated_main.dart` (generated code on the VM).
- The production kit: [tool/verify_production_data_connect](../../tool/verify_production_data_connect/README.md).

This package is not affiliated with, endorsed by or supported by Google LLC or Firebase. "Firebase" is a trademark
of Google LLC.
