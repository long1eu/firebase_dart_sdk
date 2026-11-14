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
App Check enforcement and real network conditions are not tested by it.

## Enterprise edition differences

The whole standard suite also runs against the Enterprise edition emulator
(`tool/test_integration.sh enterprise`). With emulator v1.22.0 the client behaves the same on
both editions except for the points below; the eleven tests that expect the Standard behaviour are
skipped there with a reason, and `test/integration_enterprise/edition_differences_test.dart`
pins the Enterprise behaviour. These were observed with the emulator only, not with a production
Enterprise database.

- **`null` and `NaN` in equality filters.** `whereIn`, `whereArrayContains` and
  `whereArrayContainsAny` match fields (or array elements) that are `null` or `NaN` when the
  filter value is `null` or `NaN`. On Standard they never match.
  The client evaluates these filters like Enterprise (as the JS and Android SDKs do: null is
  null, NaN is NaN; the same holds for `<=` and `>=` with a `null` or `NaN` operand). On
  Standard this means that a cached `null` or `NaN` document is first part of the local result
  of such a query, although the backend does not return it. Once the backend has confirmed
  that the document exists and that it is not a result, the client takes it out of the result
  of that query: a listener reports it with `isFromCache: true` and then its removal with
  `isFromCache: false`, and `get(Source.server)` returns what the backend returns. (The JS and
  Android SDKs keep such a document in limbo: the listener never leaves `isFromCache` and a get
  from the server does not complete.) The same mechanism covers any other query on which the
  client and the backend disagree about a cached document.
  `test/integration/firebase/firestore/property_query_test.dart` checks this.
- **`!=` and `not-in`** also return documents in which the field is `null` or missing on
  Enterprise (seen with RunQuery). The client drops them, as on Standard, but a `limit` counts
  them on the backend, so a page can come back with fewer documents than the limit although
  more match.
- **`sum` over no documents** is `null` on Enterprise and `0` on Standard (`average` is `null`
  on both).
- **Documents an aggregation covers.** On Standard, `sum`, `average` and `count` in one
  aggregation only see the documents that have every aggregated field; on Enterprise they see
  every document of the query.
- **Number of aggregations.** Standard rejects more than 5 aggregations in one query;
  Enterprise accepts them.
- **Integer `sum` overflow.** When an integer sum leaves the 64-bit range, also only while
  accumulating, the Enterprise emulator fails with `invalid-argument` ("Long overflow"); Standard
  returns a double.
- **Emulator bug:** a listener (and so `get()`, which listens) on a query with `!=` or `not-in`
  on the document id fails with "`__key__` filter value must be a Key" on the Enterprise
  emulator. The request is correct: the same query succeeds through RunQuery on that emulator
  and through Listen on the Standard one.

No test failed because of index requirements, result ordering or size limits: the emulator
does not require indexes in either edition, and it orders document ids the same way in both.
(The JS SDK notes that a production Enterprise database does not sort numeric document ids
before string ids; the emulator does not show that.)

## Testing this repository

The commands below run the test suites of `cloud_firestore_dart` itself, from
`cloud_firestore/cloud_firestore_dart` in a checkout of the repository.

The tests are not part of the published package: every `test/`, `tool/` and `docs/` path in
this section refers to a checkout of the
[repository](https://github.com/long1eu/firebase_dart_sdk/tree/main/cloud_firestore/cloud_firestore_dart) (`tool/` and `docs/` are at its
root). Run everything from this directory of the checkout. The scripts are in `tool/` at the
repository root (see `tool/README.md`).

| Tests | Command | Backend |
| --- | --- | --- |
| Unit | `dart test test/unit` | none |
| Integration | `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test test/integration` | standard emulator (`tool/start_emulator.sh`) |
| Enterprise | `FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 dart test test/integration_enterprise` | Enterprise edition emulator (`tool/start_enterprise_emulator.sh`) |
| Browser | `tool/test_browser.sh [dart2wasm\|dart2js\|both]` (repository root) | a private emulator on 127.0.0.1:8090 (or `FIRESTORE_EMULATOR_PORT`) that the script starts, Chrome |
| Integration over the web transport | `tool/test_integration.sh standard --transport=webchannel` (repository root; also `--transport=webchannel-longpolling`) | the private emulator on 127.0.0.1:8090; runs on the VM |
| Chaos tests | part of `test/integration` (`firebase/firestore/chaos/`) | standard emulator behind a TCP proxy that cuts and stalls connections |
| Firestore Lite size check | `tool/check_size.sh` (repository root) | none; compiles two programs with `dart compile js` |
| Production verification kit | `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 tool/verify_production/run.sh --backend=emulator` (repository root) | standard emulator; a real project only with `--backend=production --yes` and your credentials (run on a Standard edition database) |
| Standard suite on Enterprise | `FIRESTORE_EMULATOR_HOST=127.0.0.1:8181 FIRESTORE_EMULATOR_EDITION=enterprise dart test test/integration` | Enterprise edition emulator |

The environment variables are read by `test/util/test_backend.dart`:

- `FIRESTORE_EMULATOR_HOST` (`host:port`): the standard edition emulator, used by
  `test/integration`.
- `FIRESTORE_ENTERPRISE_EMULATOR_HOST` (`host:port`): a second emulator started in Enterprise
  edition, for the tests that need Enterprise features. Those tests live in
  `test/integration_enterprise`, get their instance from
  `IntegrationTestUtil.testEnterpriseFirestore()` and are skipped with a reason
  (`skip: IntegrationTestUtil.enterpriseEmulatorSkipReason`) while the variable is not set. Both
  emulators can run at the same time and both variables can be set together.

`tool/test_integration.sh [standard|enterprise|both]` (repository root) runs these against
emulators that are already up; `enterprise` runs `test/integration` against the Enterprise
edition emulator first and then `test/integration_enterprise`.

### Against a real Firebase project (opt-in)

There are two ways to run against a real project, both opt-in. The production verification kit
(`tool/verify_production`, see its README) is the smaller one: 15 named checks that make at most
80 writes below one document of their own, print a plan first and only run with `--yes`. It
passes against both emulators, with the known emulator differences listed in its README, and it
was run against a real Firestore database in Standard edition: 13 checks passed and 2 were
skipped (one needs an Enterprise edition database, the other a Web API key with anonymous
sign-in).

The integration suite can also run against a real project. Nothing does this by default: it
only happens when you set `FIRESTORE_TEST_PROJECT_ID` yourself and `FIRESTORE_EMULATOR_HOST` is
not set (the emulator always wins, so an emulator run can never reach a real project).

    # Either a service-account key file...
    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
    # ...or the credentials of: gcloud auth application-default login

    export FIRESTORE_TEST_PROJECT_ID=my-test-project
    export FIRESTORE_TEST_DATABASE_ID=my-database   # optional, default: (default)
    dart test test/integration/firebase/firestore/smoke_test.dart

- Credentials are Application Default Credentials, resolved by `package:grpc`: the file named
  by `GOOGLE_APPLICATION_CREDENTIALS`, else the gcloud application-default file, else the
  metadata server. The test code only passes the resulting access token to the gRPC calls; it
  does not store or print it. Do not commit key files.
- A service account needs the `Cloud Datastore User` role (`roles/datastore.user`). Its requests
  bypass security rules. With gcloud user credentials the Firestore API may ask for a quota
  project; a service account avoids that.
- **Use a throwaway project.** The tests create many documents in collections with random names
  and do not delete them; the suite makes thousands of reads and writes, which are billed.
- The suite is written for the emulator. Against production expect failures in tests that rely
  on emulator behaviour (open security rules and unauthenticated users, emulator-only limits,
  queries that need composite indexes you have not created). Start with single files.
- This path has only been exercised up to the token plumbing (unit tests with a fake
  authenticator); it has not been run against a real project.
