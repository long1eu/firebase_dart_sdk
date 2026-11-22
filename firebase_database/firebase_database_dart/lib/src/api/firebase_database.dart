/// The entry point: one database of one app. JS: `api/Database.ts`; Android: `FirebaseDatabase.java`;
/// iOS: `Api/FIRDatabase.m`.
library;

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/src/api/database_logger.dart';
import 'package:firebase_database_dart/src/api/database_persistence.dart';
import 'package:firebase_database_dart/src/api/database_reference.dart';
import 'package:meta/meta.dart';

/// A connection to one Realtime Database of a [FirebaseApp].
///
/// Each constructor call makes its own instance with its own connection: there is no global cache, and two
/// instances on one URL are two connections. Settings (emulator, persistence, logging) are constructor
/// parameters; there are no setters. An open instance keeps a CLI or server program alive until [close].
/// Auth and App Check tokens come from [app].
///
/// ```dart
/// final FirebaseDatabase db = FirebaseDatabase(app);
/// db.ref('rooms/1/messages').onChildAdded.listen((DatabaseEvent e) => print(e.snapshot.value));
/// await db.ref('rooms/1/messages').push().set(<String, Object?>{'text': 'hello'});
/// await db.close();
/// ```
final class FirebaseDatabase {
  /// Creates the database of [app].
  ///
  /// [databaseUrl] defaults to the app's `databaseURL`, then to `https://<projectId>-default-rtdb.firebaseio.com`;
  /// with neither and no project id it throws an [ArgumentError].
  ///
  /// [emulatorHost] (`'host:port'` or `'[ipv6]:port'`) connects to the Database emulator over plain
  /// WebSocket, with the database URL's namespace (by default `<projectId>-default-rtdb`). See
  /// [emulatorHostFromEnvironment]. [mockUserToken] is the emulator's mock auth token; passing it without
  /// [emulatorHost] throws an [ArgumentError].
  ///
  /// [persistence] turns on disk persistence (memory only when null). [logger] receives log messages
  /// (silent when null).
  ///
  /// The constructor is synchronous, also with persistence: opening the store and restoring writes happen in
  /// the background, and calls made meanwhile wait for it, in call order.
  ///
  /// [clock], [random] and [delay] replace the wall clock, the random source (push ids, backoff) and the
  /// timers, for tests.
  FirebaseDatabase(
    this.app, {
    String? databaseUrl,
    String? emulatorHost,
    String? mockUserToken,
    DatabasePersistence? persistence,
    DatabaseLogger? logger,
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting double Function()? random,
    @visibleForTesting Future<void> Function(Duration)? delay,
  }) {
    throw UnimplementedError();
  }

  /// The `FIREBASE_DATABASE_EMULATOR_HOST` environment variable, or null when it is not set or on the web.
  ///
  /// ```dart
  /// final FirebaseDatabase db = FirebaseDatabase(
  ///   app,
  ///   emulatorHost: FirebaseDatabase.emulatorHostFromEnvironment,
  /// );
  /// ```
  static String? get emulatorHostFromEnvironment {
    // TODO(api): read the variable through a conditional import (environment_stub.dart /
    // environment_io.dart, as firebase_storage_dart does), so the main library imports no dart:io.
    throw UnimplementedError();
  }

  /// The app whose options, Auth and App Check this database uses. When the app is deleted, the database
  /// closes itself.
  final FirebaseApp app;

  /// The URL of the database.
  Uri get databaseUrl => throw UnimplementedError();

  /// The reference at [path]. `''`, `'a/b'` and `'/a/b'` are accepted and empty segments are dropped
  /// (`'a//b'` is `a/b`). The `.info` paths work too, for example `ref('.info/connected').onValue`, but
  /// writes under `.info` throw an [ArgumentError]. Makes no request, and still works after [close].
  DatabaseReference ref([String path = '']) => throw UnimplementedError();

  /// The reference for a full [url] of this database (for example
  /// `https://my-project-default-rtdb.firebaseio.com/a/b`). Throws an [ArgumentError] when [url] names
  /// another database.
  DatabaseReference refFromUrl(String url) => throw UnimplementedError();

  /// Disconnects from the server and stays offline until [goOnline]. Writes stay queued and listeners
  /// keep their data. Synchronous and idempotent, valid before the first operation; a no-op after [close].
  void goOffline() => throw UnimplementedError();

  /// Reconnects after [goOffline]. Synchronous and idempotent, valid before the first operation; a no-op
  /// after [close]. It does not undo a server kill: once the server has killed the connection the
  /// instance stays offline until it is recreated.
  void goOnline() => throw UnimplementedError();

  /// Removes every pending local write, with events reverting them, fails their Futures with
  /// `write-canceled`, and aborts every running transaction with `write-canceled`.
  Future<void> purgeOutstandingWrites() => throw UnimplementedError();

  /// Whether the client is connected to the server (`.info/connected`). The first event is the current
  /// state.
  Stream<bool> get onConnected => throw UnimplementedError();

  /// The current value of [onConnected], synchronously.
  bool get isConnected => throw UnimplementedError();

  /// The server's clock minus this device's (`.info/serverTimeOffset`); zero until the first connection.
  Duration get serverTimeOffset => throw UnimplementedError();

  /// The device's time corrected by [serverTimeOffset].
  DateTime get estimatedServerTime => throw UnimplementedError();

  /// Whether data written now survives a restart.
  ///
  /// It reports what was asked for (a non-null `persistence`) until the store is open, then whether the
  /// store is durable. It is false when another owner holds the cache file (after waiting one lease period
  /// the instance runs memory only and logs one warning), and it turns false if the store fails or is
  /// fenced later in the session.
  bool get persistenceEnabled => throw UnimplementedError();

  /// Closes the instance. Idempotent.
  ///
  /// Every open stream gets the error `database-closed` and ends, then every pending write Future fails with
  /// `database-closed`, then the returned Future completes. Afterwards every asynchronous call fails with
  /// `database-closed`, [ref] still works (it makes no request), and [goOnline] and [goOffline] do nothing.
  Future<void> close() => throw UnimplementedError();
}
