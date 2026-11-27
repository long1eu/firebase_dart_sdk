// Owner K. Threat model T11, the decoder's rows of server_input_test.dart: one case per rule, each
// asserting a protocol-error Ignored (the connection closes it with backoff; brief rule 4) and so
// no record that could reach the delegate.
import 'dart:convert';

import 'package:firebase_database_dart/src/realtime/server_message.dart';
import 'package:test/test.dart';

Matcher _protocolError() => isA<Ignored>().having(
  (Ignored i) => i.isProtocolError,
  'isProtocolError',
  isTrue,
);

ServerMessage _push(
  String path,
  Object? data, {
  String action = 'd',
  Object? tag,
}) => decodeServerMessage(<String, Object?>{
  'a': action,
  'b': <String, Object?>{'p': path, 'd': data, 't': ?tag},
});

void main() {
  group('server paths (T11)', () {
    test('a path into .info is refused', () {
      expect(_push('.info/connected', true), _protocolError());
      expect(_push('/.info', true), _protocolError());
    });

    test('forbidden characters in a segment are refused', () {
      for (final String path in <String>[
        'a.b',
        'a#b',
        r'a$b',
        'a[b',
        'a]b',
        'a\u0000b',
        'a\nb',
        'a\u007fb',
      ]) {
        expect(_push(path, 1), _protocolError(), reason: path);
      }
    });

    test('empty segments are refused', () {
      for (final String path in <String>['a//b', 'a/', '//', '/a/']) {
        expect(_push(path, 1), _protocolError(), reason: path);
      }
    });

    test('.priority only as the last of two or more segments', () {
      expect(_push('a/.priority', 1), isA<DataPush>());
      expect(_push('.priority', 1), _protocolError());
      expect(_push('a/.priority/b', 1), _protocolError());
      expect(_push('a/.value', 1), _protocolError());
    });

    test('at most 32 segments', () {
      expect(_push(List<String>.filled(32, 'a').join('/'), 1), isA<DataPush>());
      expect(
        _push(List<String>.filled(33, 'a').join('/'), 1),
        _protocolError(),
      );
    });

    test('at most 768 UTF-8 bytes', () {
      expect(_push('é' * 384, 1), isA<DataPush>());
      expect(_push('é' * 385, 1), _protocolError());
      expect(_push('${'a' * 383}/${'b' * 384}', 1), isA<DataPush>());
      expect(_push('${'a' * 384}/${'b' * 384}', 1), _protocolError());
    });

    test('the same rules apply to c, rm and the range bounds', () {
      expect(
        decodeServerMessage(<String, Object?>{
          'a': 'c',
          'b': <String, Object?>{'p': '.info'},
        }),
        _protocolError(),
      );
      expect(
        decodeServerMessage(<String, Object?>{
          'a': 'rm',
          'b': <String, Object?>{
            'p': 'ch',
            'd': <Object?>[
              <String, Object?>{'e': '.info/x', 'm': 1},
              <String, Object?>{'s': '.info/x', 'm': 1},
            ],
          },
        }),
        _protocolError(),
      );
    });
  });

  group('merge keys (T11)', () {
    test('relative paths are accepted', () {
      expect(
        _push('a', <String, Object?>{'b/c': 1, 'd': null}, action: 'm'),
        isA<DataPush>(),
      );
    });

    test('empty, absolute, forbidden or too deep keys are refused', () {
      for (final String key in <String>[
        '',
        '/b',
        'b//c',
        'b.c',
        '.info',
        List<String>.filled(32, 'k').join('/'),
      ]) {
        expect(
          _push('a', <String, Object?>{key: 1}, action: 'm'),
          _protocolError(),
          reason: key,
        );
      }
    });
  });

  group('data keys and values (T11)', () {
    test('.sv from the server is refused, at any depth', () {
      expect(
        _push('a', <String, Object?>{'.sv': 'timestamp'}),
        _protocolError(),
      );
      expect(
        _push('a', <String, Object?>{
          'b': <String, Object?>{
            'c': <String, Object?>{'.sv': 'timestamp'},
          },
        }),
        _protocolError(),
      );
    });

    test('.value only next to .priority', () {
      expect(
        _push('a', <String, Object?>{'.value': 1, '.priority': 2}),
        isA<DataPush>(),
      );
      expect(
        _push('a', <String, Object?>{'.value': 1, 'b': 2}),
        _protocolError(),
      );
    });

    test('other keys follow the write rules', () {
      for (final String key in <String>[
        '',
        'a.b',
        'a/b',
        'a#b',
        '.foo',
        'a\tb',
      ]) {
        expect(
          _push('a', <String, Object?>{key: 1}),
          _protocolError(),
          reason: key,
        );
      }
      expect(_push('a', <String, Object?>{'é😀 ok-_~': 1}), isA<DataPush>());
    });

    test('a key over 768 bytes is refused', () {
      expect(_push('a', <String, Object?>{'k' * 768: 1}), isA<DataPush>());
      expect(_push('a', <String, Object?>{'k' * 769: 1}), _protocolError());
    });

    test('non-finite numbers are refused, in pushes and in merges', () {
      for (final double value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(_push('a', value), _protocolError());
        expect(_push('a', <Object?>[1, value]), _protocolError());
        expect(
          _push('a', <String, Object?>{'b': value}, action: 'm'),
          _protocolError(),
        );
      }
    });

    test('a leaf string over 10 MiB is refused', () {
      const int max = 10 * 1024 * 1024;
      expect(_push('a', 'x' * max), isA<DataPush>());
      expect(_push('a', 'x' * (max + 1)), _protocolError());
      expect(_push('a', 'é' * (max ~/ 2 + 1)), _protocolError());
    });

    test('values that are not JSON are refused', () {
      expect(_push('a', Object()), _protocolError());
      expect(
        _push('a', <String, Object?>{'b': DateTime(2026)}),
        _protocolError(),
      );
    });

    test('deep data is checked without recursion', () {
      Object? deep = 1;
      for (int i = 0; i < 200000; i++) {
        deep = <String, Object?>{'k': deep};
      }
      expect(() => _push('a', deep), returnsNormally);
      expect(_push('a', deep), isA<DataPush>());
    });
  });

  group('integers (T11)', () {
    test('a non-integer or negative tag is refused', () {
      for (final Object tag in <Object>[1.5, -1, '1', true, <Object?>[]]) {
        expect(_push('a', 1, tag: tag), _protocolError(), reason: '$tag');
      }
    });

    test('a tag or request number that is not a whole number below 2^53 is refused on every '
        'compiler (web audit U1, U2)', () {
      // JSON texts that this compiler's jsonDecode turns into an int on one compiler and a
      // double on another (1e20, 1.5e300 are ints on dart2js), or into a value the web cannot
      // hold exactly (beyond 2^53).
      for (final String text in <String>[
        '1e20',
        '1.5e300',
        '1e400',
        '-1e400',
        '9007199254740992',
        '9007199254740993',
        '9223372036854775807',
        '-9223372036854775808',
        '-1',
        '1.5',
      ]) {
        final Object? seen = (jsonDecode('[$text]') as List<Object?>).single;
        final String reason =
            'JSON $text decodes here to $seen (${seen.runtimeType}, is int: ${seen is int})';
        expect(
          decodeServerMessage(
            jsonDecode('{"a":"d","b":{"p":"a","d":1,"t":$text}}')
                as Map<String, Object?>,
          ),
          _protocolError(),
          reason: 'tag: $reason',
        );
        expect(
          decodeServerMessage(
            jsonDecode('{"r":$text,"b":{"s":"ok"}}') as Map<String, Object?>,
          ),
          _protocolError(),
          reason: 'r: $reason',
        );
      }
    });

    test('a non-integer or negative request number is refused', () {
      for (final Object r in <Object>[1.5, -2, '1', double.nan]) {
        expect(
          decodeServerMessage(<String, Object?>{
            'r': r,
            'b': <String, Object?>{'s': 'ok'},
          }),
          _protocolError(),
          reason: '$r',
        );
      }
    });
  });
}
