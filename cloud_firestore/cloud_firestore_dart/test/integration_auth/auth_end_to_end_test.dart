// Firebase Auth end to end: a user signs in with `firebase_auth_providers_dart` against the Firebase Auth emulator,
// and Firestore talks to an emulator whose security rules require that user (tool/auth_emulators/firestore.rules).
//
//     tool/start_auth_emulators.sh        # prints the two exports below
//     export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197
//     export FIRESTORE_AUTH_RULES_EMULATOR_HOST=127.0.0.1:8197
//     dart test test/integration_auth
//     tool/stop_auth_emulators.sh
//
// Skipped unless both variables are set. Every scenario runs over gRPC and over the web transport (WebChannel and
// REST on `dart:io` HTTP); Firestore Lite runs over gRPC and over REST.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/lite.dart' as lite;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/firestore.dart'
    show liteTransportOverride;
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_channel_transport.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

import '../util/io_web_http_client.dart';
import '../util/test_backend.dart';

const String authHostVariable = 'FIREBASE_AUTH_EMULATOR_HOST';
const String firestoreHostVariable = 'FIRESTORE_AUTH_RULES_EMULATOR_HOST';
const String projectId = 'demo-test';

String? _env(String name) {
  final String? value = Platform.environment[name]?.trim();
  return value == null || value.isEmpty ? null : value;
}

final String? skipReason = _env(authHostVariable) == null ||
        _env(firestoreHostVariable) == null
    ? '$authHostVariable and $firestoreHostVariable are not both set '
        '(start the emulators with tool/start_auth_emulators.sh)'
    : null;

int _counter = 0;
String unique(String prefix) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch}x${_counter++}';

/// Reads or writes a document with the `owner` token of the emulator, which bypasses the rules: what is really
/// stored, whoever is signed in.
class Admin {
  Admin(this.host);

  final String host;
  final HttpClient _client = HttpClient();

  Uri _uri(String path) => Uri.parse(
      'http://$host/v1/projects/$projectId/databases/(default)/documents/$path');

  Future<Map<String, Object?>?> get(String path) async {
    final HttpClientRequest request = await _client.getUrl(_uri(path));
    request.headers.set('Authorization', 'Bearer owner');
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decodeStream(response);
    if (response.statusCode == 404) {
      return null;
    }
    expect(response.statusCode, 200, reason: body);
    return (jsonDecode(body) as Map<String, Object?>)['fields']
        as Map<String, Object?>?;
  }

  Future<void> setString(String path, String field, String value) async {
    final HttpClientRequest request = await _client.patchUrl(_uri(path));
    request.headers
      ..set('Authorization', 'Bearer owner')
      ..contentType = ContentType.json;
    request.write(jsonEncode(<String, Object?>{
      'fields': <String, Object?>{
        field: <String, Object?>{'stringValue': value},
      },
    }));
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decodeStream(response);
    expect(response.statusCode, 200, reason: body);
  }

  void close() => _client.close(force: true);
}

Future<void> eventually(FutureOr<bool> Function() condition, String what,
    {Object? Function()? describe}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!await condition()) {
    if (watch.elapsed > const Duration(seconds: 15)) {
      fail('Timed out waiting for $what'
          '${describe == null ? '' : ': ${describe()}'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

final Matcher isPermissionDenied = isA<FirestoreError>().having(
    (FirestoreError e) => e.code, 'code', FirestoreErrorCode.permissionDenied);

/// A listener that records its snapshots and its error.
class Listening {
  Listening(Query<Map<String, Object?>> query) {
    _sub = query
        .getSnapshotsWithOptions(const SnapshotListenOptions(
            metadataChanges: MetadataChanges.include))
        .listen(events.add, onError: errors.add);
  }

  late final StreamSubscription<QuerySnapshot<Map<String, Object?>>> _sub;
  final List<QuerySnapshot<Map<String, Object?>>> events =
      <QuerySnapshot<Map<String, Object?>>>[];
  final List<Object> errors = <Object>[];

  bool get synced => events.isNotEmpty && !events.last.metadata.isFromCache;

  List<String> get ids => events.last.docs
      .map((QueryDocumentSnapshot<Map<String, Object?>> d) => d.id)
      .toList();

  String describe() =>
      'events=${events.map((QuerySnapshot<Map<String, Object?>> e) => '${e.metadata.isFromCache ? 'cache' : 'server'}:${e.docs.length}').toList()} '
      'errors=$errors';

  Future<void> cancel() => _sub.cancel();
}

void main() {
  final EmulatorAddress? firestoreAddress = skipReason == null
      ? EmulatorAddress.parse(_env(firestoreHostVariable)!)
      : null;
  late Admin admin;
  final List<FirebaseApp> apps = <FirebaseApp>[];
  final List<Future<void> Function()> cleanups = <Future<void> Function()>[];

  setUp(() {
    if (skipReason == null) {
      admin = Admin(_env(firestoreHostVariable)!);
    }
  });

  tearDown(() async {
    for (final Future<void> Function() cleanup in cleanups.reversed) {
      await cleanup();
    }
    cleanups.clear();
    for (final FirebaseApp app in apps) {
      app.delete();
    }
    apps.clear();
    Datastore.transportOverride = null;
    liteTransportOverride = null;
    if (skipReason == null) {
      admin.close();
    }
  });

  FirebaseApp newApp() {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
          apiKey: 'fake-api-key', applicationId: 'appId', projectId: projectId),
      name: unique('auth-e2e-'),
    );
    apps.add(app);
    return app;
  }

  Future<FirebaseUserAuth> newAuth(FirebaseApp app) async {
    final FirebaseUserAuth auth =
        await FirebaseUserAuth.forApp(app, emulatorHost: _env(authHostVariable));
    cleanups.add(auth.dispose);
    return auth;
  }

  /// A Firestore instance of the full SDK for [app], over gRPC or over the web transport, with a memory cache.
  Future<Firestore> newFirestore(FirebaseApp app, {required bool web}) async {
    Datastore.transportOverride = web
        ? (DatabaseInfo databaseInfo, ChannelOptionsProvider options) =>
            WebChannelTransport(IoWebHttpClient(), databaseInfo, options)
        : null;
    final Firestore firestore = Firestore.instanceFor(
      app: app,
      settings: FirestoreSettings(
        host: firestoreAddress!.host,
        port: firestoreAddress.port,
        sslEnabled: false,
        cacheSettings: const MemoryCacheSettings(),
      ),
    );
    Datastore.transportOverride = null;
    cleanups.add(firestore.terminate);
    return firestore;
  }

  for (final bool web in <bool>[false, true]) {
    final String transport = web ? 'web transport' : 'gRPC';

    group('Firestore over $transport', () {
      test('the security rules see the signed-in user', () async {
        final FirebaseApp app = newApp();
        final FirebaseUserAuth auth = await newAuth(app);
        final Firestore db = await newFirestore(app, web: web);
        final String run = unique('run');

        // Nobody is signed in: the request carries no token and the rules refuse it.
        await expectLater(db.doc('signed_in/$run').get(Source.server),
            throwsA(isPermissionDenied));
        await expectLater(
            db.doc('signed_in/$run').set(<String, Object?>{'v': 1}),
            throwsA(isPermissionDenied));

        final AuthUser user = await auth.signInAnonymously();
        final DocumentReference<Map<String, Object?>> own =
            db.doc('users/${user.uid}/notes/$run');
        await own.set(<String, Object?>{'text': 'mine'});
        expect((await own.get(Source.server)).data,
            <String, Object?>{'text': 'mine'});
        expect(await admin.get('users/${user.uid}/notes/$run'), isNotNull);

        // request.auth.uid is the uid of the user: the documents of somebody else stay out of reach.
        await expectLater(
            db.doc('users/somebody-else/notes/$run').get(Source.server),
            throwsA(isPermissionDenied));
        await expectLater(
            db
                .doc('users/somebody-else/notes/$run')
                .set(<String, Object?>{'text': 'not mine'}),
            throwsA(isPermissionDenied));
        expect(await admin.get('users/somebody-else/notes/$run'), isNull);
      });

      test('a user switch restarts the listeners with the new identity',
          () async {
        final FirebaseApp app = newApp();
        final FirebaseUserAuth auth = await newAuth(app);
        final Firestore db = await newFirestore(app, web: web);
        final String run = unique('run');
        final String emailA = '${unique('a')}@example.com';
        final String emailB = '${unique('b')}@example.com';

        final AuthUser a =
            await auth.createUserWithEmailAndPassword(emailA, 'password-a');
        await db
            .doc('users/${a.uid}/$run/doc')
            .set(<String, Object?>{'owner': 'a'});
        final Listening asA = Listening(db.collection('users/${a.uid}/$run'));
        await eventually(() => asA.synced, 'the listener of A',
            describe: asA.describe);
        expect(asA.ids, <String>['doc']);
        expect(asA.errors, isEmpty);

        // B signs in on the same app. The listener that is still open on the documents of A is restarted with
        // the identity of B, and the rules refuse it.
        final AuthUser b =
            await auth.createUserWithEmailAndPassword(emailB, 'password-b');
        expect(b.uid, isNot(a.uid));
        await eventually(() => asA.errors.isNotEmpty,
            'the listener of A to be refused for B',
            describe: asA.describe);
        expect(asA.errors.single, isPermissionDenied);
        await asA.cancel();

        // B has its own documents.
        await db
            .doc('users/${b.uid}/$run/doc')
            .set(<String, Object?>{'owner': 'b'});
        final Listening asB = Listening(db.collection('users/${b.uid}/$run'));
        await eventually(() => asB.synced, 'the listener of B',
            describe: asB.describe);
        expect(asB.ids, <String>['doc']);

        // Back to A: the listener of B is refused, a new listener of A works.
        await auth.signInWithEmailAndPassword(emailA, 'password-a');
        expect(auth.uid, a.uid);
        await eventually(() => asB.errors.isNotEmpty,
            'the listener of B to be refused for A',
            describe: asB.describe);
        expect(asB.errors.single, isPermissionDenied);
        await asB.cancel();
        final Listening again = Listening(db.collection('users/${a.uid}/$run'));
        await eventually(() => again.synced, 'the new listener of A',
            describe: again.describe);
        expect(again.ids, <String>['doc']);
        await again.cancel();
      });

      test('pending writes stay with the user who made them', () async {
        final FirebaseApp app = newApp();
        final FirebaseUserAuth auth = await newAuth(app);
        final Firestore db = await newFirestore(app, web: web);
        final String run = unique('run');
        final String emailA = '${unique('a')}@example.com';
        final String emailB = '${unique('b')}@example.com';

        final AuthUser a =
            await auth.createUserWithEmailAndPassword(emailA, 'password-a');
        final String pendingPath = 'users/${a.uid}/$run/pending';
        await db.doc('users/${a.uid}/$run/sent').set(<String, Object?>{'n': 1});

        // A writes while Firestore is offline: the write waits in the queue of A.
        await db.disableNetwork();
        bool acknowledged = false;
        unawaited(db
            .doc(pendingPath)
            .set(<String, Object?>{'text': 'written by a, offline'}).then((_) {
          acknowledged = true;
        }));
        expect((await db.doc(pendingPath).get(Source.cache)).exists, isTrue);

        // B signs in and the network comes back: the write of A is not sent with the token of B, and B does not
        // see it in the cache.
        final AuthUser b =
            await auth.createUserWithEmailAndPassword(emailB, 'password-b');
        await db.enableNetwork();
        await db.doc('users/${b.uid}/$run/own').set(<String, Object?>{'n': 2});
        await db.waitForPendingWrites();
        expect(await admin.get(pendingPath), isNull);
        expect(acknowledged, isFalse);
        await expectLater(db.doc(pendingPath).get(Source.cache),
            throwsA(isA<FirestoreError>()),
            reason: 'B has no cached document of A');

        // A comes back: the write is sent with the token of A.
        await auth.signInWithEmailAndPassword(emailA, 'password-a');
        await eventually(() async => await admin.get(pendingPath) != null,
            'the pending write of A to reach the backend');
        await db.waitForPendingWrites();
        expect(
            (await db.doc(pendingPath).get(Source.server)).data,
            <String, Object?>{'text': 'written by a, offline'});
      });

      test('a refreshed token keeps the listeners going', () async {
        final FirebaseApp app = newApp();
        final FirebaseUserAuth auth = await newAuth(app);
        final Firestore db = await newFirestore(app, web: web);
        final String run = unique('run');
        final AuthUser user = await auth.signInAnonymously();
        final String first =
            (await auth.getAccessToken(forceRefresh: false)).token;

        final Listening listening =
            Listening(db.collection('users/${user.uid}/$run'));
        await eventually(() => listening.synced, 'the listener',
            describe: listening.describe);

        // A new ID token from the token endpoint of the Auth emulator. Firestore restarts its streams with it.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        final String second =
            (await auth.getAccessToken(forceRefresh: true)).token;
        expect(second, isNot(first));
        await admin.setString(
            'users/${user.uid}/$run/after', 'text', 'after the refresh');
        await eventually(() => listening.ids.contains('after'),
            'a change after the token refresh',
            describe: listening.describe);
        expect(listening.errors, isEmpty);
        await listening.cancel();
      });

      test('sign-out drops access', () async {
        final FirebaseApp app = newApp();
        final FirebaseUserAuth auth = await newAuth(app);
        final Firestore db = await newFirestore(app, web: web);
        final String run = unique('run');
        final AuthUser user = await auth.signInAnonymously();
        final DocumentReference<Map<String, Object?>> ref =
            db.doc('users/${user.uid}/$run/doc');
        await ref.set(<String, Object?>{'v': 1});
        final Listening listening =
            Listening(db.collection('users/${user.uid}/$run'));
        await eventually(() => listening.synced, 'the listener',
            describe: listening.describe);

        await auth.signOut();
        await eventually(() => listening.errors.isNotEmpty,
            'the listener to be refused after the sign-out',
            describe: listening.describe);
        expect(listening.errors.single, isPermissionDenied);
        await listening.cancel();
        await expectLater(ref.get(Source.server), throwsA(isPermissionDenied));
        await expectLater(
            ref.set(<String, Object?>{'v': 2}), throwsA(isPermissionDenied));
        expect((await admin.get('users/${user.uid}/$run/doc'))!['v'],
            <String, Object?>{'integerValue': '1'});
      });
    }, skip: skipReason);
  }

  for (final bool rest in <bool>[false, true]) {
    final String transport = rest ? 'REST' : 'gRPC';

    test('Firestore Lite over $transport sends the token of the current user',
        () async {
      final FirebaseApp app = newApp();
      final FirebaseUserAuth auth = await newAuth(app);
      final List<IoWebHttpClient> httpClients = <IoWebHttpClient>[];
      liteTransportOverride = rest
          ? (DatabaseInfo databaseInfo, ChannelOptionsProvider options) {
              httpClients.add(IoWebHttpClient());
              return RestTransport(httpClients.last, databaseInfo, options);
            }
          : null;
      final lite.Firestore db = lite.Firestore.instanceFor(
        app: app,
        settings: lite.FirestoreSettings()
            .withEmulator(firestoreAddress!.host, firestoreAddress.port),
      );
      cleanups.add(db.terminate);
      final String run = unique('run');

      await expectLater(db.doc('signed_in/$run').get(),
          throwsA(isPermissionDenied));

      final AuthUser a = await auth.signInAnonymously();
      final lite.DocumentReference<Map<String, Object?>> ofA =
          db.doc('users/${a.uid}/notes/$run');
      await ofA.set(<String, Object?>{'owner': 'a'});
      expect((await ofA.get()).data, <String, Object?>{'owner': 'a'});
      await expectLater(db.doc('users/somebody-else/notes/$run').get(),
          throwsA(isPermissionDenied));

      // Another user: the next request carries the new token.
      final AuthUser b = await auth.createUserWithEmailAndPassword(
          '${unique('lite')}@example.com', 'password');
      await expectLater(ofA.get(), throwsA(isPermissionDenied));
      final lite.DocumentReference<Map<String, Object?>> ofB =
          db.doc('users/${b.uid}/notes/$run');
      await ofB.set(<String, Object?>{'owner': 'b'});
      expect((await ofB.get()).data, <String, Object?>{'owner': 'b'});

      await auth.signOut();
      await expectLater(ofB.get(), throwsA(isPermissionDenied));
      await expectLater(
          ofB.set(<String, Object?>{'owner': 'nobody'}),
          throwsA(isPermissionDenied));
      expect((await admin.get('users/${b.uid}/notes/$run'))!['owner'],
          <String, Object?>{'stringValue': 'b'});
      if (rest) {
        expect(httpClients, hasLength(1));
        expect(httpClients.single.log, isNotEmpty);
      }
    }, skip: skipReason);
  }
}
