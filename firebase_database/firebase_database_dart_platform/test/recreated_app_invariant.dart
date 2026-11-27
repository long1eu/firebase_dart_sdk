// The check run after every test of the recreated_app_*_test.dart files: an
// instance, once made for an app name and a database, is never replaced by
// one without its settings, and no client is opened for a database the
// tests do not name.
//
// It wraps DartFirebaseDatabase.clientFactory (the one of harness.dart) to
// record, for each client, the app name and the database it connects to.

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'recreated_app_pinned_support.dart';

/// One client created in the current test.
typedef RecordedClient = ({
  String app,
  String database,
  DatabaseClientSettings settings,
});

/// The clients created in the current test, in order.
final List<RecordedClient> recordedClients = <RecordedClient>[];

/// The databases the sequences of these files name: [databaseUrl] and
/// [otherUrl], normalised as [_database] does.
final Set<String> namedDatabases = <String>{
  _database(databaseUrl),
  _database(otherUrl),
};

String _database(String url) {
  final String lower = url.toLowerCase();
  return lower.endsWith('/') ? lower.substring(0, lower.length - 1) : lower;
}

String _databaseOf(dart_app.FirebaseApp app, DatabaseClientSettings s) =>
    _database(
      s.databaseUrl ??
          app.options.databaseURL ??
          'https://${app.options.projectId}-default-rtdb.firebaseio.com',
    );

/// What breaks the rule in [recordedClients]: per app name and database, a
/// client without the emulator after one with it, a client on disk after
/// one in memory (persistence turned off), and a client for a database not
/// in [namedDatabases].
List<String> clientProblems() {
  final List<String> problems = <String>[];
  final Set<String> hadEmulator = <String>{};
  final Set<String> hadMemory = <String>{};
  for (final RecordedClient c in recordedClients) {
    if (!namedDatabases.contains(c.database)) {
      problems.add('${c.app}: a client for ${c.database}, not named');
    }
    final String key = '${c.app}|${c.database}';
    if (hadEmulator.contains(key) && c.settings.emulatorHost == null) {
      problems.add('$key: a production client after an emulator one');
    }
    if (hadMemory.contains(key) && c.settings.persistence != null) {
      problems.add('$key: a client on disk after one in memory');
    }
    if (c.settings.emulatorHost != null) {
      hadEmulator.add(key);
    }
    if (c.settings.persistence == null) {
      hadMemory.add(key);
    }
  }
  return problems;
}

/// Records every client of each test and checks [clientProblems] in a
/// `tearDown`, so it runs after every test. Call it after
/// `registerForTests()`.
void checkClientsAfterEveryTest() {
  late DatabaseClientFactory inner;
  setUpAll(() {
    inner = DartFirebaseDatabase.clientFactory;
    DartFirebaseDatabase.clientFactory =
        (dart_app.FirebaseApp app, DatabaseClientSettings settings) {
          recordedClients.add((
            app: app.name,
            database: _databaseOf(app, settings),
            settings: settings,
          ));
          return inner(app, settings);
        };
  });
  setUp(recordedClients.clear);
  tearDown(() => expect(clientProblems(), isEmpty, reason: '${hosts()}'));
}
