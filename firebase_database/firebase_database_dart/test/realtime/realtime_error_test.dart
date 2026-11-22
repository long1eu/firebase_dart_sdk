// Owner K. Status strings of the connection half (rtdb_protocol.md 9, threat model T7).
import 'dart:convert';

import 'package:firebase_database_dart/src/realtime/realtime_error.dart';
import 'package:test/test.dart';

void main() {
  group('countsAsInvalidToken (8.3)', () {
    test('invalid_token and permission_denied count', () {
      expect(countsAsInvalidToken('invalid_token'), isTrue);
      expect(countsAsInvalidToken('permission_denied'), isTrue);
    });

    test('nothing else counts', () {
      for (final String status in <String>[
        'ok',
        'expired_token',
        'INVALID_TOKEN',
        'failure',
        '',
      ]) {
        expect(countsAsInvalidToken(status), isFalse, reason: status);
      }
    });
  });

  group('safeServerText (T7)', () {
    test('plain text is kept', () {
      expect(safeServerText('Permission denied'), 'Permission denied');
      expect(safeServerText('é€😀'), 'é€😀');
      expect(safeServerText(''), '');
    });

    test('control characters are escaped as \\uXXXX', () {
      expect(safeServerText('a\nb\r\tc'), r'a\u000Ab\u000D\u0009c');
      expect(
        safeServerText('\u0000\u001f\u007f\u0085'),
        r'\u0000\u001F\u007F\u0085',
      );
      expect(safeServerText('x\u2028y\u2029'), r'x\u2028y\u2029');
      expect(safeServerText('\u001b[31mred'), r'\u001B[31mred');
    });

    test('lone surrogates are escaped, pairs are kept', () {
      expect(safeServerText('a\ud800b'), r'a\uD800b');
      expect(safeServerText('a\udc00'), r'a\uDC00');
      expect(safeServerText('\ud83d\ude00'), '\u{1F600}');
    });

    test('1024 bytes are kept, one more is cut with a marker', () {
      final String exact = 'a' * 1024;
      expect(safeServerText(exact), exact);
      expect(safeServerText('${exact}b'), '$exact...(cut)');
    });

    test('the cut counts UTF-8 bytes and never splits a character', () {
      final String text = 'é' * 600;
      final String cut = safeServerText(text);
      expect(cut, '${'é' * 512}...(cut)');
      expect(utf8.encode('é' * 512), hasLength(1024));
      final String emoji = safeServerText('a${'😀' * 300}');
      expect(emoji, 'a${'😀' * 255}...(cut)');
    });

    test('a huge text stays bounded', () {
      final String cut = safeServerText('\n' * 1000000);
      expect(cut.length, lessThan(7000));
      expect(cut, isNot(contains('\n')));
    });
  });
}
