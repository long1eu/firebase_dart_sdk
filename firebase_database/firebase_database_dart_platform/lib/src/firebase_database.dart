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
/// It is called each time an instance (app and database URL) creates a
/// client, and only when persistence is on (see `FirebaseDatabaseDart.use`):
/// at the first use, and again when the instance creates a new client after
/// the app was deleted. The client keys the cache by app name and
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

  /// `host:port` (a bracketed IPv6 host) of `useDatabaseEmulator`, else null
  /// for Google's servers. The `FIREBASE_DATABASE_EMULATOR_HOST` environment
  /// variable is not read: an app goes to the emulator only when it asks to.
  final String? emulatorHost;

  /// What [DatabasePersistenceFactory] returned, or null for memory only.
  final fs.DatabasePersistence? persistence;

  /// Prints through `debugPrint`: warnings and errors always, debug and info
  /// lines only while `setLoggingEnabled(true)` is in force (it reads the flag
  /// on every call).
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
/// (see [forApp]).
///
/// The instance registered as [DatabasePlatform.instance] has no app; the
/// official `firebase_database` asks it for the instance of each app and URL
/// ([delegateFor]).
///
/// The client is immutable (its settings are constructor arguments), so this
/// class keeps the settings FlutterFire allows before first use and creates
/// the client with them on first use ([client]): the first `goOnline`,
/// `goOffline`, `purgeOutstandingWrites`, `push`, listen, or reference or
/// query operation that does I/O. `ref`, `child`, `parent`, `root`, `key`,
/// `path`, `onDisconnect()` and an event stream not listened to yet do not
/// create it. Deleting the FlutterFire app closes the client the instance
/// has when the delete starts, unless that client was created while an
/// earlier delete ran. A use while the delete runs (`firebase_core`
/// has disposed the services, the core still has the app) creates a client
/// that neither that delete nor a later one closes; on a core that keeps the
/// `firebase_app_dart` app (the native and web ones) the instance keeps
/// using it, also after the app was created again. A later use, after an
/// app of the same name was created again with the same options, creates a
/// new client with the stored settings when the instance has none open;
/// with other options it throws a [StateError] (see [forApp]). After the
/// client is created:
///
/// | Setter | Before the client | After it |
/// |---|---|---|
/// | `useDatabaseEmulator` | stored | same value: nothing; another: [StateError] |
/// | `setPersistenceEnabled` | stored | as the client is (on disk or in memory): nothing; else ignored, one `debugPrint` (as Android) |
/// | `setPersistenceCacheSizeBytes` | checked (1 MiB to 100 MiB, else [ArgumentError]), stored | checked; the stored size (10 MiB when none): nothing; else ignored, one `debugPrint` |
/// | `setLoggingEnabled` | stored | takes effect at once |
///
/// A client is on disk only when `FirebaseDatabaseDart.use` was given a
/// persistence factory, so without one `setPersistenceEnabled(true)` after
/// the client is ignored with that line, also when it was called with
/// `true` before.
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
  /// per app name and resolved database, as the Android SDK keeps one
  /// instance per database: `databaseURL`, else the app's `databaseURL`, else
  /// `https://<projectId>-default-rtdb.firebaseio.com`, as the client derives
  /// it, compared by scheme, lower-case host, port and namespace. So
  /// `FirebaseDatabase.instance` and `instanceFor(app: app, databaseURL: url)`
  /// with the URL of the same database (with or without a trailing slash, in
  /// any case of the host) share one instance, its settings and its client.
  /// A kept instance is never replaced, also when its client's
  /// `firebase_app_dart` app was deleted: its [client] then makes a new
  /// client with the stored settings.
  ///
  /// Throws a [StateError] when any kept instance of the app's name, for any
  /// database, has an app with other options than [app] (the app was deleted
  /// and created again under the same name with other options): the kept
  /// instances and their settings are not replaced, and no instance is made
  /// for the new options.
  static DartFirebaseDatabase forApp(FirebaseApp app, String? databaseURL) {
    final String key = _instanceKey(app, databaseURL);
    if (_instances.values.any(
      (DartFirebaseDatabase it) => it.app?.name == app.name && it.app != app,
    )) {
      throw _recreatedWithOtherOptions(app.name);
    }
    return _instances[key] ??= DartFirebaseDatabase._(app, databaseURL);
  }

  /// The error of [forApp] and [client] for an app named [appName] that was
  /// deleted and created again with other options.
  static StateError _recreatedWithOtherOptions(String appName) => StateError(
    'The Firebase app "$appName" was deleted and created again with other '
    'options. The FirebaseDatabase instances of the earlier app and their '
    'settings are not replaced: use another app name for the new options, '
    'or restart the app.',
  );

  /// The key of [forApp]: the app name and the database the client would
  /// connect to (the resolution of the client's constructor). A URL the
  /// client cannot parse keys by its text, so that the client reports it at
  /// the first use.
  static String _instanceKey(FirebaseApp app, String? databaseURL) {
    String? url = databaseURL ?? app.options.databaseURL;
    final String projectId = app.options.projectId;
    if ((url == null || url.isEmpty) && projectId.isNotEmpty) {
      url = 'https://$projectId-default-rtdb.firebaseio.com';
    }
    final Uri? uri = url == null || url.isEmpty
        ? null
        : Uri.tryParse(url.contains('://') ? url : 'https://$url');
    if (uri == null || uri.host.isEmpty) {
      return '${app.name}|$databaseURL';
    }
    final String host = uri.host.toLowerCase();
    final bool secure = uri.scheme == 'https' || uri.scheme == 'wss';
    final String namespace = uri.queryParameters['ns'] ?? host.split('.').first;
    final String port = uri.hasPort ? ':${uri.port}' : '';
    return '${app.name}|${secure ? 'https' : 'http'}://$host$port|$namespace';
  }

  /// Closes the clients of the instances of the app named [appName] and
  /// forgets them, so that the next use creates a new client; registered
  /// with `FirebaseApp.registerService`, which runs it when that app is
  /// deleted.
  static Future<void> _closeClientsOf(String appName) async {
    final List<Future<void>> closing = <Future<void>>[
      for (final DartFirebaseDatabase instance in _instances.values)
        if (instance.app?.name == appName) instance._dropClient(),
    ];
    await Future.wait(closing);
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

  /// Whether the client's `firebase_app_dart` app was deleted without the
  /// FlutterFire app (directly, through `firebase_app_dart`), which closed the
  /// client.
  bool get _appDeleted {
    final fs.FirebaseDatabase? client = _client;
    return client != null &&
        !dart_app.Firebase.apps.any(
          (dart_app.FirebaseApp candidate) => identical(candidate, client.app),
        );
  }

  /// The client of this instance's app and database, created on first use
  /// with the settings in force then ([clientFactory],
  /// [DatabaseClientSettings]), for the FlutterFire app that has the name of
  /// [app] now (FlutterFire's `FirebaseDatabase` keeps the app object it was
  /// made with, also after that app was deleted and created again).
  ///
  /// Throws a [StateError] on the registered instance, which has no app, and
  /// when the app was deleted and created again with other options (as
  /// [forApp]); `firebase_core`'s `no-app` exception when the app was deleted
  /// and not created again.
  fs.FirebaseDatabase get client {
    final fs.FirebaseDatabase? existing = _client;
    if (existing != null && !_appDeleted) {
      return existing;
    }
    final FirebaseApp? stored = this.app;
    if (stored == null) {
      throw StateError(
        'This is the registered instance of firebase_database_dart_platform, '
        'which has no app: use FirebaseDatabase.instanceFor(app: ...).',
      );
    }
    final FirebaseApp app = Firebase.app(stored.name);
    if (app != stored) {
      throw _recreatedWithOtherOptions(stored.name);
    }
    final dart_app.FirebaseApp dartApp = dartAppFor(
      app,
      tokenProviderFor: config.tokenProviderFor,
      appCheckProviderFor: config.appCheckProviderFor,
    );
    final DatabaseClientSettings settings = _clientSettings();
    final fs.FirebaseDatabase created = clientFactory(dartApp, settings);
    app.registerService<_DatabaseClients>(
      _DatabaseClients(app.name),
      dispose: (_DatabaseClients clients) => clients.close(),
    );
    _settings = settings;
    return _client = created;
  }

  /// Forgets the client and what it was created with, then closes it.
  Future<void> _dropClient() async {
    final fs.FirebaseDatabase? client = _client;
    _client = null;
    _settings = null;
    await client?.close();
  }

  DatabaseClientSettings _clientSettings() {
    final DatabasePersistenceFactory? persistenceFor = config.persistenceFor;
    final bool persist = persistenceFor != null && _persistenceEnabled != false;
    return DatabaseClientSettings(
      databaseUrl: databaseURL,
      emulatorHost: _emulator,
      persistence: persist
          ? persistenceFor(_cacheSizeBytes ?? _defaultCacheSizeBytes)
          : null,
      logger: _log,
    );
  }

  void _log(fs.DatabaseLogLevel level, String message) {
    final bool always =
        level == fs.DatabaseLogLevel.warning ||
        level == fs.DatabaseLogLevel.error;
    if (always || _logging) {
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
  /// `use` was given a factory and the app did not disable it. Before the
  /// client, each call with `true` without a factory prints a warning and the
  /// data stays in memory; it never throws. See the table of the class.
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

  /// `DatabasePlatform.setLoggingEnabled`: whether the debug and info lines
  /// of the client are printed (warnings and errors always are); read by
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

/// The `firebase_core` service that closes the clients of one app when that
/// app is deleted, on every platform (on Linux the Dart core also deletes the
/// `firebase_app_dart` app, which would close them; elsewhere nothing else
/// does).
final class _DatabaseClients implements FirebaseService {
  _DatabaseClients(this.appName);

  final String appName;

  Future<void> close() => DartFirebaseDatabase._closeClientsOf(appName);
}
