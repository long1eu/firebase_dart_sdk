// The credentials Firestore sends, as they arrive on the wire, over every transport: the ID token of the Firebase
// Auth user (`authorization`) and the App Check token (`x-firebase-appcheck`), how both are refreshed when the
// backend refuses them with UNAUTHENTICATED, and what happens when the App Check provider fails. Also the claims of
// the ID token in the security rules.
//
//     tool/start_auth_emulators.sh        # prints the two exports below
//     export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9197
//     export FIRESTORE_AUTH_RULES_EMULATOR_HOST=127.0.0.1:8197
//     dart test test/integration_auth/credentials_on_the_wire_test.dart
//     tool/stop_auth_emulators.sh
//
// Skipped unless both variables are set. The requests go through a recording proxy in front of the Firestore
// emulator (test/util/credentials_proxy.dart). The emulator ignores App Check and accepts any well-formed ID token,
// even an expired one, so the proxy plays the part of the production backend where a token has to be refused.
// Whether the production backend refuses a missing or invalid App Check token (enforcement) cannot be tested on the
// emulator.

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

import '../util/credentials_proxy.dart';
import '../util/io_web_http_client.dart';

const String authHostVariable = 'FIREBASE_AUTH_EMULATOR_HOST';
const String firestoreHostVariable = 'FIRESTORE_AUTH_RULES_EMULATOR_HOST';
const String projectId = 'demo-test';

String? _env(String name) {
  final String? value = Platform.environment[name]?.trim();
  return value == null || value.isEmpty ? null : value;
}

final String? skipReason =
    _env(authHostVariable) == null || _env(firestoreHostVariable) == null
    ? '$authHostVariable and $firestoreHostVariable are not both set '
          '(start the emulators with tool/start_auth_emulators.sh)'
    : null;

int _counter = 0;
String unique(String prefix) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch}x${_counter++}';

const String appCheckHeader = 'x-firebase-appcheck';

/// An App Check provider under the control of the test.
class FakeAppCheck implements InternalAppCheckTokenProvider {
  FakeAppCheck(this.token);

  /// The token [getToken] returns.
  String token;

  /// Called by [getToken] with `forceRefresh: true`; returns the new token.
  String Function()? refresh;

  /// Reported with the token, like the App Check SDKs report a failed attestation.
  Object? error;

  /// Thrown by [getToken].
  Error? throwError;

  final List<bool> forceRefreshArgs = <bool>[];
  final StreamController<AppCheckTokenResult> changes =
      StreamController<AppCheckTokenResult>.broadcast();

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
    forceRefreshArgs.add(forceRefresh);
    if (throwError != null) {
      throw throwError!;
    }
    if (forceRefresh && refresh != null) {
      token = refresh!();
    }
    return AppCheckTokenResult(token, error: error);
  }

  /// A new token, announced like the App Check SDKs do after a refresh.
  void change(String newToken) {
    token = newToken;
    changes.add(AppCheckTokenResult(newToken));
  }

  @override
  Stream<AppCheckTokenResult> get onTokenChanged => changes.stream;
}

Future<void> eventually(
  FutureOr<bool> Function() condition,
  String what, {
  Object? Function()? describe,
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!await condition()) {
    if (watch.elapsed > const Duration(seconds: 20)) {
      fail(
        'Timed out waiting for $what'
        '${describe == null ? '' : ': ${describe()}'}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

final Matcher isPermissionDenied = isA<FirestoreError>().having(
  (FirestoreError e) => e.code,
  'code',
  FirestoreErrorCode.permissionDenied,
);

final Matcher isUnauthenticated = isA<FirestoreError>().having(
  (FirestoreError e) => e.code,
  'code',
  FirestoreErrorCode.unauthenticated,
);

/// Runs [body] and collects what it prints (the SDK logs with `print`).
Future<T> capturePrints<T>(List<String> printed, Future<T> Function() body) =>
    runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          printed.add(line);
          parent.print(zone, line);
        },
      ),
    );

/// Reads a document with the `owner` token of the emulator, which bypasses the rules.
Future<Map<String, Object?>?> adminGet(String host, String path) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(
      Uri.parse(
        'http://$host/v1/projects/$projectId/databases/(default)/documents/$path',
      ),
    );
    request.headers.set('Authorization', 'Bearer owner');
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decodeStream(response);
    if (response.statusCode == 404) {
      return null;
    }
    expect(response.statusCode, 200, reason: body);
    return (jsonDecode(body) as Map<String, Object?>)['fields']
        as Map<String, Object?>?;
  } finally {
    client.close(force: true);
  }
}

/// The transports of the full SDK.
enum FullTransport { grpc, web }

/// The transports of Firestore Lite.
enum LiteTransport { grpc, rest }

void main() {
  final String? firestoreHost = _env(firestoreHostVariable);
  final List<FirebaseApp> apps = <FirebaseApp>[];
  final List<Future<void> Function()> cleanups = <Future<void> Function()>[];

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
  });

  FirebaseApp newApp({InternalAppCheckTokenProvider? appCheck}) {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'fake-api-key',
        applicationId: 'appId',
        projectId: projectId,
      ),
      name: unique('wire-'),
    );
    app.appCheckProvider = appCheck;
    apps.add(app);
    return app;
  }

  Future<FirebaseUserAuth> newAuth(FirebaseApp app) async {
    final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
      app,
      emulatorHost: _env(authHostVariable),
    );
    cleanups.add(auth.dispose);
    return auth;
  }

  (String, int) upstream() {
    final List<String> parts = firestoreHost!.split(':');
    return (parts[0], int.parse(parts[1]));
  }

  Future<GrpcCredentialsProxy> grpcProxy() async {
    final (String host, int port) = upstream();
    final GrpcCredentialsProxy proxy = await GrpcCredentialsProxy.start(
      host,
      port,
    );
    cleanups.add(proxy.close);
    return proxy;
  }

  Future<HttpCredentialsProxy> httpProxy() async {
    final (String host, int port) = upstream();
    final HttpCredentialsProxy proxy = await HttpCredentialsProxy.start(
      host,
      port,
    );
    cleanups.add(proxy.close);
    return proxy;
  }

  /// The full SDK over [transport], through a new proxy (returned with the instance).
  Future<
    (
      Firestore,
      List<RecordedRequest> Function(),
      void Function(CredentialsCheck?),
    )
  >
  newFirestore(FirebaseApp app, FullTransport transport) async {
    final String host;
    final int port;
    final List<RecordedRequest> Function() requests;
    final void Function(CredentialsCheck?) setCheck;
    if (transport == FullTransport.grpc) {
      Datastore.transportOverride = null;
      final GrpcCredentialsProxy proxy = await grpcProxy();
      (host, port) = (proxy.host, proxy.port);
      requests = () => proxy.requests;
      setCheck = (CredentialsCheck? check) => proxy.check = check;
    } else {
      final HttpCredentialsProxy proxy = await httpProxy();
      (host, port) = (proxy.host, proxy.port);
      requests = () => proxy.requests;
      setCheck = (CredentialsCheck? check) => proxy.check = check;
      Datastore.transportOverride =
          (DatabaseInfo databaseInfo, ChannelOptionsProvider options) =>
              WebChannelTransport(IoWebHttpClient(), databaseInfo, options);
    }
    final Firestore firestore = Firestore.instanceFor(
      app: app,
      settings: FirestoreSettings(
        host: host,
        port: port,
        sslEnabled: false,
        cacheSettings: const MemoryCacheSettings(),
      ),
    );
    // The transport is created with the client, on the first operation: the override stays in place until the
    // tear-down.
    cleanups.add(firestore.terminate);
    return (firestore, requests, setCheck);
  }

  /// Firestore Lite over [transport], through a new proxy.
  Future<
    (
      lite.Firestore,
      List<RecordedRequest> Function(),
      void Function(CredentialsCheck?),
    )
  >
  newLite(FirebaseApp app, LiteTransport transport) async {
    final String host;
    final int port;
    final List<RecordedRequest> Function() requests;
    final void Function(CredentialsCheck?) setCheck;
    if (transport == LiteTransport.grpc) {
      final GrpcCredentialsProxy proxy = await grpcProxy();
      (host, port) = (proxy.host, proxy.port);
      requests = () => proxy.requests;
      setCheck = (CredentialsCheck? check) => proxy.check = check;
      liteTransportOverride = null;
    } else {
      final HttpCredentialsProxy proxy = await httpProxy();
      (host, port) = (proxy.host, proxy.port);
      requests = () => proxy.requests;
      setCheck = (CredentialsCheck? check) => proxy.check = check;
      liteTransportOverride =
          (DatabaseInfo databaseInfo, ChannelOptionsProvider options) =>
              RestTransport(IoWebHttpClient(), databaseInfo, options);
    }
    final lite.Firestore db = lite.Firestore.instanceFor(
      app: app,
      settings: lite.FirestoreSettings().withEmulator(host, port),
    );
    cleanups.add(db.terminate);
    return (db, requests, setCheck);
  }

  String describe(List<RecordedRequest> requests) => requests.join('\n');

  for (final FullTransport transport in FullTransport.values) {
    final String name = transport == FullTransport.grpc
        ? 'gRPC'
        : 'WebChannel and REST';
    final Set<String> expectedTransports = transport == FullTransport.grpc
        ? <String>{'grpc'}
        : <String>{'webchannel', 'rest'};

    group('Firestore over $name', () {
      test(
        'every request carries the ID token and the App Check token',
        () async {
          final FakeAppCheck appCheck = FakeAppCheck('app-check-1');
          final FirebaseApp app = newApp(appCheck: appCheck);
          final FirebaseUserAuth auth = await newAuth(app);
          final (Firestore db, List<RecordedRequest> Function() requests, _) =
              await newFirestore(app, transport);
          final AuthUser user = await auth.signInAnonymously();
          final String idToken = (await auth.getAccessToken(
            forceRefresh: false,
          )).token;
          final String run = unique('run');

          // A write (Write stream), a listener (Listen stream) and an aggregation (a unary RPC).
          final DocumentReference<Map<String, Object?>> ref = db.doc(
            'users/${user.uid}/$run/doc',
          );
          await ref.set(<String, Object?>{'v': 1});
          final Completer<void> synced = Completer<void>();
          final StreamSubscription<DocumentSnapshot<Map<String, Object?>>> sub =
              ref.snapshots.listen((DocumentSnapshot<Map<String, Object?>> s) {
                if (!s.metadata.isFromCache && !synced.isCompleted) {
                  synced.complete();
                }
              });
          await synced.future.timeout(const Duration(seconds: 20));
          await sub.cancel();
          final AggregateQuerySnapshot count = await db
              .collection('users/${user.uid}/$run')
              .count()
              .get();
          expect(count.getCount(), 1);

          final List<RecordedRequest> seen = requests();
          expect(
            seen.map((RecordedRequest r) => r.method),
            containsAll(<String>['Write', 'Listen', 'RunAggregationQuery']),
            reason: describe(seen),
          );
          expect(
            seen.map((RecordedRequest r) => r.transport).toSet(),
            expectedTransports,
            reason: describe(seen),
          );
          for (final RecordedRequest request in seen) {
            expect(request.appCheck, 'app-check-1', reason: '$request');
            expect(
              request.authorization,
              'Bearer $idToken',
              reason: '$request',
            );
            // REST calls use the format of the JS SDK's RestConnection.
            expect(
              request.headers['x-goog-request-params'],
              request.transport == 'rest'
                  ? 'project_id=$projectId'
                  : 'projects/$projectId/databases/(default)',
              reason: '$request',
            );
          }
          expect(appCheck.forceRefreshArgs, everyElement(isFalse));
        },
      );

      test('a new App Check token is used from the next request on', () async {
        final FakeAppCheck appCheck = FakeAppCheck('app-check-1');
        final FirebaseApp app = newApp(appCheck: appCheck);
        final FirebaseUserAuth auth = await newAuth(app);
        final (Firestore db, List<RecordedRequest> Function() requests, _) =
            await newFirestore(app, transport);
        final AuthUser user = await auth.signInAnonymously();
        final CollectionReference<Map<String, Object?>> collection = db
            .collection('users/${user.uid}/${unique('run')}');
        await collection.doc('a').set(<String, Object?>{'v': 1});
        expect(
          await collection.count().get().then(
            (AggregateQuerySnapshot s) => s.getCount(),
          ),
          1,
        );
        final int streamsBefore = requests()
            .where((RecordedRequest r) => r.method == 'Write')
            .length;

        appCheck.change('app-check-2');
        expect(
          await collection.count().get().then(
            (AggregateQuerySnapshot s) => s.getCount(),
          ),
          1,
        );
        final RecordedRequest last = requests().last;
        expect(last.method, 'RunAggregationQuery');
        expect(last.appCheck, 'app-check-2');
        // Like the JS and Android SDKs, a new App Check token does not restart the open streams: the write stream
        // keeps the token it was opened with.
        await collection.doc('b').set(<String, Object?>{'v': 2});
        expect(
          requests().where((RecordedRequest r) => r.method == 'Write').length,
          streamsBefore,
          reason: describe(requests()),
        );
      });

      test('an App Check token the backend refuses is refreshed', () async {
        int refreshes = 0;
        final FakeAppCheck appCheck = FakeAppCheck('stale')
          ..refresh = () => 'fresh-${++refreshes}';
        final FirebaseApp app = newApp(appCheck: appCheck);
        final FirebaseUserAuth auth = await newAuth(app);
        final (
          Firestore db,
          List<RecordedRequest> Function() requests,
          void Function(CredentialsCheck?) setCheck,
        ) = await newFirestore(
          app,
          transport,
        );
        final AuthUser user = await auth.signInAnonymously();
        // The backend enforces App Check and does not accept the cached token.
        setCheck(
          (Map<String, String> headers) => headers[appCheckHeader] == 'stale'
              ? 'The App Check token is invalid.'
              : null,
        );
        final String path = 'users/${user.uid}/${unique('run')}/doc';

        // The write stream is refused, Firestore invalidates the token and the next attempt force-refreshes it.
        await db
            .doc(path)
            .set(<String, Object?>{'v': 1})
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () => fail(
                'The write never went through: '
                '${describe(requests())}',
              ),
            );
        expect(await adminGet(firestoreHost!, path), isNotNull);
        expect(appCheck.forceRefreshArgs, contains(isTrue));
        expect(requests().first.rejected, isTrue, reason: describe(requests()));
        expect(requests().first.appCheck, 'stale');
        final List<RecordedRequest> accepted = requests()
            .where((RecordedRequest r) => !r.rejected)
            .toList();
        expect(accepted, isNotEmpty);
        expect(
          accepted.map((RecordedRequest r) => r.appCheck),
          everyElement(startsWith('fresh-')),
          reason: describe(requests()),
        );

        // A listener works with the refreshed token too.
        final DocumentSnapshot<Map<String, Object?>> snapshot = await db
            .doc(path)
            .get(Source.server);
        expect(snapshot.data, <String, Object?>{'v': 1});
        expect(requests().last.rejected, isFalse);
      });

      test(
        'an ID token the backend refuses is refreshed with the Auth service',
        () async {
          final FirebaseApp app = newApp();
          final FirebaseUserAuth auth = await newAuth(app);
          final (
            Firestore db,
            List<RecordedRequest> Function() requests,
            void Function(CredentialsCheck?) setCheck,
          ) = await newFirestore(
            app,
            transport,
          );
          final AuthUser user = await auth.signInAnonymously();
          final String first = (await auth.getAccessToken(
            forceRefresh: false,
          )).token;
          // The token endpoint of the Auth emulator stamps `iat` in seconds: wait for a different token.
          await Future<void>.delayed(const Duration(milliseconds: 1100));
          // The backend refuses the first token (expired or revoked), as only production does.
          setCheck(
            (Map<String, String> headers) =>
                headers['authorization'] == 'Bearer $first'
                ? 'Request had invalid authentication credentials.'
                : null,
          );
          final String path = 'users/${user.uid}/${unique('run')}/doc';

          await db
              .doc(path)
              .set(<String, Object?>{'v': 1})
              .timeout(
                const Duration(seconds: 30),
                onTimeout: () => fail(
                  'The write never went through: '
                  '${describe(requests())}',
                ),
              );
          expect(await adminGet(firestoreHost!, path), isNotNull);
          final String second = (await auth.getAccessToken(
            forceRefresh: false,
          )).token;
          expect(second, isNot(first));
          expect(auth.uid, user.uid);
          expect(
            requests().first.rejected,
            isTrue,
            reason: describe(requests()),
          );
          final List<RecordedRequest> accepted = requests()
              .where((RecordedRequest r) => !r.rejected)
              .toList();
          expect(
            accepted.map((RecordedRequest r) => r.authorization),
            everyElement('Bearer $second'),
            reason: describe(requests()),
          );
          // The rules saw the refreshed token of the same user.
          expect(
            (await db.doc(path).get(Source.server)).data,
            <String, Object?>{'v': 1},
          );
        },
      );

      test('a failed App Check attestation: the placeholder token is sent and '
          'the failure is logged', () async {
        final List<String> printed = <String>[];
        await capturePrints(printed, () async {
          final FakeAppCheck appCheck = FakeAppCheck('placeholder')
            ..error = StateError('attestation failed');
          final FirebaseApp app = newApp(appCheck: appCheck);
          final FirebaseUserAuth auth = await newAuth(app);
          final (Firestore db, List<RecordedRequest> Function() requests, _) =
              await newFirestore(app, transport);
          final AuthUser user = await auth.signInAnonymously();
          final String path = 'users/${user.uid}/${unique('run')}/doc';
          await db.doc(path).set(<String, Object?>{'v': 1});
          expect(
            (await db.doc(path).get(Source.server)).data,
            <String, Object?>{'v': 1},
          );
          expect(requests(), isNotEmpty);
          expect(
            requests().map((RecordedRequest r) => r.appCheck),
            everyElement('placeholder'),
          );

          // An empty token with the error: no header at all.
          appCheck.token = '';
          expect(
            await db
                .collection('users/${user.uid}/${unique('run')}')
                .count()
                .get()
                .then((AggregateQuerySnapshot s) => s.getCount()),
            isNotNull,
          );
          expect(requests().last.method, 'RunAggregationQuery');
          expect(requests().last.headers.containsKey(appCheckHeader), isFalse);
        });
        expect(
          printed,
          contains(
            contains(
              'Error getting App Check token; using placeholder token instead',
            ),
          ),
        );
      });

      test('an App Check provider that throws: the requests go out without the '
          'header and the failure is logged', () async {
        final List<String> printed = <String>[];
        await capturePrints(printed, () async {
          final FakeAppCheck appCheck = FakeAppCheck('unused')
            ..throwError = StateError('no attestation provider');
          final FirebaseApp app = newApp(appCheck: appCheck);
          final FirebaseUserAuth auth = await newAuth(app);
          final (Firestore db, List<RecordedRequest> Function() requests, _) =
              await newFirestore(app, transport);
          final AuthUser user = await auth.signInAnonymously();
          final String path = 'users/${user.uid}/${unique('run')}/doc';
          await db
              .doc(path)
              .set(<String, Object?>{'v': 1})
              .timeout(const Duration(seconds: 20));
          expect(
            (await db.doc(path).get(Source.server)).data,
            <String, Object?>{'v': 1},
          );
          expect(requests(), isNotEmpty);
          for (final RecordedRequest request in requests()) {
            expect(
              request.headers.containsKey(appCheckHeader),
              isFalse,
              reason: '$request',
            );
            expect(
              request.authorization,
              startsWith('Bearer '),
              reason: '$request',
            );
          }
        });
        expect(
          printed,
          contains(
            allOf(
              contains('Failed to get AppCheck token'),
              contains('no attestation provider'),
            ),
          ),
        );
      });

      test('no App Check provider: no header', () async {
        final FirebaseApp app = newApp();
        final (Firestore db, List<RecordedRequest> Function() requests, _) =
            await newFirestore(app, transport);
        await expectLater(
          db.doc('signed_in/${unique('x')}').get(Source.server),
          throwsA(isPermissionDenied),
        );
        expect(requests(), isNotEmpty);
        for (final RecordedRequest request in requests()) {
          expect(request.headers.containsKey(appCheckHeader), isFalse);
          expect(request.headers.containsKey('authorization'), isFalse);
        }
      });
    }, skip: skipReason);
  }

  for (final LiteTransport transport in LiteTransport.values) {
    final String name = transport == LiteTransport.grpc ? 'gRPC' : 'REST';
    final String expectedTransport = transport == LiteTransport.grpc
        ? 'grpc'
        : 'rest';

    group('Firestore Lite over $name', () {
      test(
        'every request carries the ID token and the App Check token',
        () async {
          final FakeAppCheck appCheck = FakeAppCheck('app-check-1');
          final FirebaseApp app = newApp(appCheck: appCheck);
          final FirebaseUserAuth auth = await newAuth(app);
          final (
            lite.Firestore db,
            List<RecordedRequest> Function() requests,
            _,
          ) = await newLite(
            app,
            transport,
          );
          final AuthUser user = await auth.signInAnonymously();
          final String idToken = (await auth.getAccessToken(
            forceRefresh: false,
          )).token;
          final lite.DocumentReference<Map<String, Object?>> ref = db.doc(
            'users/${user.uid}/${unique('run')}/doc',
          );
          await ref.set(<String, Object?>{'v': 1});
          expect((await ref.get()).data, <String, Object?>{'v': 1});

          appCheck.change('app-check-2');
          expect((await ref.get()).data, <String, Object?>{'v': 1});

          final List<RecordedRequest> seen = requests();
          expect(seen, hasLength(3), reason: describe(seen));
          expect(
            seen.map((RecordedRequest r) => r.transport),
            everyElement(expectedTransport),
          );
          expect(seen.map((RecordedRequest r) => r.appCheck), <String>[
            'app-check-1',
            'app-check-1',
            'app-check-2',
          ]);
          expect(
            seen.map((RecordedRequest r) => r.authorization),
            everyElement('Bearer $idToken'),
          );
        },
      );

      test('a refused App Check token fails that request with UNAUTHENTICATED '
          'and is refreshed for the next one (like JS)', () async {
        int refreshes = 0;
        final FakeAppCheck appCheck = FakeAppCheck('stale')
          ..refresh = () => 'fresh-${++refreshes}';
        final FirebaseApp app = newApp(appCheck: appCheck);
        final (
          lite.Firestore db,
          List<RecordedRequest> Function() requests,
          void Function(CredentialsCheck?) setCheck,
        ) = await newLite(
          app,
          transport,
        );
        setCheck(
          (Map<String, String> headers) => headers[appCheckHeader] == 'stale'
              ? 'The App Check token is invalid.'
              : null,
        );
        final lite.DocumentReference<Map<String, Object?>> ref = db.doc(
          'signed_in/${unique('x')}',
        );

        await expectLater(ref.get(), throwsA(isUnauthenticated));
        // The next request force-refreshes the token; the rules then refuse the anonymous request.
        await expectLater(ref.get(), throwsA(isPermissionDenied));
        expect(appCheck.forceRefreshArgs, <bool>[false, true]);
        expect(requests().map((RecordedRequest r) => r.appCheck), <String>[
          'stale',
          'fresh-1',
        ]);
        expect(requests().map((RecordedRequest r) => r.rejected), <bool>[
          true,
          false,
        ]);
      });

      test('a refused ID token fails that request with UNAUTHENTICATED and is '
          'refreshed for the next one', () async {
        final FirebaseApp app = newApp();
        final FirebaseUserAuth auth = await newAuth(app);
        final (
          lite.Firestore db,
          List<RecordedRequest> Function() requests,
          void Function(CredentialsCheck?) setCheck,
        ) = await newLite(
          app,
          transport,
        );
        final AuthUser user = await auth.signInAnonymously();
        final String first = (await auth.getAccessToken(
          forceRefresh: false,
        )).token;
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        setCheck(
          (Map<String, String> headers) =>
              headers['authorization'] == 'Bearer $first'
              ? 'Request had invalid authentication credentials.'
              : null,
        );
        final lite.DocumentReference<Map<String, Object?>> ref = db.doc(
          'users/${user.uid}/${unique('run')}/doc',
        );

        await expectLater(
          ref.set(<String, Object?>{'v': 1}),
          throwsA(isUnauthenticated),
        );
        await ref.set(<String, Object?>{'v': 1});
        final String second = (await auth.getAccessToken(
          forceRefresh: false,
        )).token;
        expect(second, isNot(first));
        expect(requests().map((RecordedRequest r) => r.authorization), <String>[
          'Bearer $first',
          'Bearer $second',
        ]);
        expect((await ref.get()).data, <String, Object?>{'v': 1});
      });

      test(
        'an App Check provider that throws: the request goes out without it',
        () async {
          final List<String> printed = <String>[];
          await capturePrints(printed, () async {
            final FakeAppCheck appCheck = FakeAppCheck('unused')
              ..throwError = StateError('no attestation provider');
            final FirebaseApp app = newApp(appCheck: appCheck);
            final FirebaseUserAuth auth = await newAuth(app);
            final (
              lite.Firestore db,
              List<RecordedRequest> Function() requests,
              _,
            ) = await newLite(
              app,
              transport,
            );
            final AuthUser user = await auth.signInAnonymously();
            final lite.DocumentReference<Map<String, Object?>> ref = db.doc(
              'users/${user.uid}/${unique('run')}/doc',
            );
            await ref.set(<String, Object?>{'v': 1});
            expect((await ref.get()).data, <String, Object?>{'v': 1});
            expect(requests(), hasLength(2));
            expect(
              requests().map(
                (RecordedRequest r) => r.headers.containsKey(appCheckHeader),
              ),
              everyElement(isFalse),
            );
          });
          expect(printed, contains(contains('Failed to get AppCheck token')));
        },
      );
    }, skip: skipReason);
  }

  group('Security rules and the claims of the ID token', () {
    Future<Firestore> direct(FirebaseApp app) async {
      final (String host, int port) = upstream();
      final Firestore firestore = Firestore.instanceFor(
        app: app,
        settings: FirestoreSettings(
          host: host,
          port: port,
          sslEnabled: false,
          cacheSettings: const MemoryCacheSettings(),
        ),
      );
      cleanups.add(firestore.terminate);
      return firestore;
    }

    String customToken(String uid, Map<String, Object?> claims) {
      // The Auth emulator accepts an unsigned custom token.
      String encode(Object json) =>
          base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
      final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return '${encode(<String, Object?>{'alg': 'none', 'typ': 'JWT'})}.'
          '${encode(<String, Object?>{'iss': 'tests@example.com', 'sub': 'tests@example.com', 'aud': 'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit', 'iat': now, 'exp': now + 3600, 'uid': uid, 'claims': claims})}.';
    }

    test('request.auth.token carries the custom claims', () async {
      final FirebaseApp app = newApp();
      final FirebaseUserAuth auth = await newAuth(app);
      final Firestore db = await direct(app);
      final String path = 'testers/${unique('doc')}';

      await auth.signInWithCustomToken(
        customToken(unique('plain-'), <String, Object?>{'role': 'user'}),
      );
      await expectLater(
        db.doc(path).set(<String, Object?>{'v': 1}),
        throwsA(isPermissionDenied),
      );

      await auth.signInWithCustomToken(
        customToken(unique('tester-'), <String, Object?>{'role': 'tester'}),
      );
      await db.doc(path).set(<String, Object?>{'v': 1});
      expect((await db.doc(path).get(Source.server)).data, <String, Object?>{
        'v': 1,
      });
    });

    test(
      'request.auth.token carries the sign-in provider and the email',
      () async {
        final FirebaseApp app = newApp();
        final FirebaseUserAuth auth = await newAuth(app);
        final Firestore db = await direct(app);
        final String path = 'password_users/${unique('doc')}';

        await auth.signInAnonymously();
        await expectLater(
          db.doc(path).set(<String, Object?>{'v': 1}),
          throwsA(isPermissionDenied),
        );

        await auth.createUserWithEmailAndPassword(
          '${unique('pw')}@example.com',
          'password',
        );
        await db.doc(path).set(<String, Object?>{'v': 1});
        expect((await db.doc(path).get(Source.server)).data, <String, Object?>{
          'v': 1,
        });
      },
    );
  }, skip: skipReason);
}
