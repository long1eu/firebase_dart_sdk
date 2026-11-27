// The databaseUrl argument together with emulatorHost: the URL gives only the namespace, with the
// emulator's own rule when it has no ?ns=. Without emulatorHost the same URLs keep the production
// rules of parseDatabaseUrl. No connection is opened: only the constructor and databaseUrl run.
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/realtime/database_url.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

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
