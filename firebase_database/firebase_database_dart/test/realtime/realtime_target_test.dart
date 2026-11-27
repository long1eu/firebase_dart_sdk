// RealtimeTarget: WebSocket URL, upgrade headers, server host (rtdb_protocol.md 2.2 to 2.4; test
// matrix B-2.2, B-2.3, B-2.3a, B-2.4; JS repoinfo.test.ts and websocketconnection.test.ts; iOS
// FConnectionHostTest.m and FRealtime.m:44). The hostile-host and token-scope tables are
// test/security/hosts_test.dart.
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/realtime/database_url.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:test/test.dart';

RealtimeTarget vmTarget(RepoInfo info) =>
    RealtimeTarget(info, useHeaders: true, userAgent: 'Firebase/5/test/dart');

RealtimeTarget webTarget(RepoInfo info) =>
    RealtimeTarget(info, useHeaders: false);

void main() {
  final RepoInfo plain = parseDatabaseUrl('https://test-ns.firebaseio.com');
  final RepoInfo regional = parseDatabaseUrl(
    'https://db.europe-west1.firebasedatabase.app',
  );
  final RepoInfo emulator = emulatorDatabase(
    '127.0.0.1',
    9000,
    namespace: 'demo-test-default-rtdb',
  );

  group('connectionUri (B-2.3)', () {
    test('exact string with ls (JS repoinfo.test.ts:30)', () {
      expect(
        vmTarget(plain).connectionUri(lastSessionId: 'test').toString(),
        'wss://test-ns.firebaseio.com/.ws?v=5&ls=test',
      );
    });

    test('a first connection has only v', () {
      expect(
        vmTarget(plain).connectionUri().toString(),
        'wss://test-ns.firebaseio.com/.ws?v=5',
      );
    });

    test('web: parameter order v, ls, ac, p, ns', () {
      final RealtimeTarget target = webTarget(regional);
      expect(
        target
            .connectionUri(
              lastSessionId: 'S1',
              appId: '1:2:web:3',
              appCheckToken: 'AC.tok-en_',
            )
            .toString(),
        'wss://db.europe-west1.firebasedatabase.app/.ws'
        '?v=5&ls=S1&ac=AC.tok-en_&p=1%3A2%3Aweb%3A3&ns=db',
      );
    });

    test('web: p carries the app id (JS websocketconnection.test.ts:24)', () {
      final Uri uri = webTarget(plain).connectionUri(appId: 'app-id');
      expect(uri.queryParameters['p'], 'app-id');
    });

    test(
      'web: no p for an empty app id (JS websocketconnection.test.ts:35)',
      () {
        final Uri uri = webTarget(
          plain,
        ).connectionUri(appId: '', appCheckToken: '');
        expect(uri.queryParameters.containsKey('p'), isFalse);
        expect(uri.queryParameters.containsKey('ac'), isFalse);
      },
    );

    test('VM: never ac or p in the URL (they go in headers, T25)', () {
      final Uri uri = vmTarget(
        plain,
      ).connectionUri(appId: '1:2:web:3', appCheckToken: 'secret-app-check');
      expect(uri.toString(), 'wss://test-ns.firebaseio.com/.ws?v=5');
    });

    test('query values are percent-encoded (T6)', () {
      final Uri uri = webTarget(
        plain,
      ).connectionUri(lastSessionId: 'a&ns=evil', appCheckToken: 'x y+z=');
      expect(uri.query, 'v=5&ls=a%26ns%3Devil&ac=x+y%2Bz%3D');
      expect(uri.queryParametersAll['ns'], isNull);
    });

    test('ns rule: none for a plain <ns>.firebaseio.com', () {
      expect(vmTarget(plain).connectionUri().queryParameters['ns'], isNull);
    });

    test('ns rule: sent when ns differs from the first label', () {
      final RepoInfo info = parseDatabaseUrl(
        'https://test-ns.firebaseio.com?ns=other',
      );
      expect(vmTarget(info).connectionUri().queryParameters['ns'], 'other');
    });

    test('ns rule: sent for a deeper firebaseio.com host', () {
      final RepoInfo info = parseDatabaseUrl('https://a.b.firebaseio.com');
      expect(vmTarget(info).connectionUri().queryParameters['ns'], 'a');
    });

    test('ns rule: sent for firebasedatabase.app and custom domains', () {
      expect(vmTarget(regional).connectionUri().queryParameters['ns'], 'db');
      final RepoInfo custom = parseDatabaseUrl('https://db.example.com?ns=c');
      expect(vmTarget(custom).connectionUri().queryParameters['ns'], 'c');
    });

    test(
      'ns rule: sent after a server host was accepted (RepoInfo.ts:103)',
      () {
        final RealtimeTarget target = vmTarget(plain);
        expect(
          target.acceptServerHost('s-usc1a-nss-2001.firebaseio.com'),
          isTrue,
        );
        expect(
          target.connectionUri().toString(),
          'wss://s-usc1a-nss-2001.firebaseio.com/.ws?v=5&ns=test-ns',
        );
        target.forgetServerHost();
        expect(
          target.connectionUri().toString(),
          'wss://test-ns.firebaseio.com/.ws?v=5',
        );
      },
    );

    test('emulator: ws, host:port, ns always (B-2.4; probe: no ns gives '
        'fake-server on 127.0.0.1)', () {
      expect(
        vmTarget(emulator).connectionUri().toString(),
        'ws://127.0.0.1:9000/.ws?v=5&ns=demo-test-default-rtdb',
      );
    });

    test('a cloud workstation emulator uses wss', () {
      final RepoInfo info = emulatorDatabase(
        '9000-x.cloudworkstations.dev',
        443,
        namespace: 'n',
      );
      expect(
        vmTarget(info).connectionUri().toString(),
        'wss://9000-x.cloudworkstations.dev:443/.ws?v=5&ns=n',
      );
    });

    test('IPv6 emulator host is bracketed', () {
      final RepoInfo info = emulatorDatabase('::1', 9000, namespace: 'n');
      expect(
        vmTarget(info).connectionUri().toString(),
        'ws://[::1]:9000/.ws?v=5&ns=n',
      );
    });

    test('never has user info', () {
      expect(vmTarget(plain).connectionUri().userInfo, isEmpty);
    });
  });

  group('connectionHeaders (B-2.3a)', () {
    test('VM: User-Agent, X-Firebase-GMPID, X-Firebase-AppCheck', () {
      expect(
        vmTarget(
          plain,
        ).connectionHeaders(appId: '1:2:web:3', appCheckToken: 'ac'),
        <String, String>{
          'User-Agent': 'Firebase/5/test/dart',
          'X-Firebase-GMPID': '1:2:web:3',
          'X-Firebase-AppCheck': 'ac',
        },
      );
    });

    test('VM: absent values leave their header out', () {
      expect(
        RealtimeTarget(plain, useHeaders: true).connectionHeaders(appId: ''),
        isEmpty,
      );
    });

    test('web: no headers at all', () {
      expect(
        webTarget(plain).connectionHeaders(appId: 'a', appCheckToken: 'ac'),
        isEmpty,
      );
    });
  });

  group('server host (B-2.2; iOS FConnectionHostTest.m)', () {
    test('internalHost starts as the configured host', () {
      expect(vmTarget(plain).internalHost, 'test-ns.firebaseio.com');
      expect(vmTarget(emulator).internalHost, '127.0.0.1:9000');
    });

    test('a valid hello host is saved (U-I22, :164)', () {
      final RealtimeTarget target = vmTarget(plain);
      expect(
        target.acceptServerHost('s-usc1a-nss-2001.firebaseio.com'),
        isTrue,
      );
      expect(target.internalHost, 's-usc1a-nss-2001.firebaseio.com');
    });

    test(
      'an invalid hello host is ignored and keeps the saved host (:145)',
      () {
        final RealtimeTarget target = vmTarget(plain);
        target.acceptServerHost('s-1.firebaseio.com');
        expect(target.acceptServerHost('evil.example'), isFalse);
        expect(target.internalHost, 's-1.firebaseio.com');
      },
    );

    test('forgetServerHost restores the configured host (U-I21)', () {
      final RealtimeTarget target = vmTarget(plain);
      target.acceptServerHost('s-1.firebaseio.com');
      target.forgetServerHost();
      expect(target.internalHost, 'test-ns.firebaseio.com');
    });

    test('the configured host is accepted and brings back its port', () {
      final RealtimeTarget target = vmTarget(
        parseDatabaseUrl('https://localhost:9443?ns=n'),
      );
      expect(target.acceptServerHost('localhost'), isTrue);
      expect(
        target.connectionUri().toString(),
        'wss://localhost:9443/.ws?v=5&ns=n',
      );
    });

    test('upper case is lowercased', () {
      final RealtimeTarget target = vmTarget(plain);
      expect(target.acceptServerHost('S-X.FIREBASEIO.COM'), isTrue);
      expect(target.internalHost, 's-x.firebaseio.com');
    });

    test('a regional database accepts a firebasedatabase.app shard', () {
      final RealtimeTarget target = vmTarget(regional);
      expect(
        target.acceptServerHost('s-ew1.europe-west1.firebasedatabase.app'),
        isTrue,
      );
    });

    test('the emulator never changes host (Connection.ts:348-351; T1)', () {
      final RealtimeTarget target = vmTarget(emulator);
      expect(target.acceptServerHost('127.0.0.1'), isFalse);
      expect(target.acceptServerHost('s-1.firebaseio.com'), isFalse);
      expect(target.internalHost, '127.0.0.1:9000');
    });

    test('the server host lives in this target only (U-I31 adapted: no '
        'cache shared by a second target)', () {
      final RealtimeTarget first = vmTarget(plain);
      first.acceptServerHost('s-1.firebaseio.com');
      expect(vmTarget(plain).internalHost, 'test-ns.firebaseio.com');
    });
  });

  group('construction and toString', () {
    test('a plain-text RepoInfo that is not the emulator is refused '
        '(T3; review M1 (a))', () {
      expect(
        () => RealtimeTarget(
          const RepoInfo(
            host: 'x.firebaseio.com',
            namespace: 'x',
            secure: false,
          ),
          useHeaders: true,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            allOf(
              contains('http://x.firebaseio.com is plain text'),
              contains('only the Realtime Database emulator accepts'),
              contains('https://'),
              contains('emulatorHost'),
            ),
          ),
        ),
      );
    });

    test('toString shows the configured URL only (T8)', () {
      final RealtimeTarget target = vmTarget(plain);
      target.acceptServerHost('s-1.firebaseio.com');
      expect(
        target.toString(),
        'RealtimeTarget(https://test-ns.firebaseio.com)',
      );
      expect(
        vmTarget(emulator).toString(),
        'RealtimeTarget(http://127.0.0.1:9000)',
      );
    });
  });
}
