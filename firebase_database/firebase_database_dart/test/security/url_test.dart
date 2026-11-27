// Threat model T6 (database URL parsing) and T3 (no plain-text production URL): the table of
// accepted and refused database URLs, and messages that never quote a query value.
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/realtime/database_url.dart';
import 'package:test/test.dart';

void main() {
  group('accepted', () {
    final Map<String, (String, String)> accepted = <String, (String, String)>{
      'https://x.firebaseio.com': ('x.firebaseio.com', 'x'),
      'https://x.firebaseio.com/': ('x.firebaseio.com', 'x'),
      'https://X.FIREBASEIO.COM': ('x.firebaseio.com', 'x'),
      'wss://x.firebaseio.com': ('x.firebaseio.com', 'x'),
      'x.firebaseio.com': ('x.firebaseio.com', 'x'),
      'https://x.firebaseio.com:443': ('x.firebaseio.com', 'x'),
      'https://x.firebaseio.com?ns=y': ('x.firebaseio.com', 'y'),
      'https://x.firebaseio.com?ns=Y': ('x.firebaseio.com', 'y'),
      'https://x.firebaseio.com?ns=%79': ('x.firebaseio.com', 'y'),
      'https://d.us-central1.firebasedatabase.app': (
        'd.us-central1.firebasedatabase.app',
        'd',
      ),
      'https://db.example.com?ns=n': ('db.example.com', 'n'),
      'https://xn--bcher-kva.example?ns=n': ('xn--bcher-kva.example', 'n'),
      'https://localhost:9443?ns=n': ('localhost:9443', 'n'),
      'https://127.0.0.1:9443?ns=n': ('127.0.0.1:9443', 'n'),
      'https://[::1]:9443?ns=n': ('[::1]:9443', 'n'),
    };
    for (final MapEntry<String, (String, String)> entry in accepted.entries) {
      test(entry.key, () {
        final RepoInfo info = parseDatabaseUrl(entry.key);
        expect(info.host, entry.value.$1);
        expect(info.namespace, entry.value.$2);
        expect(info.secure, isTrue);
        expect(info.isUsingEmulator, isFalse);
      });
    }
  });

  group('refused', () {
    final List<String> refused = <String>[
      // User info: JS connects to evil.example (parser.ts:75-82).
      'https://localhost:x@evil.example',
      'https://u:p@x.firebaseio.com',
      'https://@x.firebaseio.com',
      'https://x.firebaseio.com@evil.example',
      // ns injection and invalid names.
      'https://x.firebaseio.com?ns=a%26ac%3Dx',
      'https://x.firebaseio.com?ns=a&ac=x',
      'https://x.firebaseio.com?ns=../x',
      'https://x.firebaseio.com?ns=a_b',
      'https://x.firebaseio.com?ns=',
      'https://x.firebaseio.com?ns',
      'https://x.firebaseio.com?ns=a%20',
      'https://x.firebaseio.com?ns=%FF',
      'https://x.firebaseio.com?ns=a&ns=b',
      'https://x.firebaseio.com?ns=${'a' * 64}',
      'https://x.firebaseio.com?auth=t',
      'https://x.firebaseio.com?NS=a',
      // Fragment and path.
      'https://x.firebaseio.com#frag',
      'https://x.firebaseio.com/#',
      'https://x.firebaseio.com/a',
      'https://x.firebaseio.com//',
      'https://x.firebaseio.com/%2e%2e',
      // Ports.
      'https://x.firebaseio.com:444',
      'https://x.firebaseio.com:80',
      'https://x.firebaseio.com:0',
      'https://localhost:0?ns=n',
      'https://localhost:70000?ns=n',
      'https://x.firebaseio.com:abc',
      // Plain text (T3) and other schemes.
      'http://x.firebaseio.com',
      'http://x.firebaseio.com:443',
      'ws://x.firebaseio.com',
      'http://localhost:9000?ns=n',
      'ftp://x.firebaseio.com',
      'file:///x',
      // IP literals other than loopback.
      'https://10.0.2.2?ns=n',
      'https://8.8.8.8:443?ns=n',
      'https://[2001:db8::1]?ns=n',
      'https://127.1?ns=n',
      'https://0x7f.0.0.1?ns=n',
      'https://127.000.0.1?ns=n',
      'https://[::1%25lo0]?ns=n',
      // Hosts.
      'https://',
      '',
      'https://.firebaseio.com',
      'https://x..firebaseio.com',
      'https://x.firebaseio.com.',
      'https://x_y.firebaseio.com',
      'https://-x.firebaseio.com',
      'https://bücher.firebaseio.com',
      'https://x%2Efirebaseio.com',
      r'https://x.firebaseio.com\@evil.example',
      'https://x.firebaseio.com evil',
      ' https://x.firebaseio.com',
      // No namespace, and firebase.com (2.1 step 6).
      'https://db.example.com',
      'https://firebaseio.com',
      'https://localhost',
      'https://x.firebase.com',
      'https://firebase.com?ns=n',
    ];
    for (final String url in refused) {
      test(url.isEmpty ? '(empty)' : url, () {
        expect(() => parseDatabaseUrl(url), throwsFormatException);
      });
    }
  });

  test(
    'a refusal never quotes the URL, its user info or a query value (T8)',
    () {
      const List<String> urls = <String>[
        'https://user:pa55-marker@x.firebaseio.com',
        'https://x.firebaseio.com?ns=Bad_marker',
        'https://x.firebaseio.com?ns=a&auth=tok-marker',
        'http://x.firebaseio.com?ns=plain-marker',
        'https://x.firebaseio.com/path-marker',
        'https://x.firebaseio.com#frag-marker',
      ];
      for (final String url in urls) {
        try {
          parseDatabaseUrl(url);
          fail('$url was accepted');
        } on FormatException catch (e) {
          expect(e.toString(), isNot(contains('marker')), reason: url);
          expect(e.source, isNull, reason: url);
        }
      }
    },
  );

  test('http and ws point to the emulator API (T3)', () {
    for (final String url in <String>[
      'http://x.firebaseio.com',
      'ws://x.firebaseio.com',
    ]) {
      expect(
        () => parseDatabaseUrl(url),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('emulatorHost'),
          ),
        ),
      );
    }
  });
}
