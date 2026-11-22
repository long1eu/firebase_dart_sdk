/// [DartFirebaseDatabase], the [DatabasePlatform] of this package: one
/// instance per FlutterFire app and database URL, holding the settings that
/// FlutterFire allows before first use and the `firebase_database_dart`
/// client created on first use.
library;

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/src/app.dart';
import 'package:firebase_database_dart_platform/src/errors.dart';
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
) => fs.FirebaseDatabase(
  app,
  databaseUrl: settings.databaseUrl,
  emulatorHost: settings.emulatorHost,
  persistence: settings.persistence,
  logger: settings.logger,
);

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

  DartFirebaseDatabase._(FirebaseApp app, String? databaseURL)
    : super(app: app, databaseURL: databaseURL);

  static const int _mebibyte = 1024 * 1024;
  static const int _defaultCacheSizeBytes = 10 * _mebibyte;
  static const int _minCacheSizeBytes = _mebibyte;
  static const int _maxCacheSizeBytes = 100 * _mebibyte;

  static final Map<String, DartFirebaseDatabase> _instances =
      <String, DartFirebaseDatabase>{};

  /// The configuration of the clients created from now on.
  static DartDatabaseConfig config = const DartDatabaseConfig();

  /// Creates every client; tests replace it with one that returns a client of
  /// `databaseWithFakeServer` (`package:firebase_database_dart/testing.dart`).
  @visibleForTesting
  static DatabaseClientFactory clientFactory = createClient;

  /// Whether an instance has created its client, after which `use` throws.
  static bool get anyStarted =>
      _instances.values.any((DartFirebaseDatabase it) => it.started);

  /// The instance of [app] and [databaseURL], created on first use and kept
  /// under the key `'${app.name}|$databaseURL'`, the key of
  /// `FirebaseDatabase.instanceFor`. A kept instance whose app is not [app]
  /// (the app was deleted and created again under the same name; the client
  /// of the old one closed itself) is replaced.
  static DartFirebaseDatabase forApp(FirebaseApp app, String? databaseURL) {
    final String key = '${app.name}|$databaseURL';
    final DartFirebaseDatabase? kept = _instances[key];
    if (kept != null && kept.app == app && !kept._appDeleted) {
      return kept;
    }
    return _instances[key] = DartFirebaseDatabase._(app, databaseURL);
  }

  /// `host:port` of [useDatabaseEmulator], null until it is called.
  String? _emulator;

  /// The argument of [setPersistenceEnabled], null until it is called.
  bool? _persistenceEnabled;

  /// The argument of [setPersistenceCacheSizeBytes], null until it is called.
  int? _cacheSizeBytes;

  bool _logging = false;

  /// What the client was created with; null before.
  DatabaseClientSettings? _settings;

  fs.FirebaseDatabase? _client;

  /// Whether this instance has created its client.
  bool get started => _client != null;

  /// Whether the client's `firebase_app_dart` app was deleted (with the
  /// FlutterFire app of the same name), which closed the client.
  bool get _appDeleted {
    final fs.FirebaseDatabase? client = _client;
    return client != null &&
        !dart_app.Firebase.apps.any(
          (dart_app.FirebaseApp candidate) => identical(candidate, client.app),
        );
  }

  /// The client of this instance's app and URL, created on first use with the
  /// settings in force then ([clientFactory], [DatabaseClientSettings]).
  /// Throws a [StateError] on the registered instance, which has no app.
  fs.FirebaseDatabase get client {
    final fs.FirebaseDatabase? existing = _client;
    if (existing != null) {
      return existing;
    }
    final FirebaseApp? app = this.app;
    if (app == null) {
      throw StateError(
        'This is the registered instance of firebase_database_dart_platform, '
        'which has no app: use FirebaseDatabase.instanceFor(app: ...).',
      );
    }
    final dart_app.FirebaseApp dartApp = dartAppFor(
      app,
      tokenProviderFor: config.tokenProviderFor,
      appCheckProviderFor: config.appCheckProviderFor,
    );
    final DatabaseClientSettings settings = _clientSettings();
    final fs.FirebaseDatabase created = clientFactory(dartApp, settings);
    _settings = settings;
    return _client = created;
  }

  DatabaseClientSettings _clientSettings() {
    final DatabasePersistenceFactory? persistenceFor = config.persistenceFor;
    final bool persist = persistenceFor != null && _persistenceEnabled != false;
    return DatabaseClientSettings(
      databaseUrl: databaseURL,
      emulatorHost:
          _emulator ?? fs.FirebaseDatabase.emulatorHostFromEnvironment,
      persistence: persist
          ? persistenceFor(_cacheSizeBytes ?? _defaultCacheSizeBytes)
          : null,
      logger: _log,
    );
  }

  void _log(fs.DatabaseLogLevel level, String message) {
    if (_logging) {
      debugPrint('[firebase_database] ${level.name}: $message');
    }
  }

  void _ignored(String setting) {
    debugPrint(
      'firebase_database_dart_platform: $setting was called after the first '
      'use of this FirebaseDatabase and has no effect.',
    );
  }

  /// `DatabasePlatform.delegateFor`: [forApp].
  @override
  DatabasePlatform delegateFor({
    required FirebaseApp app,
    String? databaseURL,
  }) => forApp(app, databaseURL);

  /// `DatabasePlatform.ref`: a [DartReference] of [path] (null, `''`, `'a/b'`
  /// or `'/a/b'`, the last from `refFromURL`). No I/O and no client.
  @override
  DatabaseReferencePlatform ref([String? path]) => DartReference(this, path);

  /// `DatabasePlatform.useDatabaseEmulator`: the client's `emulatorHost`,
  /// `host:port`, an IPv6 [host] in brackets. See the table of the class.
  @override
  void useDatabaseEmulator(String host, int port) {
    final String emulator = host.contains(':') && !host.startsWith('[')
        ? '[$host]:$port'
        : '$host:$port';
    final DatabaseClientSettings? settings = _settings;
    if (settings == null) {
      _emulator = emulator;
      return;
    }
    if (settings.emulatorHost != emulator) {
      throw StateError(
        'useDatabaseEmulator($emulator) was called after the first use of '
        'this FirebaseDatabase, which talks to '
        '${settings.emulatorHost ?? 'the production database'}. Call it '
        'before any other use.',
      );
    }
  }

  /// `DatabasePlatform.setPersistenceEnabled`: whether the client gets the
  /// persistence of [DartDatabaseConfig.persistenceFor]. Persistence is on when
  /// `use` was given a factory and the app did not disable it; `true` without
  /// a factory prints one warning and stays in memory, never throws. See the
  /// table of the class.
  @override
  void setPersistenceEnabled(bool enabled) {
    final DatabaseClientSettings? settings = _settings;
    if (settings != null) {
      if (enabled != (settings.persistence != null)) {
        _ignored('setPersistenceEnabled($enabled)');
      }
      return;
    }
    if (enabled && config.persistenceFor == null) {
      debugPrint(
        'firebase_database_dart_platform: setPersistenceEnabled(true) without '
        'a persistence factory keeps the data in memory; pass '
        'FirebaseDatabaseDart.use(persistenceFor: ...).',
      );
    }
    _persistenceEnabled = enabled;
  }

  /// `DatabasePlatform.setPersistenceCacheSizeBytes`: the argument of
  /// [DatabasePersistenceFactory]. See the table of the class.
  @override
  void setPersistenceCacheSizeBytes(int cacheSize) {
    if (cacheSize < _minCacheSizeBytes || cacheSize > _maxCacheSizeBytes) {
      throw ArgumentError.value(
        cacheSize,
        'cacheSize',
        'must be between 1 MiB ($_minCacheSizeBytes) and 100 MiB '
            '($_maxCacheSizeBytes) bytes',
      );
    }
    if (_settings == null) {
      _cacheSizeBytes = cacheSize;
      return;
    }
    if (cacheSize != (_cacheSizeBytes ?? _defaultCacheSizeBytes)) {
      _ignored('setPersistenceCacheSizeBytes($cacheSize)');
    }
  }

  /// `DatabasePlatform.setLoggingEnabled`: read by
  /// [DatabaseClientSettings.logger] on every call, at any time.
  @override
  void setLoggingEnabled(bool enabled) => _logging = enabled;

  /// `DatabasePlatform.goOnline`: client `goOnline()` (creates the client).
  @override
  Future<void> goOnline() async => client.goOnline();

  /// `DatabasePlatform.goOffline`: client `goOffline()` (creates the client).
  @override
  Future<void> goOffline() async => client.goOffline();

  /// `DatabasePlatform.purgeOutstandingWrites`: client
  /// `purgeOutstandingWrites()` through `guard`; the pending writes fail with
  /// `write-cancelled`.
  @override
  Future<void> purgeOutstandingWrites() =>
      guard(() => client.purgeOutstandingWrites());
}
