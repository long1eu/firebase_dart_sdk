# The emulator and testing

Develop and test against the Firestore emulator of the Firebase CLI: it needs no project, costs
nothing and can be reset at any time. Everything in this package was verified against it.

## Start the emulator

```shell
firebase emulators:start --only firestore --project demo-my-app
```

A project id that starts with `demo-` keeps the emulator from talking to a real project. For
[Pipelines](pipelines.md) and the other Enterprise features, start the emulator in Enterprise
edition: the Firebase CLI takes the edition from `firebase.json` (see the Firebase CLI
documentation), and the emulator JAR takes `--database-edition enterprise` (the repository's
`tool/start_enterprise_emulator.sh` runs the JAR that way, next to a Standard emulator).

## Connect to it

The settings must be passed to the call that creates the instance:

```dart
final FirebaseApp app = FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: 'demo-key', // the emulator accepts any key and application id
    applicationId: '1:1234567890:dart:demo',
    projectId: 'demo-my-app',
  ),
);
final Firestore firestore = Firestore.instanceFor(
  app: app,
  settings: FirestoreSettings().withEmulator('127.0.0.1', 8080),
);
```

The package does not read `FIRESTORE_EMULATOR_HOST` by itself; read it in your own code if you
want the same switch:

```dart
import 'dart:io';

final String? emulator = Platform.environment['FIRESTORE_EMULATOR_HOST']; // host:port
final FirestoreSettings settings = emulator == null
    ? FirestoreSettings()
    : FirestoreSettings().withEmulator(
        emulator.substring(0, emulator.lastIndexOf(':')),
        int.parse(emulator.substring(emulator.lastIndexOf(':') + 1)),
      );
```

## Security rules as a user

To test the security rules as a signed-in user without the Auth emulator, pass a mock user
token: the claims of a Firebase ID token, which the client encodes as an unsigned JWT (as
`connectFirestoreEmulator` does in the JS SDK), or a token string.

```dart
final Firestore asAlice = Firestore.instanceFor(
  app: FirebaseApp.withOptions(app.options, name: 'alice'),
  settings: FirestoreSettings().withEmulator('127.0.0.1', 8080, mockUserToken: {'sub': 'alice'}),
);
```

A mock token is only accepted together with `withEmulator`, so it is never sent to a production
host. To test real sign-in flows, use the Auth emulator with
[`firebase_auth_providers_dart`](../../firebase_auth/firebase_auth_providers_dart/README.md).

## Tests with package:test

```dart
import 'package:test/test.dart';

late Firestore db;
int instances = 0;

setUp(() {
  // A new app name gives each test its own instance (and its own cache).
  final FirebaseApp testApp = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      applicationId: '1:1234567890:dart:test',
      projectId: 'demo-my-app',
    ),
    name: 'test-${instances++}',
  );
  db = Firestore.instanceFor(
    app: testApp,
    settings: FirestoreSettings().withEmulator('127.0.0.1', 8080),
  );
});

tearDown(() async {
  await db.terminate();
  await db.clearPersistence();
});

test('writes and reads a document', () async {
  // A collection name of its own keeps tests independent on a shared emulator.
  final DocumentReference<Map<String, Object?>> doc =
      db.collection('test-${DateTime.now().microsecondsSinceEpoch}').doc('a');
  await doc.set({'n': 1});
  expect((await doc.get()).data, {'n': 1});
});
```

- **Terminate every instance and await every operation** before the test ends. An operation that
  is still in flight when its instance is terminated fails afterwards, and that unhandled error
  fails whichever test runs then.
- `clearPersistence()` after `terminate()` deletes a persistent cache between tests.
- To reset the data of the emulator, call its REST endpoint
  `DELETE http://127.0.0.1:8080/emulator/v1/projects/<project>/databases/(default)/documents`.
- `Firestore.setLogLevel(LogLevel.debug)` prints what the client does.
- To test offline behaviour, use `disableNetwork()` and `enableNetwork()`.

## Differences between the emulator and production

The emulator does not enforce everything production does: composite index requirements, quotas,
App Check enforcement and real network conditions are not tested by it. The Enterprise edition
emulator also differs from the Standard one in a few query and aggregation results; the
[Testing section](../../cloud_firestore/cloud_firestore_dart/README.md#testing) of the package
README lists them, together with how this repository's own test suites are run.
