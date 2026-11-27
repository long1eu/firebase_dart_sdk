// Threat model T1 (server-chosen host) and T3 (token scope) at the level of RealtimeTarget. The
// connection-level halves (a fake server sending these hellos and resets, the reset storm, the
// upgrade redirect) belong to the owners of connection.dart and the transport, in their own
// files.
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/realtime/database_url.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:test/test.dart';

RealtimeTarget target(RepoInfo info, {bool useHeaders = true}) =>
    RealtimeTarget(info, useHeaders: useHeaders);

void main() {
  final RepoInfo production = parseDatabaseUrl('https://x.firebaseio.com');

  group('server host (T1)', () {
    const List<String> refused = <String>[
      'evil.example',
      's-x.firebaseio.com@evil.example',
      's-x.firebaseio.com:444',
      's-x.firebaseio.com:443',
      's-x.firebaseio.com/x',
      's-x.firebaseio.com?x',
      's-x.firebaseio.com#',
      's-x.firebaseio.com.',
      's-x.firebaseio.com.evil.example',
      'xfirebaseio.com',
      'firebaseio.com',
      'firebasedatabase.app',
      'evil-firebaseio.com',
      '.firebaseio.com',
      's-x..firebaseio.com',
      's_x.firebaseio.com',
      's-x.firebaseio.com\u0000',
      ' s-x.firebaseio.com',
      'ß.firebaseio.com',
      '[::1]',
      '127.0.0.1',
      '',
    ];
    for (final String host in refused) {
      test(
        'refuses ${host.isEmpty ? '(empty)' : Uri.encodeFull(host)} and keeps '
        'the next URL on the current host',
        () {
          final RealtimeTarget t = target(production);
          expect(t.acceptServerHost(host), isFalse);
          final Uri next = t.connectionUri(lastSessionId: 's');
          expect(next.host, 'x.firebaseio.com');
          expect(next.hasPort, isFalse);
          expect(next.userInfo, isEmpty);
          expect(t.internalHost, 'x.firebaseio.com');
        },
      );
    }

    test('a host longer than 253 characters is refused', () {
      final String long =
          '${List<String>.filled(60, 'abc').join('.')}.firebaseio.com';
      expect(long.length, greaterThan(253));
      expect(target(production).acceptServerHost(long), isFalse);
    });

    test('a refused host keeps a previously accepted one', () {
      final RealtimeTarget t = target(production);
      expect(t.acceptServerHost('s-1.firebaseio.com'), isTrue);
      expect(t.acceptServerHost('s-1.firebaseio.com@evil.example'), isFalse);
      expect(t.connectionUri().host, 's-1.firebaseio.com');
    });

    test('upper case is lowercased and accepted', () {
      final RealtimeTarget t = target(production);
      expect(t.acceptServerHost('S-X.FIREBASEIO.COM'), isTrue);
      expect(t.connectionUri().host, 's-x.firebaseio.com');
    });

    test('a custom domain accepts itself and Google shards only', () {
      final RealtimeTarget t = target(
        parseDatabaseUrl('https://db.example.com?ns=n'),
      );
      expect(t.acceptServerHost('db.example.com'), isTrue);
      expect(t.acceptServerHost('other.example.com'), isFalse);
      expect(t.acceptServerHost('s-1.firebaseio.com'), isTrue);
    });

    test('the emulator ignores h and r', () {
      final RealtimeTarget t = target(
        emulatorDatabase('10.0.0.5', 9000, namespace: 'n'),
      );
      for (final String host in <String>[
        's-1.firebaseio.com',
        '10.0.0.5',
        'x.firebaseio.com',
      ]) {
        expect(t.acceptServerHost(host), isFalse, reason: host);
      }
      expect(t.connectionUri().toString(), 'ws://10.0.0.5:9000/.ws?v=5&ns=n');
    });

    test('the WebSocket scheme cannot be changed by a host', () {
      final RealtimeTarget t = target(production);
      t.acceptServerHost('s-1.firebaseio.com');
      expect(t.connectionUri().scheme, 'wss');
    });
  });

  group('token scope (T3)', () {
    test('production: TLS to the configured host only', () {
      final RealtimeTarget t = target(production);
      expect(
        t.mayReceiveTokens(Uri.parse('wss://x.firebaseio.com/.ws?v=5')),
        isTrue,
      );
      expect(
        t.mayReceiveTokens(Uri.parse('https://x.firebaseio.com/a.json')),
        isTrue,
      );
      expect(
        t.mayReceiveTokens(Uri.parse('wss://X.FIREBASEIO.COM:443/.ws')),
        isTrue,
      );
      for (final String url in <String>[
        'ws://x.firebaseio.com/.ws',
        'http://x.firebaseio.com/a.json',
        'http://x.firebaseio.com:443/a.json',
        'https://x.firebaseio.com:444/a.json',
        'wss://y.firebaseio.com/.ws',
        'wss://x.firebaseio.com.evil.example/.ws',
        'https://u:p@x.firebaseio.com/a.json',
        'https://evil.example/a.json',
        'https://127.0.0.1/a.json',
      ]) {
        expect(t.mayReceiveTokens(Uri.parse(url)), isFalse, reason: url);
      }
    });

    test('production: an accepted server host over TLS on 443 only', () {
      final RealtimeTarget t = target(production);
      expect(
        t.mayReceiveTokens(Uri.parse('wss://s-1.firebaseio.com/.ws')),
        isFalse,
      );
      t.acceptServerHost('s-1.firebaseio.com');
      expect(
        t.mayReceiveTokens(Uri.parse('wss://s-1.firebaseio.com/.ws')),
        isTrue,
      );
      expect(
        t.mayReceiveTokens(Uri.parse('ws://s-1.firebaseio.com/.ws')),
        isFalse,
      );
      expect(
        t.mayReceiveTokens(Uri.parse('wss://s-1.firebaseio.com:8443/.ws')),
        isFalse,
      );
      t.forgetServerHost();
      expect(
        t.mayReceiveTokens(Uri.parse('wss://s-1.firebaseio.com/.ws')),
        isFalse,
      );
    });

    test('every URL the target builds may carry tokens', () {
      final RealtimeTarget t = target(production, useHeaders: false);
      expect(t.mayReceiveTokens(t.connectionUri()), isTrue);
      t.acceptServerHost('s-1.firebaseio.com');
      expect(t.mayReceiveTokens(t.connectionUri()), isTrue);
    });

    test('emulator on a non-loopback host gets the tokens at its exact '
        'host and port, nothing else does', () {
      final RealtimeTarget t = target(
        emulatorDatabase('10.0.0.5', 9000, namespace: 'n'),
      );
      expect(t.mayReceiveTokens(Uri.parse('ws://10.0.0.5:9000/.ws')), isTrue);
      expect(
        t.mayReceiveTokens(Uri.parse('http://10.0.0.5:9000/a.json')),
        isTrue,
      );
      expect(t.mayReceiveTokens(t.connectionUri()), isTrue);
      for (final String url in <String>[
        'ws://10.0.0.5:9001/.ws',
        'ws://10.0.0.5/.ws',
        'http://10.0.0.5/a.json',
        'ws://10.0.0.6:9000/.ws',
        'ws://127.0.0.1.evil.example:9000/.ws',
        'ws://u@10.0.0.5:9000/.ws',
        'wss://10.0.0.5:9000/.ws',
        'https://x.firebaseio.com/a.json',
      ]) {
        expect(t.mayReceiveTokens(Uri.parse(url)), isFalse, reason: url);
      }
    });

    test('emulator on loopback: another port gets nothing', () {
      final RealtimeTarget t = target(
        emulatorDatabase('127.0.0.1', 9000, namespace: 'n'),
      );
      expect(t.mayReceiveTokens(Uri.parse('ws://127.0.0.1:9000/.ws')), isTrue);
      expect(t.mayReceiveTokens(Uri.parse('ws://127.0.0.1:9001/.ws')), isFalse);
      expect(t.mayReceiveTokens(Uri.parse('ws://localhost:9000/.ws')), isFalse);
    });

    test('a secure emulator (cloud workstation) needs TLS', () {
      final RealtimeTarget t = target(
        emulatorDatabase('9000-x.cloudworkstations.dev', 443, namespace: 'n'),
      );
      expect(
        t.mayReceiveTokens(Uri.parse('wss://9000-x.cloudworkstations.dev/.ws')),
        isTrue,
      );
      expect(
        t.mayReceiveTokens(
          Uri.parse('ws://9000-x.cloudworkstations.dev:443/.ws'),
        ),
        isFalse,
      );
    });

    test(
      'plain-text production URLs never become a target (review M1 (a))',
      () {
        for (final String url in <String>[
          'http://x.firebaseio.com:443',
          'http://x.firebaseio.com',
          'ws://x.firebaseio.com',
        ]) {
          expect(
            () => parseDatabaseUrl(url),
            throwsFormatException,
            reason: url,
          );
        }
        expect(
          () => RealtimeTarget(
            const RepoInfo(
              host: 'x.firebaseio.com',
              namespace: 'x',
              secure: false,
            ),
            useHeaders: true,
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('App Check token placement (T25)', () {
    test('VM: header only, never in the URL', () {
      final RealtimeTarget t = target(production);
      expect(
        t.connectionUri(appCheckToken: 'ac-marker').toString(),
        isNot(contains('ac-marker')),
      );
      expect(
        t.connectionHeaders(appCheckToken: 'ac-marker')['X-Firebase-AppCheck'],
        'ac-marker',
      );
    });

    test('web: in the URL, no headers', () {
      final RealtimeTarget t = target(production, useHeaders: false);
      expect(
        t.connectionUri(appCheckToken: 'ac-marker').queryParameters['ac'],
        'ac-marker',
      );
      expect(t.connectionHeaders(appCheckToken: 'ac-marker'), isEmpty);
    });

    test('toString shows no query, token or server host (T8)', () {
      final RealtimeTarget t = target(production);
      t.acceptServerHost('s-1.firebaseio.com');
      t.connectionUri(appCheckToken: 'ac-marker', lastSessionId: 'ls-marker');
      expect(t.toString(), 'RealtimeTarget(https://x.firebaseio.com)');
    });
  });
}
