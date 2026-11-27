// The check run after every test of the recreated_app_*_test.dart files:
// every client has the settings of its own instance (the one of its app name
// and database) as they were when the client was created, and no client is
// opened for a database the tests do not name.
//
// It records the settings each instance was given, by putting a recording
// DatabasePlatform in front of the registered one: FlutterFire's
// FirebaseDatabase calls the setters on the delegate that delegateFor
// returns, and the recording delegate forwards each call to the instance of
// this package. It also wraps DartFirebaseDatabase.clientFactory (the one of
// harness.dart) to record, for each client, what its instance had then and
// what the client got. The check does not compare clients with each other,
// so the order of the clients does not matter.

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'recreated_app_pinned_support.dart';

/// The two settings of a client that decide where its data goes: the
/// emulator (`host:port`, null for production) and whether it is on disk.
typedef ClientShape = ({String? emulatorHost, bool onDisk});

/// One client created in the current test: its app name and database, what
/// its instance's settings asked for when it was created, and what it got.
typedef RecordedClient = ({
  String app,
  String database,
  ClientShape expected,
  ClientShape actual,
});

/// The clients created in the current test, in order.
final List<RecordedClient> recordedClients = <RecordedClient>[];

/// The databases the sequences of these files name: [databaseUrl] and
/// [otherUrl], normalised as [_database] does.
final Set<String> namedDatabases = <String>{
  _database(databaseUrl),
  _database(otherUrl),
};

/// The settings given to each instance, by `app|database`, as the instance
/// stores them: a setter call counts only while the instance has no client
/// (after it, the instance refuses or ignores a change). Kept for the whole
/// file, as the instances are.
final Map<String, _Given> _given = <String, _Given>{};

class _Given {
  String? emulatorHost;
  bool? persistenceEnabled;
}

String _database(String url) {
  final String lower = url.toLowerCase();
  return lower.endsWith('/') ? lower.substring(0, lower.length - 1) : lower;
}

String _key(
  String appName,
  String? databaseUrl,
  String? appDatabaseUrl,
  String? projectId,
) {
  final String url =
      databaseUrl ??
      appDatabaseUrl ??
      'https://$projectId-default-rtdb.firebaseio.com';
  return '$appName|${_database(url)}';
}

/// What [recordedClients] (or [clients]) break: a client whose emulator or
/// persistence is not what its instance asked for when the client was
/// created, and a client for a database not in [namedDatabases].
List<String> clientProblems([Iterable<RecordedClient>? clients]) {
  final List<String> problems = <String>[];
  for (final RecordedClient c in clients ?? recordedClients) {
    final String key = '${c.app}|${c.database}';
    if (!namedDatabases.contains(c.database)) {
      problems.add('$key: a client for a database not named');
    }
    if (c.actual.emulatorHost != c.expected.emulatorHost) {
      problems.add(
        '$key: a client on ${c.actual.emulatorHost ?? 'production'}, its '
        'instance asked for ${c.expected.emulatorHost ?? 'production'}',
      );
    }
    if (c.actual.onDisk != c.expected.onDisk) {
      problems.add(
        '$key: a client ${c.actual.onDisk ? 'on disk' : 'in memory'}, its '
        'instance asked for ${c.expected.onDisk ? 'disk' : 'memory'}',
      );
    }
  }
  return problems;
}

/// Records the settings of every instance and every client of each test,
/// and checks [clientProblems] in a `tearDown`, so it runs after every
/// test. Call it after `registerForTests()`.
void checkClientsAfterEveryTest() {
  late DatabaseClientFactory inner;
  late DatabasePlatform registered;
  setUpAll(() {
    registered = DatabasePlatform.instance;
    DatabasePlatform.instance = _RecordingDatabase(registered);
    inner = DartFirebaseDatabase.clientFactory;
    DartFirebaseDatabase.clientFactory =
        (dart_app.FirebaseApp app, DatabaseClientSettings settings) {
          final String key = _key(
            app.name,
            settings.databaseUrl,
            app.options.databaseURL,
            app.options.projectId,
          );
          final _Given? given = _given[key];
          recordedClients.add((
            app: app.name,
            database: key.substring(app.name.length + 1),
            expected: (
              emulatorHost: given?.emulatorHost,
              onDisk:
                  DartFirebaseDatabase.config.persistenceFor != null &&
                  given?.persistenceEnabled != false,
            ),
            actual: (
              emulatorHost: settings.emulatorHost,
              onDisk: settings.persistence != null,
            ),
          ));
          return inner(app, settings);
        };
  });
  tearDownAll(() {
    DartFirebaseDatabase.clientFactory = inner;
    DatabasePlatform.instance = registered;
  });
  setUp(recordedClients.clear);
  tearDown(() => expect(clientProblems(), isEmpty, reason: '${hosts()}'));
}

/// The registered platform, with a [_RecordingDelegate] around each
/// instance it hands to FlutterFire.
class _RecordingDatabase extends DatabasePlatform {
  _RecordingDatabase(this._inner);

  final DatabasePlatform _inner;

  @override
  DatabasePlatform delegateFor({
    required FirebaseApp app,
    String? databaseURL,
  }) => _RecordingDelegate(DartFirebaseDatabase.forApp(app, databaseURL));

  @override
  DatabaseReferencePlatform ref([String? path]) => _inner.ref(path);
}

/// Forwards every call to [_instance] and records in [_given] the setter
/// calls that the instance stores.
class _RecordingDelegate extends DatabasePlatform {
  _RecordingDelegate(this._instance)
    : super(app: _instance.app, databaseURL: _instance.databaseURL);

  final DartFirebaseDatabase _instance;

  _Given get _record => _given.putIfAbsent(
    _key(
      _instance.app!.name,
      _instance.databaseURL,
      _instance.app!.options.databaseURL,
      _instance.app!.options.projectId,
    ),
    _Given.new,
  );

  @override
  void useDatabaseEmulator(String host, int port) {
    final bool started = _instance.started;
    _instance.useDatabaseEmulator(host, port);
    if (!started) {
      _record.emulatorHost = host.contains(':') && !host.startsWith('[')
          ? '[$host]:$port'
          : '$host:$port';
    }
  }

  @override
  void setPersistenceEnabled(bool enabled) {
    final bool started = _instance.started;
    _instance.setPersistenceEnabled(enabled);
    if (!started) {
      _record.persistenceEnabled = enabled;
    }
  }

  @override
  void setPersistenceCacheSizeBytes(int cacheSize) =>
      _instance.setPersistenceCacheSizeBytes(cacheSize);

  @override
  void setLoggingEnabled(bool enabled) => _instance.setLoggingEnabled(enabled);

  @override
  DatabaseReferencePlatform ref([String? path]) => _instance.ref(path);

  @override
  Future<void> goOnline() => _instance.goOnline();

  @override
  Future<void> goOffline() => _instance.goOffline();

  @override
  Future<void> purgeOutstandingWrites() => _instance.purgeOutstandingWrites();
}
