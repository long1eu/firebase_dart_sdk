# Data Connect

`firebase_data_connect_dart` is the Data Connect client of this repository: pure Dart, no plugin and no native
code. On the Dart VM (macOS, Windows, Linux) it speaks gRPC to the service; on the web (dart2js and dart2wasm) it
speaks REST. It runs the queries and mutations of a connector, hands back typed results, reports GraphQL errors
together with the partial data, and sends the Auth and App Check tokens of your `FirebaseApp`. A compatibility
library runs the code that `firebase dataconnect:sdk:generate` writes on the VM without Flutter. The package is at
0.1.0 and not on pub.dev yet.

This guide covers the setup, the untyped and the typed calls, the rules for values, errors, tokens, the emulator
and testing, generated code and the web. How the client compares with the official SDKs is in
[data_connect_parity.md](../data_connect_parity.md); why it differs and which alternatives were rejected is in
[data_connect_decisions.md](../data_connect_decisions.md).

What 0.1.0 does not do: server-pushed (realtime) subscriptions, and the normalised entity cache that the official
SDKs have. The emulator never pushes after the first result and sends no entity metadata, so neither could be
tested here. `QueryRef.subscribe()` exists and emits the results this instance fetched
([below](#subscribe)). The client was written against the emulator and the SDK sources; it has not run against a
production project yet. The [production kit](../../tool/verify_production_data_connect/README.md) runs checks
against your own project, with the owner's approval.

## What you add

The two internal transport packages are not on pub.dev. Depend on all of them from this repository:

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
carries them). Dart 3.8 or later; no Flutter dependency.

## Set up

You need a `FirebaseApp` with the `projectId` of the project that hosts the service, and the three names of the
connector:

| Part | Where it is defined |
|---|---|
| `location` | `location` in `dataconnect.yaml` |
| `serviceId` | `serviceId` in `dataconnect.yaml` |
| `connector` | `connectorId` in the connector's `connector.yaml` |

Each part must be a host label (1 to 63 of `a-z`, `0-9` and `-`, not starting or ending with `-`); anything else is
an `ArgumentError` naming the part. The app id of the app is sent on every call, and the API key on the web
(a missing one is a `StateError` at the first call that needs it).

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_data_connect_dart/firebase_data_connect_dart.dart';

DataConnect createClient() {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'AIzaSyDummyDummyDummyDummyDummyDummyDum', // placeholder: use your own key
      appId: '1:123456789012:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );
  return DataConnect(
    app,
    connector: const ConnectorConfig(
      location: 'us-central1',
      serviceId: 'my-service',
      connector: 'my-connector',
    ),
  );
}
```

There is no global cache: every `DataConnect(...)` is a new instance with its own connection. Create one per
connector and keep it. `close()` ends the connection; calls in flight and later calls fail with the code
`client-closed`. The instance also closes itself when its app is deleted.

The constructor also takes `requestTimeout` (the deadline of one attempt, 60 seconds by default), `logger`, and an
`httpClient` that the web transport uses and the instance never closes. `callerSdkType` (`CallerSdkType.base` or
`.generated`) only changes the client identification header.

## Run a query or a mutation

The untyped calls take the name of the operation and a variables map and return the `data` map of the response:

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_data_connect_dart/firebase_data_connect_dart.dart';

Future<void> untyped(FirebaseApp app) async {
  final DataConnect dataConnect = DataConnect(
    app,
    connector: const ConnectorConfig(
      location: 'us-central1',
      serviceId: 'my-service',
      connector: 'my-connector',
    ),
  );
  try {
    final Map<String, Object?> created = await dataConnect.executeMutation(
      'CreateItem',
      variables: <String, Object?>{'name': 'first'},
    );
    print(created); // {item_insert: {id: ...}}
    final Map<String, Object?> data = await dataConnect.executeQuery('ListItems');
    print(data['items']);
  } finally {
    await dataConnect.close();
  }
}
```

### Typed references

`query` and `mutation` return a reference that remembers the operation, its variables and how to decode its data.
`decode` receives the data map; `encodeVariables` turns your variables object into the map the server expects.

```dart
import 'package:firebase_data_connect_dart/firebase_data_connect_dart.dart';

class Item {
  const Item({required this.id, required this.name});

  factory Item.fromJson(Map<String, Object?> json) =>
      Item(id: json['id']! as String, name: json['name']! as String);

  final String id;
  final String name;
}

class CreateItemVariables {
  const CreateItemVariables({required this.name});

  final String name;
}

Future<void> typed(DataConnect dataConnect) async {
  final QueryRef<List<Item>, void> listItems = dataConnect.query<List<Item>, void>(
    'ListItems',
    decode: (Map<String, Object?> data) => <Item>[
      for (final Object? row in data['items']! as List<Object?>)
        Item.fromJson(row! as Map<String, Object?>),
    ],
  );
  final QueryResult<List<Item>, void> result = await listItems.execute();
  print('${result.data.length} items from ${result.source.name}');

  final MutationRef<String, CreateItemVariables> createItem =
      dataConnect.mutation<String, CreateItemVariables>(
        'CreateItem',
        variables: const CreateItemVariables(name: 'second'),
        encodeVariables: (CreateItemVariables variables) => <String, Object?>{'name': variables.name},
        decode: (Map<String, Object?> data) =>
            (data['item_insert']! as Map<String, Object?>)['id']! as String,
      );
  final MutationResult<String, CreateItemVariables> created = await createItem.execute();
  print('created ${created.data}');
}
```

If `decode` throws, the call fails with `DataConnectException` code `codec-failed`, the thrown object as `cause`
and none of the data in the message. `operationId` of a reference is the operation name plus the canonical JSON of
its encoded variables (keys sorted); two references with equal ids on one instance are the same query for
`subscribe()`.

### Fetch policy

`execute({fetchPolicy})` accepts `QueryFetchPolicy.preferCache` (the default), `cacheOnly` and `serverOnly`.
There is no cache in 0.1.0, so `preferCache` and `serverOnly` both go to the server and report
`DataSource.server`, and `cacheOnly` throws `cache-miss` without a network call. The JS SDK answers a repeated
`preferCache` query from an implicit in-memory map of the last result; this client does not.

### Subscribe

`QueryRef.subscribe()` returns a broadcast stream. The first listener of an `operationId` causes one
`execute(serverOnly)` and receives the result or the error. While a listener exists, every successful `execute()`
of a reference with the same id on this instance hands its data to every listener, each decoded by its own
reference; a listener that joins later gets the last data, unless the signed-in user changed. When the last
listener cancels, nothing is kept. The stream never shows changes made elsewhere. A later release will keep the
same signature and add server push.

## Values

Variables and results are JSON values: `null`, `bool`, `int`, `double`, `String`, `List<Object?>` and
`Map<String, Object?>`. The rules are the same over gRPC and REST:

- A variable that is another type, a map with a non-`String` key, a non-finite `double`, or an `int` outside
  ±(2^53 − 1) throws `ArgumentError` from `execute()` before anything is sent. The message names the path
  (`variables.items[3].count`) and never the value. Nesting deeper than 100 levels is refused as well.
- A number in a result is an `int` when it is integral and within ±(2^53 − 1), otherwise a `double`. So a
  GraphQL `Float` holding `3.0` arrives as `3`: read it with `(value as num).toDouble()`.
- An integer beyond ±(2^53 − 1) in a result arrives rounded, on both platforms. A schema that needs such values
  stores them as strings; GraphQL `Int64` already travels as a decimal string through generated helpers.
- A result nested deeper than 100 levels, a non-finite number, or a body over 16 MiB fails with
  `invalid-response`.

## Errors

Everything the client throws about a call is a `DataConnectException` (a `FirebaseException` of `firebase_app_dart`
with plugin `data_connect`): a kebab-case `code`, a `message` that names the failure, an optional `serverMessage`
(the server's text, shortened and sanitised) and an optional `cause`.

| Code | When |
|---|---|
| `cancelled`, `unknown`, `invalid-argument`, `deadline-exceeded`, `not-found`, `already-exists`, `permission-denied`, `resource-exhausted`, `failed-precondition`, `aborted`, `out-of-range`, `unimplemented`, `internal`, `unavailable`, `data-loss`, `unauthenticated` | the gRPC status, or on the web the one in the error body, else the one of the HTTP status |
| `partial-error` | GraphQL `errors` in a response with transport status OK (queries and mutations) |
| `invalid-response` | a body or message over the limits above, a non-finite number, an OK response with neither `errors` nor `data` |
| `codec-failed` | your `decode` threw and the response had no GraphQL errors |
| `cache-miss` | `cacheOnly` |
| `client-closed` | the call was running when `close()` was called, or came after it |

`partial-error` is a `DataConnectOperationException<Data>`: its `errors` (`GraphqlError` with `message`, `path`
made of field names and list indexes, `locations` and `extensions`, and a `code` getter for the status in
`extensions`), the `rawData` map the server returned and the decoded `data` when `decode` accepted it.

```dart
import 'package:firebase_data_connect_dart/firebase_data_connect_dart.dart';

Future<void> readErrors(DataConnect dataConnect) async {
  try {
    await dataConnect.executeMutation('DeleteItem', variables: <String, Object?>{'id': 'not-a-uuid'});
  } on DataConnectOperationException<Object?> catch (e) {
    for (final GraphqlError error in e.errors) {
      print('${error.path.join('.')}: ${error.message} (${error.code.name})');
    }
    print('the server also returned: ${e.rawData}');
  } on DataConnectException catch (e) {
    print('${e.code}: ${e.message} ${e.serverMessage ?? ''}');
  }
}
```

A mutation that reports GraphQL errors may have written; read `rawData` before you run it again. A transport
failure has no `cause`, and nothing in a message, `toString` or log line holds a token, the API key, a URL with its
query, variables or result data.

## Authentication and App Check

Before each attempt the client asks the app for the Auth ID token and the App Check token (SHARED's `TokenSource`
of `firebase_app_dart`); tokens are never cached by the client and each is sent to one request only. They travel
as `x-firebase-auth-token` and `x-firebase-appcheck`. See [authentication.md](authentication.md) for giving the app
a token provider.

- A failing Auth provider fails the call before anything is sent: `unauthenticated` (provider error),
  `unavailable` (timeout), `failed-precondition` (token too long). A missing or failing App Check token never
  fails a call.
- When the server answers `unauthenticated` to a call that carried an ID token, the client invalidates the Auth
  token (once per 60 seconds at most) and sends the call again if a different token came back; otherwise the call
  fails. A call without an ID token is not retried, so a signed-out user calling an `@auth(level: USER)`
  operation costs one request. Mutations follow the same rule (the server is assumed to refuse before it runs the
  operation; no SDK has measured it). Nothing else is retried: a retried mutation may run twice.
- `requestTimeout` bounds one attempt, token wait included; a retried call can therefore take twice as long.

## The emulator and tests

`firebase emulators:start --only dataconnect` (port 9399 by default) serves REST and gRPC on one port. Pass
`emulatorHost` (`host:port` or `[ipv6]:port`; no scheme and no Google production host, otherwise `ArgumentError`).
The plain transport is used unless `emulatorSecure` is true; a non-loopback host without TLS makes the client log
one warning that tokens go to it in clear text. `DataConnect.emulatorHostFromEnvironment` reads
`FIREBASE_DATA_CONNECT_EMULATOR_HOST` (null on the web); the constructor never reads it by itself.

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_data_connect_dart/firebase_data_connect_dart.dart';

DataConnect testClient(FirebaseApp app) => DataConnect(
  app,
  connector: const ConnectorConfig(
    location: 'us-central1',
    serviceId: 'test-service',
    connector: 'test-connector',
  ),
  emulatorHost: DataConnect.emulatorHostFromEnvironment ?? '127.0.0.1:9499',
);
```

The emulator checks no signature: an ID token whose payload has `sub` or `user_id` is accepted, a token without
it is refused with `unauthenticated`, and an operation with `@auth(level: PUBLIC)` accepts no token. The project
id in the path is not checked. A test therefore needs an app with a test token provider, not the Auth emulator.

This repository has a ready fixture under `tool/data_connect_emulator/dataconnect/` (service `test-service`,
connector `test-connector`, a table `Item`, queries `ListItems` and `MyItems`, mutations `CreateItem` and
`DeleteItem`) and the scripts that run it on a private port:

    firebase setup:emulators:dataconnect          # once: downloads the emulator
    ./tool/start_data_connect_emulator.sh         # 127.0.0.1:9499, prints the export line
    export FIREBASE_DATA_CONNECT_EMULATOR_HOST=127.0.0.1:9499
    dart run example/main.dart                    # in firebase_data_connect/firebase_data_connect_dart
    ./tool/stop_data_connect_emulator.sh

The integration tests of the package carry the tag `emulator` and skip themselves without the variable.
`tool/test_browser_data_connect.sh <dart2js|dart2wasm>` runs the whole test tree in headless Chrome against the
same emulator.

## Generated code

`firebase dataconnect:sdk:generate` writes Dart code that imports FlutterFire's `firebase_data_connect` and
`package:flutter/foundation.dart`; the generator has no option to change either. To use that code without Flutter,
run the rewrite command on the output directory after every generate:

    dart run firebase_data_connect_dart:rewrite_generated lib/generated

It swaps the two imports for `package:firebase_data_connect_dart/flutterfire.dart` and `package:meta/meta.dart`,
refuses (exit 1, nothing written) a file that imports any other `package:flutter/` library or imports
`foundation.dart` with `show`, `hide` or `as`, and is idempotent; `--check` writes nothing and exits 1 if a file
would change. Your app then depends on `firebase_data_connect_dart` and `meta`.

The generated connector class finds its instance with `FirebaseDataConnect.instanceFor`, which uses the default app
of `firebase_app_dart`; initialise it first. Both libraries define `ConnectorConfig`, `QueryRef`, `MutationRef`,
`QueryResult`, `QueryFetchPolicy` and `DataSource`; an app imports one, or the other with a prefix.

```dart
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_data_connect_dart/flutterfire.dart' as compat;

Future<void> generatedSetup() async {
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyDummyDummyDummyDummyDummyDummyDum', // placeholder: use your own key
      appId: '1:123456789012:web:0123456789abcdef',
      projectId: 'demo-test',
    ),
  );
  final compat.FirebaseDataConnect dataConnect = compat.FirebaseDataConnect.instanceFor(
    connectorConfig: compat.ConnectorConfig('us-central1', 'test-connector', 'test-service'),
  );
  dataConnect.useDataConnectEmulator('127.0.0.1', 9499);
}
```

Where it differs from FlutterFire (the full list is in [data_connect_parity.md](../data_connect_parity.md)):

- `subscribe()` emits only what this instance fetched, and logs that once.
- `cacheSettings` is accepted and ignored with a warning; `cacheOnly` fails with the error code `cacheMiss`.
- `DataConnectError` extends `firebase_app_dart`'s `FirebaseException`, so `on FirebaseException` with the
  FlutterFire class does not catch it, and `error.cause` holds the core `DataConnectException`.
- A reference made before `useDataConnectEmulator` uses the emulator; streams from before the switch end with
  `client-closed`.
- `FirebaseDataConnect` does not expose `cachedInstances`, `auth`, `appCheck`, `transport`, `transportOptions`,
  `options`, `cacheManager`, `checkTransport()` or `checkAndInitializeCache()`.

A Flutter app can instead use the override package named `firebase_data_connect` (a later release of this
repository), which lets the generated code compile unchanged.

## On the web

The web build uses REST through `package:http` and the browser's fetch. It contains neither `package:grpc`,
`package:protobuf` nor `package:fixnum`; CI checks that with `tool/check_web_imports.dart`. The REST URL carries
the API key as a `key` query parameter (as the JS SDK does), so the key can appear in the browser's network tab but
never in a message, a log line or an exception of this client. A browser needs the emulator or the service to answer
the CORS preflight of the headers the client sends; the production service's behaviour is one of the facts the
verification kit measures. An `httpClient` can be passed for tests.

## Limits

- One `DataConnect` is one connector. Two instances are two connections (one HTTP/2 connection each on the VM).
- Bodies over 16 MiB, nesting deeper than 100 levels and non-finite numbers fail with `invalid-response`.
- No realtime subscriptions, no entity cache, no `Vector` values.
- Integers beyond ±(2^53 − 1) are refused in variables and arrive rounded in results.
- Generated code on the VM needs the rewrite command after each generate.
- Realtime and the cache need production measurements first; the facts to probe are P1, P2 and P12 in
  [data_connect_decisions.md](../data_connect_decisions.md).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `ArgumentError` naming `emulatorHost` | a scheme (`http://`), no port, or a Google production host; pass `host:port` |
| `StateError` naming the app id or the API key | the `FirebaseOptions` lack it; the web needs the key, every platform needs the app id |
| `unauthenticated` against the emulator | the ID token has no `sub` or `user_id`; or an `@auth(level: USER)` operation was called with no token |
| `not-found` on every call | wrong `location`, `serviceId` or connector name, or the operation is not in the deployed connector |
| `unavailable` on the VM against the emulator | the emulator speaks plaintext only: do not set `emulatorSecure` |
| `cache-miss` | the call asked for `cacheOnly`; there is no cache in 0.1.0 |
| generated code does not compile after generate | run `rewrite_generated` again on the directory |
