# Setup templates

Complete programs for `cloud_firestore_dart` 0.1.x. Each one compiles as shown. Replace
`my-project` and the other placeholders; never write a real key or credential into code.

## Dependencies

```shell
dart pub add cloud_firestore_dart firebase_app_dart
dart pub add firebase_auth_providers_dart          # signed-in users or server credentials
dart pub add 'sqlite3:^2.7.3'                      # only for a disk cache on the VM
```

In Flutter, for a disk cache:

```shell
flutter pub add cloud_firestore_dart firebase_app_dart path_provider \
  'sqlite3:^2.7.3' 'sqlite3_flutter_libs:^0.5.0'
```

`sqlite3` must stay on 2.x: the opener file below imports `package:sqlite3/open.dart`, which 3.x
does not have. The opener is not part of the package; copy it into the app unchanged:
<https://raw.githubusercontent.com/long1eu/firebase_dart_sdk/main/cloud_firestore/cloud_firestore_dart/example/sqlite_database.dart>
(it defines `sqliteOpener(Directory directory, {int? pageCacheMb})`; uses `dart:ffi` and
`dart:io`). For the web the opener is `example/sqlite_database_web.dart` in the same folder.

## The FirebaseApp

```dart
final FirebaseApp app = FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: '<the Web API key of the project>',
    appId: '1:1234567890:web:0123456789abcdef',
    projectId: 'my-project',
  ),
);
```

- Synchronous. An app without `name:` is the default app (`FirebaseApp.instance`); a second app
  with the same name throws. Other apps: `FirebaseApp.withOptions(options, name: 'other')`.
- The values of a web app of the project (Firebase console, Project settings, Your apps) work on
  every platform. A FlutterFire `firebase_options.dart` compiles once its import is changed.
- On desktops and servers any unique id of the form `1:<project number>:<platform>:<suffix>`
  works as `appId`. Against the emulator any key and id work.

## CLI or server against the emulator

```dart
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

Future<void> main() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:demo',
      projectId: 'demo-my-app', // a demo- project never reaches a real one
    ),
  );
  final String emulator = Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080';
  final int colon = emulator.lastIndexOf(':');
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings().withEmulator(
      emulator.substring(0, colon),
      int.parse(emulator.substring(colon + 1)),
    ),
  );
  try {
    final DocumentReference<Map<String, Object?>> ada = firestore.doc('users/ada');
    await ada.set(<String, Object?>{'name': 'Ada', 'age': 36});
    print((await ada.get()).data());
  } on FirestoreException catch (e) {
    stderr.writeln('${e.code}: ${e.message}');
    exitCode = 1;
  } finally {
    await firestore.terminate(); // the gRPC channel keeps the process alive otherwise
  }
}
```

## Server with Application Default Credentials

```dart
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/adc.dart'; // needs dart:io

Future<void> main() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: '', // an empty key is not sent
      appId: '1:1234567890:dart:server',
      projectId: Platform.environment['FIREBASE_PROJECT_ID'] ?? 'my-project',
    ),
  );
  // Before instanceFor. Bypasses security rules; IAM decides (role Cloud Datastore User).
  app.authProvider = applicationDefaultCredentials();
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(
      cacheSettings: const MemoryCacheSettings(gcSettings: MemoryEagerGcSettings()),
    ),
  );
  final DocumentSnapshot<Map<String, Object?>> config = await firestore
      .doc('config/app')
      .get(const GetOptions(source: Source.server)); // never answer a request from a stale cache
  print(config.exists ? config.data() : 'no config');
  await firestore.terminate();
}
```

ADC looks at `GOOGLE_APPLICATION_CREDENTIALS`, then `gcloud auth application-default login`,
then the metadata server. A service account key instead (no `dart:io` needed):
`app.authProvider = OAuthTokenProvider.serviceAccount(jsonDecode(keyJson));` with
`package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart`. Share the one instance
across all requests.

## Signed-in end users

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

Future<void> signedIn(FirebaseApp app, String email, String password) async {
  // Before instanceFor: it becomes the token provider of the app.
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: app);
  await auth.signInWithEmailAndPassword(email, password); // or signInAnonymously()
  await firestore.doc('users/${auth.uid}/notes/first').set(<String, Object?>{'text': 'hi'});
  await auth.signOut();
}
```

- Covers anonymous, email/password and custom-token sign-in, token refresh, sign-out and the
  REST account operations. No Google, Apple or other federated sign-in, no phone, no email link,
  no multi-factor.
- `auth.userChanges()` (stream), `auth.currentUser`, `auth.uid`. Errors are
  `FirebaseAuthException` with codes such as `wrong-password`.
- The session is forgotten when the process ends unless you pass `storage:` (an `AuthStorage`);
  it stores the refresh token, a credential: keep it in secure storage.
- Auth emulator: `FirebaseUserAuth.forApp(app, emulatorHost: '127.0.0.1:9099')`.

## Flutter with the SQLite cache

```dart
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'sqlite_database.dart'; // the copied opener

late final FirebaseFirestore firestore;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<the Web API key of the project>',
      appId: '1:1234567890:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );
  final Directory directory = await getApplicationSupportDirectory();
  firestore = FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: sqliteOpener(directory),
    settings: Settings(cacheSettings: PersistentCacheSettings()),
  );
  runApp(
    MaterialApp(
      home: StreamBuilder<QuerySnapshot<Map<String, Object?>>>(
        stream: firestore.collection('notes').snapshots(),
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot<Map<String, Object?>>> s) =>
            Text('${s.data()?.length ?? 0} notes'),
      ),
    ),
  );
}
```

- Create the instance once, before `runApp`. On the Android emulator the host machine is
  `10.0.2.2` (no automatic `localhost` mapping).
- A hot restart opens the cache again from a new isolate; the new client takes it over. A
  background isolate gets its own app name or database.
- No test of the repository runs a Flutter app on a device.

## Tests against the emulator

```dart
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

void main() {
  late FirebaseFirestore db;
  int instances = 0;

  setUp(() {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'demo-key',
        appId: '1:1234567890:dart:test',
        projectId: 'demo-my-app',
      ),
      name: 'test-${instances++}', // own instance and cache per test
    );
    db = FirebaseFirestore.instanceFor(
      app: app,
      settings: Settings().withEmulator('127.0.0.1', 8080),
    );
  });

  tearDown(() async {
    await db.terminate();
    await db.clearPersistence();
  });

  test('writes and reads a document', () async {
    final DocumentReference<Map<String, Object?>> doc = db
        .collection('test-${DateTime.now().microsecondsSinceEpoch}')
        .doc('a');
    await doc.set(<String, Object?>{'n': 1});
    expect((await doc.get()).data(), <String, Object?>{'n': 1});
  });
}
```

Start the emulator with `firebase emulators:start --only firestore --project demo-my-app` (Firebase
CLI, Java). Rules as a user without the Auth emulator:
`withEmulator('127.0.0.1', 8080, mockUserToken: {'sub': 'alice'})`. Reset the data with
`DELETE http://127.0.0.1:8080/emulator/v1/projects/<project>/databases/(default)/documents`. The
emulator does not enforce composite indexes, quotas or App Check.
