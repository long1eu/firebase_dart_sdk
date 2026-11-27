// Database URL parsing and the emulator helpers (rtdb_protocol.md 2.1, 2.4; test matrix B-2.1,
// B-2.4; Android ParseUrlTest, JS parser.test.ts, iOS FRealtime.m:27). The refusal table of
// threat model T6 is test/security/url_test.dart.
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/realtime/database_url.dart';
import 'package:test/test.dart';

void expectInfo(
  RepoInfo info, {
  required String host,
  required String namespace,
  required bool secure,
  bool emulator = false,
}) {
  expect(info.host, host, reason: 'host');
  expect(info.namespace, namespace, reason: 'namespace');
  expect(info.secure, secure, reason: 'secure');
  expect(info.isUsingEmulator, emulator, reason: 'isUsingEmulator');
}

void main() {
  group('parseDatabaseUrl (B-2.1)', () {
    test('a firebaseio.com URL takes the namespace from the first label', () {
      expectInfo(
        parseDatabaseUrl('https://test-ns.firebaseio.com'),
        host: 'test-ns.firebaseio.com',
        namespace: 'test-ns',
        secure: true,
      );
    });

    test('a regional firebasedatabase.app URL takes the first label', () {
      expectInfo(
        parseDatabaseUrl('https://my-db.europe-west1.firebasedatabase.app'),
        host: 'my-db.europe-west1.firebasedatabase.app',
        namespace: 'my-db',
        secure: true,
      );
    });

    test('a trailing slash is the same URL (Android ParseUrlTest:67)', () {
      final RepoInfo withSlash = parseDatabaseUrl('https://a.firebaseio.com/');
      final RepoInfo without = parseDatabaseUrl('https://a.firebaseio.com');
      expect(withSlash.host, without.host);
      expect(withSlash.namespace, without.namespace);
    });

    test('a bare host is read as https (2.1)', () {
      expectInfo(
        parseDatabaseUrl('bare.firebaseio.com'),
        host: 'bare.firebaseio.com',
        namespace: 'bare',
        secure: true,
      );
    });

    test('wss is accepted like https (JS parser.test.ts:21, adapted)', () {
      expectInfo(
        parseDatabaseUrl('wss://w.firebaseio.com'),
        host: 'w.firebaseio.com',
        namespace: 'w',
        secure: true,
      );
    });

    test('the host and the scheme are lowercased', () {
      expectInfo(
        parseDatabaseUrl('HTTPS://My-NS.FirebaseIO.com'),
        host: 'my-ns.firebaseio.com',
        namespace: 'my-ns',
        secure: true,
      );
    });

    test('ns overrides the first label (2.1 step 5) and is lowercased', () {
      expectInfo(
        parseDatabaseUrl('https://a.firebaseio.com?ns=Other-NS'),
        host: 'a.firebaseio.com',
        namespace: 'other-ns',
        secure: true,
      );
    });

    test('a custom domain with ns (Android ParseUrlTest:74, adapted)', () {
      expectInfo(
        parseDatabaseUrl('https://db.example.com/?ns=mrschmidt'),
        host: 'db.example.com',
        namespace: 'mrschmidt',
        secure: true,
      );
    });

    test('an explicit port 443 is dropped from the host', () {
      expectInfo(
        parseDatabaseUrl('https://a.firebaseio.com:443'),
        host: 'a.firebaseio.com',
        namespace: 'a',
        secure: true,
      );
    });

    test('a loopback host keeps any port, secure (a TLS front)', () {
      expectInfo(
        parseDatabaseUrl('https://localhost:9443?ns=local'),
        host: 'localhost:9443',
        namespace: 'local',
        secure: true,
      );
      expectInfo(
        parseDatabaseUrl('https://127.0.0.1:9443?ns=local'),
        host: '127.0.0.1:9443',
        namespace: 'local',
        secure: true,
      );
      expectInfo(
        parseDatabaseUrl('https://[::1]:9443?ns=local'),
        host: '[::1]:9443',
        namespace: 'local',
        secure: true,
      );
    });

    test('an empty query is no query', () {
      expect(parseDatabaseUrl('https://a.firebaseio.com/?').namespace, 'a');
    });

    test('http points to the emulator API (Android ParseUrlTest:84, the '
        'opposite decision: no plain-text production URL, T3)', () {
      expect(
        () => parseDatabaseUrl('http://gsoltis.fblocal.com:9000'),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('emulatorHost'),
          ),
        ),
      );
    });

    test('a path is refused (Android ParseUrlTest:32 parses one; getDatabase '
        'needs an empty path, api/Database.ts:163-168)', () {
      expect(
        () => parseDatabaseUrl('https://gsoltis.firebaseio.com/foo/bar'),
        throwsFormatException,
      );
    });

    test('firebase.com is refused (2.1 step 6)', () {
      expect(
        () => parseDatabaseUrl('https://old.firebase.com'),
        throwsFormatException,
      );
    });

    test('a custom domain without ns is refused', () {
      expect(
        () => parseDatabaseUrl('https://db.example.com'),
        throwsFormatException,
      );
    });

    test('a bare firebaseio.com host has no namespace', () {
      expect(
        () => parseDatabaseUrl('https://firebaseio.com'),
        throwsFormatException,
      );
    });
  });

  group('defaultDatabase (1.1)', () {
    test('is <projectId>-default-rtdb.firebaseio.com', () {
      expectInfo(
        defaultDatabase('demo-test'),
        host: 'demo-test-default-rtdb.firebaseio.com',
        namespace: 'demo-test-default-rtdb',
        secure: true,
      );
    });

    test('refuses a project id that is not a label', () {
      for (final String bad in <String>[
        '',
        'Demo',
        'a_b',
        'a.b',
        '-a',
        'a' * 51,
      ]) {
        expect(() => defaultDatabase(bad), throwsArgumentError, reason: bad);
      }
    });

    test('accepts the longest id whose namespace fits 63 characters', () {
      final String id = 'a' * 50;
      expect(defaultDatabase(id).namespace.length, 63);
    });
  });

  group('emulatorDatabase (B-2.4)', () {
    test('is plain text on host:port with the namespace (Android '
        'ParseUrlTest:95)', () {
      expectInfo(
        emulatorDatabase('10.0.2.2', 9000, namespace: 'myns'),
        host: '10.0.2.2:9000',
        namespace: 'myns',
        secure: false,
        emulator: true,
      );
    });

    test('a cloud workstation is secure (util:src/url.ts:22-36)', () {
      expectInfo(
        emulatorDatabase('9000-x.cloudworkstations.dev', 443, namespace: 'n'),
        host: '9000-x.cloudworkstations.dev:443',
        namespace: 'n',
        secure: true,
        emulator: true,
      );
    });

    test('a host merely containing the workstation domain is not secure', () {
      expect(
        emulatorDatabase(
          'cloudworkstations.dev.example.com',
          9000,
          namespace: 'n',
        ).secure,
        isFalse,
      );
      expect(
        emulatorDatabase('xcloudworkstations.dev', 9000, namespace: 'n').secure,
        isFalse,
      );
    });

    test('IPv6 hosts are bracketed, with or without brackets given', () {
      expect(emulatorDatabase('::1', 9000, namespace: 'n').host, '[::1]:9000');
      expect(
        emulatorDatabase('[::1]', 9000, namespace: 'n').host,
        '[::1]:9000',
      );
    });

    test('the host and the namespace are lowercased (probe: ns is matched '
        'case-insensitively)', () {
      final RepoInfo info = emulatorDatabase(
        'LocalHost',
        9000,
        namespace: 'Q4',
      );
      expect(info.host, 'localhost:9000');
      expect(info.namespace, 'q4');
    });

    test('refuses an empty or malformed host, a bad port, a bad namespace', () {
      expect(
        () => emulatorDatabase('', 9000, namespace: 'n'),
        throwsArgumentError,
      );
      expect(
        () => emulatorDatabase('a@b', 9000, namespace: 'n'),
        throwsArgumentError,
      );
      expect(
        () => emulatorDatabase('localhost:9000', 9000, namespace: 'n'),
        throwsArgumentError,
      );
      expect(
        () => emulatorDatabase('localhost', 0, namespace: 'n'),
        throwsArgumentError,
      );
      expect(
        () => emulatorDatabase('localhost', 65536, namespace: 'n'),
        throwsArgumentError,
      );
      for (final String ns in <String>[
        '',
        'demo_test',
        'a b',
        'a/b',
        'x' * 64,
      ]) {
        expect(
          () => emulatorDatabase('localhost', 9000, namespace: ns),
          throwsArgumentError,
          reason: ns,
        );
      }
    });
  });

  group('parseEmulatorHost (2.4, FIREBASE_DATABASE_EMULATOR_HOST)', () {
    test('host:port', () {
      expect(parseEmulatorHost('127.0.0.1:9000'), (
        host: '127.0.0.1',
        port: 9000,
      ));
      expect(parseEmulatorHost('Emu.Local:65535'), (
        host: 'emu.local',
        port: 65535,
      ));
    });

    test('a bracketed IPv6 host comes back without brackets', () {
      expect(parseEmulatorHost('[::1]:9000'), (host: '::1', port: 9000));
    });

    test('refuses anything else', () {
      for (final String bad in <String>[
        '',
        'localhost',
        'localhost:',
        ':9000',
        'localhost:0',
        'localhost:65536',
        'localhost:+90',
        'localhost:9000/',
        'http://localhost:9000',
        'user@localhost:9000',
        '::1:9000',
        '[::1]9000',
        '[::1',
        'local host:9000',
      ]) {
        expect(
          () => parseEmulatorHost(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });

  group('host helpers', () {
    test('splitHostPort and joinHostPort round trip', () {
      for (final String value in <String>[
        'a.firebaseio.com',
        'localhost:9000',
        '[::1]:9000',
        '[::1]',
      ]) {
        final ({String host, int? port}) parts = splitHostPort(value);
        expect(joinHostPort(parts.host, parts.port), value);
      }
    });

    test('isLoopbackHost', () {
      for (final String host in <String>[
        'localhost',
        '127.0.0.1',
        '127.255.0.9',
        '::1',
        '0:0:0:0:0:0:0:1',
      ]) {
        expect(isLoopbackHost(host), isTrue, reason: host);
      }
      for (final String host in <String>[
        '127.0.0.1.evil.example',
        '128.0.0.1',
        '127.1',
        '127.000.0.1',
        '127.0.0.256',
        '::2',
        '::ffff:127.0.0.1',
        'localhost.evil.example',
        '',
      ]) {
        expect(isLoopbackHost(host), isFalse, reason: host);
      }
    });

    test('isDnsHostName', () {
      for (final String host in <String>[
        'a',
        'a.firebaseio.com',
        's-usc1a-nss-2001.firebaseio.com',
        'xn--bcher-kva.example',
        '${'a' * 63}.com',
      ]) {
        expect(isDnsHostName(host), isTrue, reason: host);
      }
      for (final String host in <String>[
        '',
        'a.',
        '.a',
        'a..b',
        '-a.com',
        'a-.com',
        'a_b.com',
        'A.com',
        '${'a' * 64}.com',
        '${List<String>.filled(127, 'a').join('.')}.b',
        '1.2.3.4',
        'a.b:1',
        'a/b',
        'a@b',
      ]) {
        expect(isDnsHostName(host), isFalse, reason: host);
      }
    });
  });
}
