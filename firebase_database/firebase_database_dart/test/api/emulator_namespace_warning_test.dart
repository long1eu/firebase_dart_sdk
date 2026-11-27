// The warning for an emulator namespace chosen from the URL host (no ?ns=): logged once, at the
// first connection, also after a reconnect; nothing with ?ns=, without a URL or an emulator. Each
// negative case has a positive control in the same test.
// Each test connects to a FakeDatabaseServer; no test answers a pending request.
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/fake_database_server.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart'
    show firebaseDatabaseWithConnection;
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

int _apps = 0;

const Duration _reconnectDelay = Duration(seconds: 1);

/// Builds a database on [server] with [databaseUrl] and [emulatorHost], connects it, drops the
/// connection once, lets it reconnect, and returns the warnings logged.
/// [app] defaults to [newTestApp]; [logger], when given, is called after the warning is recorded.
/// [connected] receives the values of `.info/connected`.
List<String> warningsOverTwoConnections(
  FakeTime time,
  FakeDatabaseServer server, {
  String? databaseUrl,
  String? emulatorHost,
  FirebaseApp? app,
  DatabaseLogger? logger,
  List<Object?>? connected,
}) {
  final List<String> warnings = <String>[];
  final FirebaseDatabase db = firebaseDatabaseWithConnection(
    app ?? newTestApp(),
    databaseUrl: databaseUrl,
    emulatorHost: emulatorHost,
    logger: (DatabaseLogLevel level, String message) {
      if (level == DatabaseLogLevel.warning) {
        warnings.add(message);
      }
      logger?.call(level, message);
    },
    connectionFactory: (ServerActionsDelegate delegate, DatabaseLogger? _) =>
        server.connect(
          delegate,
          reconnectDelay: _reconnectDelay,
          tokens: ProviderTokenSource(
            auth: null,
            forcedRefreshMinInterval: Duration.zero,
            now: DateTime.now,
          ),
        ),
  );
  if (connected != null) {
    db
        .ref('.info/connected')
        .onValue
        .listen((DatabaseEvent e) => connected.add(e.snapshot.value));
  }
  db.goOnline();
  time.elapse(Duration.zero);
  server.dropConnection();
  time.elapse(_reconnectDelay * 2);
  expect(
    server.connectionAttempts,
    2,
    reason: 'connected, dropped, reconnected',
  );
  return warnings;
}

void main() {
  test(
    'a namespace from the URL host warns once, naming it and the emulator host',
    () {
      fakeTime((FakeTime time) {
        final List<String> warnings = warningsOverTwoConnections(
          time,
          FakeDatabaseServer(),
          databaseUrl: 'http://localhost:9000',
          emulatorHost: '127.0.0.1:9000',
        );
        expect(warnings, hasLength(1));
        expect(warnings.single, contains('"fake-server"'));
        expect(warnings.single, contains('127.0.0.1:9000'));
        expect(warnings.single, contains('?ns='));
        expect(warnings.single, isNot(contains('localhost')));
      });
    },
  );

  test('a named host gives its first label, also warned once', () {
    fakeTime((FakeTime time) {
      final List<String> warnings = warningsOverTwoConnections(
        time,
        FakeDatabaseServer(),
        databaseUrl: 'http://my-mac.local:9000',
        emulatorHost: 'my-mac.local:9000',
      );
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('"my-mac"'));
    });
  });

  test('a custom domain without ns warns once, without quoting the URL', () {
    fakeTime((FakeTime time) {
      final List<String> warnings = warningsOverTwoConnections(
        time,
        FakeDatabaseServer(),
        databaseUrl: 'https://db.example.com',
        emulatorHost: '127.0.0.1:9000',
      );
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('"db"'));
      expect(warnings.single, isNot(contains('example')));
    });
  });

  test('ws on its default port warns for the same namespace as http', () {
    fakeTime((FakeTime time) {
      for (final String url in <String>[
        'http://localhost:80',
        'ws://localhost:80',
      ]) {
        final List<String> warnings = warningsOverTwoConnections(
          time,
          FakeDatabaseServer(),
          databaseUrl: url,
          emulatorHost: '127.0.0.1:9000',
        );
        expect(warnings.single, contains('"localhost"'), reason: url);
      }
    });
  });

  test('a URL with ?ns= logs no warning; the same host without it does', () {
    fakeTime((FakeTime time) {
      expect(
        warningsOverTwoConnections(
          time,
          FakeDatabaseServer(),
          databaseUrl: 'http://localhost:9000?ns=fake-server',
          emulatorHost: '127.0.0.1:9000',
        ),
        isEmpty,
      );
      expect(
        warningsOverTwoConnections(
          time,
          FakeDatabaseServer(),
          databaseUrl: 'http://localhost:9000',
          emulatorHost: '127.0.0.1:9000',
        ),
        hasLength(1),
      );
    });
  });

  test('no URL, or a host naming the default database, logs no warning; '
      'another database on the same domain does', () {
    fakeTime((FakeTime time) {
      expect(
        warningsOverTwoConnections(
          time,
          FakeDatabaseServer(),
          emulatorHost: '127.0.0.1:9000',
        ),
        isEmpty,
      );
      expect(
        warningsOverTwoConnections(
          time,
          FakeDatabaseServer(),
          databaseUrl: 'https://test-project-default-rtdb.firebaseio.com',
          emulatorHost: '127.0.0.1:9000',
        ),
        isEmpty,
      );
      expect(
        warningsOverTwoConnections(
          time,
          FakeDatabaseServer(),
          databaseUrl: 'https://test-project-other.firebaseio.com',
          emulatorHost: '127.0.0.1:9000',
        ),
        hasLength(1),
      );
    });
  });

  test('no emulator host logs no warning; the same URL with one does', () {
    fakeTime((FakeTime time) {
      expect(
        warningsOverTwoConnections(
          time,
          FakeDatabaseServer(),
          databaseUrl: 'https://demo.firebaseio.com',
        ),
        isEmpty,
      );
      expect(
        warningsOverTwoConnections(
          time,
          FakeDatabaseServer(),
          databaseUrl: 'https://demo.firebaseio.com',
          emulatorHost: '127.0.0.1:9000',
        ),
        hasLength(1),
      );
    });
  });

  test('without a project id any namespace from the host warns', () {
    fakeTime((FakeTime time) {
      FirebaseApp noProject() => FirebaseApp.withOptions(
        const FirebaseOptions(apiKey: 'k', appId: '1:1:dart:x'),
        name: 'no-project-${_apps++}',
      );
      for (final String url in <String>[
        'https://null-default-rtdb.firebaseio.com',
        'http://my-mac.local:9000',
      ]) {
        final List<String> warnings = warningsOverTwoConnections(
          time,
          FakeDatabaseServer(),
          app: noProject(),
          databaseUrl: url,
          emulatorHost: '127.0.0.1:9000',
        );
        expect(warnings, hasLength(1), reason: url);
      }
    });
  });

  test('a logger that throws does not stop the first connect', () {
    fakeTime((FakeTime time) {
      final List<Object?> connected = <Object?>[];
      final List<String> warnings = warningsOverTwoConnections(
        time,
        FakeDatabaseServer(),
        databaseUrl: 'http://localhost:9000',
        emulatorHost: '127.0.0.1:9000',
        connected: connected,
        logger: (DatabaseLogLevel level, String message) {
          if (level == DatabaseLogLevel.warning) {
            throw StateError('logger');
          }
        },
      );
      expect(warnings, hasLength(1));
      // Connected, dropped, connected again: the first connect reached the Repo.
      expect(connected, <Object?>[false, true, false, true]);
    });
  });
}
