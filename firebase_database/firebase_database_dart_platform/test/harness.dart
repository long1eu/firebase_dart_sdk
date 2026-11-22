// What the test files share: the fake server, the registration, new apps,
// the error matchers. Owner: builder A (see lib/src/OWNERS.md). Signatures
// only; builder A writes the bodies first, then B and C use them.
//
// The rig is the client's own test double,
// package:firebase_database_dart/testing.dart: every client the shim creates
// is a databaseWithFakeServer client connected to [server], through
// DartFirebaseDatabase.clientFactory. Tests run in real async (not fakeAsync):
// the official classes and the plugin registration are in the loop.

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// The database URL of [options].
const String databaseUrl = 'https://demo-unit-default-rtdb.firebaseio.com';

/// The options of every app of [newApp], with [databaseUrl].
const FirebaseOptions options = FirebaseOptions(
  apiKey: 'test-api-key',
  appId: '1:1:web:1',
  messagingSenderId: '1',
  projectId: 'demo-unit',
  databaseURL: databaseUrl,
);

/// The reconnect delay of the fake clients: short, the tests run in real
/// time.
const Duration reconnectDelay = Duration(milliseconds: 10);

/// The fake server of the current test; a new one before each test. Every
/// client the shim creates during the test connects to it.
late FakeDatabaseServer server;

/// The settings of every client the shim created during the current test, in
/// order: what the instance captured (emulator host, persistence, logger,
/// URL). Cleared before each test.
final List<DatabaseClientSettings> createdClients = <DatabaseClientSettings>[];

/// The tokens handed out per app name; an app without one has no user.
final Map<String, String> tokens = <String, String>{};

/// A new app, so that every test starts with fresh instances and settings.
Future<FirebaseApp> newApp({FirebaseOptions appOptions = options}) =>
    throw UnimplementedError();

/// Registers the package as an app on Linux would
/// ([FirebaseDatabaseDart.use] in `setUpAll`), with the Dart core, the
/// token providers of [tokens] and [persistenceFor]; replaces
/// [DartFirebaseDatabase.clientFactory] with one that records the settings in
/// [createdClients] and returns `databaseWithFakeServer(app, server,
/// persistence: settings.persistence, logger: settings.logger,
/// reconnectDelay: reconnectDelay)`. Adds the `setUp` that makes a new
/// [server] and clears [createdClients].
void registerForTests({DatabasePersistenceFactory? persistenceFor}) =>
    throw UnimplementedError();

/// Lets the client deliver what is queued: its dispatch queue drains in
/// microtasks and yields with `Timer.run` between changes.
Future<void> settle() => throw UnimplementedError();

/// Throws a [FirebaseException] of `firebase_core` (not the client's) with
/// the plugin `firebase_database` and [code].
Matcher throwsDatabaseCode(String code) => throw UnimplementedError();

/// A [FirebaseException] of `firebase_core` (not the client's) with the
/// plugin `firebase_database` and [code].
Matcher isDatabaseCode(String code) => throw UnimplementedError();

/// A token provider with one token.
class FixedToken extends dart_app.AuthTokenProvider {
  /// A provider that always returns [token].
  FixedToken(this.token);

  /// The token.
  final String token;

  @override
  Future<dart_app.GetTokenResult> getAccessToken({
    required bool forceRefresh,
  }) => throw UnimplementedError();

  @override
  String? get uid => throw UnimplementedError();

  @override
  Stream<dart_app.AuthTokenChange> get onTokenChanged =>
      throw UnimplementedError();
}
