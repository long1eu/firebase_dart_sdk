// The databaseUrl argument together with emulatorHost: the URL gives only the namespace, with the
// emulator's own rule when it has no ?ns=. Without emulatorHost the same URLs keep the production
// rules of parseDatabaseUrl. No connection is opened: only the constructor and databaseUrl run.
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart'
    show FirebaseDatabaseInternal;
import 'package:firebase_database_dart/src/realtime/database_url.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

int _apps = 0;

/// The databaseUrl of an instance built with [url] and [emulatorHost].
String emulatorUrl(String url, String emulatorHost) => fakeTime(
  (FakeTime time) => FirebaseDatabase(
    newTestApp(),
    databaseUrl: url,
    emulatorHost: emulatorHost,
  ).databaseUrl.toString(),
);

/// Expects the constructor to throw an [ArgumentError] on databaseUrl whose message contains
/// [message].
void expectRefused(String url, String message, {String? emulatorHost}) {
  fakeTime((FakeTime time) {
    expect(
      () => FirebaseDatabase(
        newTestApp(),
        databaseUrl: url,
        emulatorHost: emulatorHost,
      ),
      throwsA(
        isA<ArgumentError>()
            .having((ArgumentError e) => e.name, 'name', 'databaseUrl')
            .having(
              (ArgumentError e) => '${e.message}',
              'message',
              contains(message),
            ),
      ),
      reason: url,
    );
  });
}

void main() {
  group('with an emulator host, the URL gives only the namespace', () {
    test('the Android emulator alias', () {
      expect(
        emulatorUrl('http://10.0.2.2:9000?ns=x', '10.0.2.2:9000'),
        'http://10.0.2.2:9000?ns=x',
      );
    });

    test('a LAN address', () {
      expect(
        emulatorUrl('http://192.168.0.57:9000?ns=x', '192.168.0.57:9000'),
        'http://192.168.0.57:9000?ns=x',
      );
    });

    test('a named host with any port', () {
      expect(
        emulatorUrl('http://my-mac.local:9000?ns=x', 'my-mac.local:9000'),
        'http://my-mac.local:9000?ns=x',
      );
    });

    test('localhost without ns is the emulator fallback namespace', () {
      expect(
        emulatorUrl('http://localhost:9000', '127.0.0.1:9000'),
        'http://127.0.0.1:9000?ns=fake-server',
      );
    });

    test('the URL host is not used to connect', () {
      expect(
        emulatorUrl('http://localhost:9000?ns=x', '10.0.2.2:9000'),
        'http://10.0.2.2:9000?ns=x',
      );
      expect(
        emulatorUrl('https://my-mac.local:9000?ns=x', '127.0.0.1:9000'),
        'http://127.0.0.1:9000?ns=x',
      );
    });

    test('user info, a path, a fragment, another query key and a bad ns '
        'still throw', () {
      const String host = '127.0.0.1:9000';
      expectRefused(
        'http://user@10.0.2.2:9000?ns=x',
        'user info',
        emulatorHost: host,
      );
      expectRefused('http://10.0.2.2:9000/a?ns=x', 'path', emulatorHost: host);
      expectRefused(
        'http://10.0.2.2:9000?ns=x#f',
        'fragment',
        emulatorHost: host,
      );
      expectRefused(
        'http://10.0.2.2:9000?ns=x&v=5',
        'but ns',
        emulatorHost: host,
      );
      expectRefused(
        'http://10.0.2.2:9000?ns=Bad_Name',
        'ns must',
        emulatorHost: host,
      );
      expectRefused('ftp://10.0.2.2:9000?ns=x', 'scheme', emulatorHost: host);
      expectRefused('http://10.0.2.2:0?ns=x', 'Port', emulatorHost: host);
      expectRefused(
        'http://lo%63alhost:9000?ns=x',
        'host may only hold',
        emulatorHost: host,
      );
    });

    test('a refusal never shows a password or the URL', () {
      fakeTime((FakeTime time) {
        for (final String url in <String>[
          'http://user:s3cret@localhost:9000?ns=x',
          'http://localhost:9000/s3cret?ns=x',
          'http://localhost:9000?ns=x&s3cret=1',
          'http://localhost:9000?ns=s3cret_',
        ]) {
          expect(
            () => FirebaseDatabase(
              newTestApp(),
              databaseUrl: url,
              emulatorHost: '127.0.0.1:9000',
            ),
            throwsA(
              isA<ArgumentError>().having(
                (ArgumentError e) => '$e',
                'text',
                allOf(isNot(contains('s3cret')), isNot(contains('localhost'))),
              ),
            ),
            reason: url,
          );
        }
      });
    });

    test("without the argument the app's databaseURL gives the namespace", () {
      FirebaseApp appWith(String? databaseURL) => FirebaseApp.withOptions(
        FirebaseOptions(
          apiKey: 'test-key',
          appId: '1:1234567890:dart:test',
          projectId: 'test-project',
          databaseURL: databaseURL,
        ),
        name: 'emulator-url-${databaseURL.hashCode}-${_apps++}',
      );
      Uri urlOf(FirebaseApp app, {String? databaseUrl}) => fakeTime(
        (FakeTime time) => FirebaseDatabase(
          app,
          databaseUrl: databaseUrl,
          emulatorHost: '127.0.0.1:9000',
        ).databaseUrl,
      );
      expect(
        urlOf(appWith('https://db.example.com?ns=other')).toString(),
        'http://127.0.0.1:9000?ns=other',
      );
      expect(
        urlOf(appWith('https://db.example.com')).toString(),
        'http://127.0.0.1:9000?ns=db',
      );
      expect(
        urlOf(
          appWith('https://test-project-default-rtdb.firebaseio.com'),
        ).toString(),
        'http://127.0.0.1:9000?ns=test-project-default-rtdb',
      );
      // An empty argument is no URL: the project's default, not the app's databaseURL.
      expect(
        urlOf(appWith('https://db.example.com'), databaseUrl: '').toString(),
        'http://127.0.0.1:9000?ns=test-project-default-rtdb',
      );
    });

    test('databaseUrl and the connection send the same namespace', () {
      fakeTime((FakeTime time) {
        for (final (String url, String host) in <(String, String)>[
          ('http://localhost:9000', '127.0.0.1:9000'),
          ('ws://my-mac.local:9000', '10.0.2.2:9000'),
          ('https://db.example.com', '[::1]:9000'),
          ('http://10.0.2.2:9000?ns=X', '10.0.2.2:9000'),
        ]) {
          final FirebaseDatabase db = FirebaseDatabase(
            newTestApp(),
            databaseUrl: url,
            emulatorHost: host,
          );
          final Uri connection = RealtimeTarget(
            db.repoInfo,
            useHeaders: true,
          ).connectionUri();
          expect(
            connection.queryParameters['ns'],
            db.databaseUrl.queryParameters['ns'],
            reason: url,
          );
          expect(connection.authority, db.databaseUrl.authority, reason: url);
        }
      });
    });
  });

  group('emulatorUrlNamespace without ns follows the emulator', () {
    for (final (String url, String namespace) in <(String, String)>[
      ('http://my-mac.local:9000', 'my-mac'),
      ('http://Demo.localhost:9000', 'demo'),
      ('http://demo.firebaseio.com', 'demo'),
      ('demo.firebaseio.com', 'demo'),
      (
        'https://demo-default-rtdb.europe-west1.firebasedatabase.app',
        'demo-default-rtdb',
      ),
      ('http://localhost:9000', 'fake-server'),
      ('http://127.0.0.1:9000', 'fake-server'),
      ('http://10.0.2.2:9000', 'fake-server'),
      ('http://192.168.0.57', 'fake-server'),
      ('http://[::1]:9000', 'fake-server'),
      // The emulator would see the Host header `localhost`, a valid name.
      ('http://localhost', 'localhost'),
      // ws and wss, and the default port of each scheme left out of the Host header.
      ('ws://my-mac.local:9000', 'my-mac'),
      ('wss://demo.firebaseio.com', 'demo'),
      ('ws://localhost:9000', 'fake-server'),
      ('http://localhost:80', 'localhost'),
      ('ws://localhost:80', 'localhost'),
      ('https://localhost:443', 'localhost'),
      ('wss://localhost:443', 'localhost'),
      ('http://localhost:443', 'fake-server'),
      ('ws://localhost:443', 'fake-server'),
      ('https://localhost:80', 'fake-server'),
      // A one-label name: its port stays on the only part.
      ('http://my-mac:9000', 'fake-server'),
      ('http://devbox', 'devbox'),
      // A numeric first part: kept below four parts, or above the 32-bit range.
      ('http://1.b.c', '1'),
      ('http://1.b.c.d', 'fake-server'),
      ('http://2147483647.b.c.d', 'fake-server'),
      ('http://2147483648.b.c.d', '2147483648'),
      ('http://4294967296.b.c.d', '4294967296'),
      // Leading zeros count for nothing, as in the emulator's int parser.
      ('http://0000000001.b.c.d', 'fake-server'),
      ('http://00000000001.b.c.d', 'fake-server'),
      ('http://0000000000002147483647.b.c.d', 'fake-server'),
      ('http://0000000000002147483648.b.c.d', '0000000000002147483648'),
      // A bare host is read as https: 443 is dropped, 80 stays.
      ('localhost:443', 'localhost'),
      ('localhost:80', 'fake-server'),
      // A custom domain or a firebase.com host without ns: no longer refused in emulator mode.
      ('https://db.example.com', 'db'),
      ('https://foo.firebase.com', 'foo'),
      // Upper case and percent escapes.
      ('HTTP://MY-MAC.LOCAL:9000', 'my-mac'),
      ('http://localhost:9000?ns=DeMo', 'demo'),
      ('http://localhost:9000?ns=%64emo', 'demo'),
    ]) {
      test(url, () => expect(emulatorUrlNamespace(url), namespace));
    }
  });

  group('without an emulator host the same URLs throw as before', () {
    test('plain http is refused first', () {
      for (final String url in <String>[
        'http://10.0.2.2:9000?ns=x',
        'http://192.168.0.57:9000?ns=x',
        'http://my-mac.local:9000?ns=x',
        'http://localhost:9000',
      ]) {
        expectRefused(url, 'must use https');
      }
    });

    test('over https the host rules still apply', () {
      expectRefused('https://10.0.2.2:9000?ns=x', 'loopback only');
      expectRefused('https://192.168.0.57:9000?ns=x', 'loopback only');
      expectRefused('https://my-mac.local:9000?ns=x', 'port must be 443');
      expectRefused(
        'https://localhost:9000',
        'needs the database name as ?ns=',
      );
    });
  });
}
