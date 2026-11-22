/// [DartFirebaseDatabase], the [DatabasePlatform] of this package: one
/// instance per FlutterFire app and database URL, holding the settings that
/// FlutterFire allows before first use and the `firebase_database_dart`
/// client created on first use.
library;

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/src/app.dart';
import 'package:firebase_database_dart_platform/src/reference.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart';
import 'package:flutter/foundation.dart';

/// Returns the persistence of the clients of this package, for the cache
/// size the app set with `FirebaseDatabase.setPersistenceCacheSizeBytes` (10
/// MiB when it set none), for example
/// `(int cacheSizeBytes) => sqlitePersistence(directory, cacheSizeBytes: cacheSizeBytes)`
/// of `firebase_database_dart_sqlite`.
///
/// It is called once per instance (app and database URL), when the instance
/// creates its client, and only when persistence is on (see
/// `FirebaseDatabaseDart.use`). The client keys the cache by app name and
/// database URL, so one directory serves every app.
typedef DatabasePersistenceFactory =
    fs.DatabasePersistence Function(int cacheSizeBytes);

/// What `FirebaseDatabaseDart.use` configures; read when an instance creates
/// its client.
@immutable
class DartDatabaseConfig {
  /// The configuration of `FirebaseDatabaseDart.use`.
  const DartDatabaseConfig({
    this.tokenProviderFor,
    this.appCheckProviderFor,
    this.persistenceFor,
  });

  /// The token provider of each FlutterFire app; see `dartAppFor`.
  final TokenProviderFactory? tokenProviderFor;

  /// The App Check token provider of each FlutterFire app; see `dartAppFor`.
  final AppCheckProviderFactory? appCheckProviderFor;

  /// The persistence of the clients; null runs every client in memory.
  final DatabasePersistenceFactory? persistenceFor;
}

/// The constructor arguments of one `firebase_database_dart` client, as
/// [DartFirebaseDatabase] resolved them from its settings when it created the
/// client. Tests read them to check what was captured.
@immutable
class DatabaseClientSettings {
  /// The arguments of one client.
  const DatabaseClientSettings({
    required this.logger,
    this.databaseUrl,
    this.emulatorHost,
    this.persistence,
  });

  /// `databaseURL` of `FirebaseDatabase.instanceFor`, or null for the app's
  /// (the client derives `https://<projectId>-default-rtdb.firebaseio.com`
  /// when the app has none).
  final String? databaseUrl;

  /// `host:port` (a bracketed IPv6 host) of `useDatabaseEmulator`, else of
  /// `FIREBASE_DATABASE_EMULATOR_HOST`, else null for Google's servers.
  final String? emulatorHost;

  /// What [DatabasePersistenceFactory] returned, or null for memory only.
  final fs.DatabasePersistence? persistence;

  /// Prints through `debugPrint` while `setLoggingEnabled(true)` is in force;
  /// it reads the flag on every call.
  final fs.DatabaseLogger logger;
}

/// Creates the client of [app] with [settings]; [DartFirebaseDatabase.clientFactory].
typedef DatabaseClientFactory =
    fs.FirebaseDatabase Function(
      dart_app.FirebaseApp app,
      DatabaseClientSettings settings,
    );

/// The default [DatabaseClientFactory]: `fs.FirebaseDatabase(app,
/// databaseUrl:, emulatorHost:, persistence:, logger:)`.
fs.FirebaseDatabase createClient(
  dart_app.FirebaseApp app,
  DatabaseClientSettings settings,
) => throw UnimplementedError();

/// The implementation of [DatabasePlatform] on top of
/// `firebase_database_dart`: one instance per FlutterFire app and database
/// URL.
///
/// The instance registered as [DatabasePlatform.instance] has no app; the
/// official `firebase_database` asks it for the instance of each app and URL
/// ([delegateFor]).
///
/// The client is immutable (its settings are constructor arguments), so this
/// class keeps the settings FlutterFire allows before first use and creates
/// the client with them on first use ([client]): the first `goOnline`,
/// `goOffline`, `purgeOutstandingWrites`, `push`, or reference or query
/// operation that does I/O. `ref`, `child`, `parent`, `root`, `key`, `path`
/// and `onDisconnect()` do not create it. After that:
///
/// | Setter | Before the client | After it |
/// |---|---|---|
/// | `useDatabaseEmulator` | stored | same value: nothing; another: [StateError] |
/// | `setPersistenceEnabled` | stored | same value: nothing; another: ignored, one `debugPrint` (as Android) |
/// | `setPersistenceCacheSizeBytes` | checked (1 MiB to 100 MiB, else [ArgumentError]), stored | checked, then as `setPersistenceEnabled` |
/// | `setLoggingEnabled` | stored | takes effect at once |
class DartFirebaseDatabase extends DatabasePlatform {
  /// The instance without an app, for [DatabasePlatform.instance].
  DartFirebaseDatabase() : super();

  /// The configuration of the clients created from now on.
  static DartDatabaseConfig config = const DartDatabaseConfig();

  /// Creates every client; tests replace it with one that returns a client of
  /// `databaseWithFakeServer` (`package:firebase_database_dart/testing.dart`).
  @visibleForTesting
  static DatabaseClientFactory clientFactory = createClient;

  /// Whether an instance has created its client, after which `use` throws.
  static bool get anyStarted => throw UnimplementedError();

  /// The instance of [app] and [databaseURL], created on first use and kept
  /// under the key `'${app.name}|$databaseURL'`, the key of
  /// `FirebaseDatabase.instanceFor`. A kept instance whose app is not [app]
  /// (the app was deleted and created again under the same name; the client
  /// of the old one closed itself) is replaced.
  static DartFirebaseDatabase forApp(FirebaseApp app, String? databaseURL) =>
      throw UnimplementedError();

  /// Whether this instance has created its client.
  bool get started => throw UnimplementedError();

  /// The client of this instance's app and URL, created on first use with the
  /// settings in force then ([clientFactory], [DatabaseClientSettings]).
  /// Throws a [StateError] on the registered instance, which has no app.
  fs.FirebaseDatabase get client => throw UnimplementedError();

  /// `DatabasePlatform.delegateFor`: [forApp].
  @override
  DatabasePlatform delegateFor({
    required FirebaseApp app,
    String? databaseURL,
  }) => throw UnimplementedError();

  /// `DatabasePlatform.ref`: a [DartReference] of [path] (null, `''`, `'a/b'`
  /// or `'/a/b'`, the last from `refFromURL`). No I/O and no client.
  @override
  DatabaseReferencePlatform ref([String? path]) => throw UnimplementedError();

  /// `DatabasePlatform.useDatabaseEmulator`: the client's `emulatorHost`,
  /// `host:port`, an IPv6 [host] in brackets. See the table of the class.
  @override
  void useDatabaseEmulator(String host, int port) => throw UnimplementedError();

  /// `DatabasePlatform.setPersistenceEnabled`: whether the client gets the
  /// persistence of [DartDatabaseConfig.persistenceFor]. Persistence is on when
  /// `use` was given a factory and the app did not disable it; `true` without
  /// a factory prints one warning and stays in memory, never throws. See the
  /// table of the class.
  @override
  void setPersistenceEnabled(bool enabled) => throw UnimplementedError();

  /// `DatabasePlatform.setPersistenceCacheSizeBytes`: the argument of
  /// [DatabasePersistenceFactory]. See the table of the class.
  @override
  void setPersistenceCacheSizeBytes(int cacheSize) =>
      throw UnimplementedError();

  /// `DatabasePlatform.setLoggingEnabled`: read by
  /// [DatabaseClientSettings.logger] on every call, at any time.
  @override
  void setLoggingEnabled(bool enabled) => throw UnimplementedError();

  /// `DatabasePlatform.goOnline`: client `goOnline()` (creates the client).
  @override
  Future<void> goOnline() => throw UnimplementedError();

  /// `DatabasePlatform.goOffline`: client `goOffline()` (creates the client).
  @override
  Future<void> goOffline() => throw UnimplementedError();

  /// `DatabasePlatform.purgeOutstandingWrites`: client
  /// `purgeOutstandingWrites()` through `guard`; the pending writes fail with
  /// `write-cancelled`.
  @override
  Future<void> purgeOutstandingWrites() => throw UnimplementedError();
}
