import 'dart:convert';

import 'package:firebase_transport_dart/firebase_transport_dart.dart';
import 'package:test/test.dart';

String _nested(int depth) => '${'[' * depth}${']' * depth}';

List<int> _bytes(String text) => utf8.encode(text);

void main() {
  group('depth 32 is accepted and 33 refused', () {
    test('maxJsonDepth is 32', () {
      expect(maxJsonDepth, 32);
    });

    test('exceedsJsonDepth in bytes: 32 levels pass, 33 do not', () {
      expect(exceedsJsonDepth(_bytes(_nested(32))), isFalse);
      expect(exceedsJsonDepth(_bytes(_nested(33))), isTrue);
    });

    test('exceedsJsonDepth in text: 32 levels pass, 33 do not', () {
      expect(exceedsJsonDepth(_nested(32).codeUnits), isFalse);
      expect(exceedsJsonDepth(_nested(33).codeUnits), isTrue);
    });

    test('decodeGuardedBytes accepts 32 levels and refuses 33', () {
      expect(decodeGuardedBytes(_bytes(_nested(32))), isA<List<Object?>>());
      expect(
        () => decodeGuardedBytes(_bytes(_nested(33))),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            'The JSON nests deeper than 32 levels.',
          ),
        ),
      );
    });

    test('decodeGuardedText accepts 32 levels and refuses 33', () {
      expect(decodeGuardedText(_nested(32)), isA<List<Object?>>());
      expect(
        () => decodeGuardedText(_nested(33)),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            'The JSON nests deeper than 32 levels.',
          ),
        ),
      );
    });

    test(
      'sibling containers do not add up: the depth falls back after each',
      () {
        final String siblings = '[${_nested(31)},${_nested(31)}]';
        expect(exceedsJsonDepth(siblings.codeUnits), isFalse);
        expect(decodeGuardedText(siblings), isA<List<Object?>>());
        expect(decodeGuardedBytes(_bytes(siblings)), isA<List<Object?>>());
        final String tooDeepSibling = '[${_nested(31)},${_nested(32)}]';
        expect(exceedsJsonDepth(tooDeepSibling.codeUnits), isTrue);
      },
    );

    test('objects count as levels, mixed with arrays', () {
      final String mixed32 = '{"a":' * 16 + '[' * 16 + ']' * 16 + '}' * 16;
      final String mixed33 = '{"a":' * 17 + '[' * 16 + ']' * 16 + '}' * 17;
      expect(exceedsJsonDepth(mixed32.codeUnits), isFalse);
      expect(exceedsJsonDepth(mixed33.codeUnits), isTrue);
    });
  });

  group('brackets inside strings and after escapes', () {
    test('brackets inside a string do not count', () {
      final String text = '["${'[' * 100}"]';
      expect(exceedsJsonDepth(text.codeUnits), isFalse);
      expect(decodeGuardedText(text), <Object?>['[' * 100]);
    });

    test('an escaped quote does not end the string', () {
      final String text = r'["\"' + '[' * 100 + r'"]';
      expect(exceedsJsonDepth(text.codeUnits), isFalse);
      expect(decodeGuardedText(text), <Object?>['"${'[' * 100}']);
    });

    test('an escaped backslash before the closing quote ends the string', () {
      final String text = '["\\\\",${_nested(33)}]';
      expect(exceedsJsonDepth(text.codeUnits), isTrue);
    });

    test('brackets after a string closes count again', () {
      final String text = '["x",${_nested(32)}]';
      expect(exceedsJsonDepth(text.codeUnits), isTrue);
    });

    test('the same holds in bytes', () {
      final String text = '["${'{' * 100}"]';
      expect(exceedsJsonDepth(_bytes(text)), isFalse);
      expect(decodeGuardedBytes(_bytes(text)), <Object?>['{' * 100]);
    });
  });

  group('a custom maxDepth', () {
    test('exceedsJsonDepth honours it', () {
      expect(exceedsJsonDepth(_nested(64).codeUnits, maxDepth: 64), isFalse);
      expect(exceedsJsonDepth(_nested(65).codeUnits, maxDepth: 64), isTrue);
      expect(exceedsJsonDepth(_nested(2).codeUnits, maxDepth: 1), isTrue);
    });

    test('depth 33 is accepted with maxDepth 64', () {
      expect(
        decodeGuardedText(_nested(33), maxDepth: 64),
        isA<List<Object?>>(),
      );
      expect(
        decodeGuardedBytes(_bytes(_nested(33)), maxDepth: 64),
        isA<List<Object?>>(),
      );
    });

    test('the message names the limit in use', () {
      expect(
        () => decodeGuardedText(_nested(65), maxDepth: 64),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            'The JSON nests deeper than 64 levels.',
          ),
        ),
      );
      expect(
        () => decodeGuardedBytes(_bytes(_nested(11)), maxDepth: 10),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            'The JSON nests deeper than 10 levels.',
          ),
        ),
      );
    });
  });

  group('input that is not valid', () {
    test('bytes that are not UTF-8 throw a FormatException', () {
      expect(
        () => decodeGuardedBytes(<int>[0x22, 0xff, 0xfe, 0x22]),
        throwsFormatException,
      );
    });

    test('a truncated UTF-8 sequence throws a FormatException', () {
      expect(
        () => decodeGuardedBytes(<int>[0x22, 0xe2, 0x82]),
        throwsFormatException,
      );
    });

    test('bytes that are not JSON throw a FormatException', () {
      expect(() => decodeGuardedBytes(_bytes('{"a":')), throwsFormatException);
      expect(() => decodeGuardedBytes(_bytes('nope')), throwsFormatException);
    });

    test('text that is not JSON throws a FormatException', () {
      expect(() => decodeGuardedText('{"a":'), throwsFormatException);
      expect(() => decodeGuardedText(''), throwsFormatException);
    });

    test('a failure that is not depth does not say the JSON nests deeper', () {
      expect(
        () => decodeGuardedText('{"a":'),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            isNot(contains('nests deeper')),
          ),
        ),
      );
    });
  });
}
