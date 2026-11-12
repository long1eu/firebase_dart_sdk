// File created by
// Lung Razvan <long1eu>
// on 08/10/2018

import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  group('hardAssertLazy', () {
    test('does not build the message when the condition holds', () {
      int calls = 0;
      hardAssertLazy(true, () {
        calls++;
        return 'unused';
      });
      expect(calls, 0);
    });

    test('builds the message once and throws an AssertionError', () {
      int calls = 0;
      expect(
          () => hardAssertLazy(false, () {
                calls++;
                return 'failed with ${42}';
              }),
          throwsA(isA<AssertionError>().having(
              (AssertionError e) => e.message, 'message', 'failed with 42')));
      expect(calls, 1);
      // Same error type and format as hardAssert.
      Object? eager;
      Object? lazy;
      try {
        hardAssert(false, 'm');
      } catch (e) {
        eager = e;
      }
      try {
        hardAssertLazy(false, () => 'm');
      } catch (e) {
        lazy = e;
      }
      expect(lazy.toString(), eager.toString());
    });
  });

  group('compareUtf8Strings', () {
    int sign(int v) => v.sign;

    test('orders ASCII and prefixes', () {
      expect(sign(compareUtf8Strings('a', 'a')), 0);
      expect(sign(compareUtf8Strings('', '')), 0);
      expect(sign(compareUtf8Strings('', 'a')), -1);
      expect(sign(compareUtf8Strings('a', 'ab')), -1);
      expect(sign(compareUtf8Strings('ab', 'a')), 1);
      expect(sign(compareUtf8Strings('A', 'a')), -1);
      expect(sign(compareUtf8Strings('abc', 'abd')), -1);
    });

    test('orders supplementary characters after U+E000..U+FFFF', () {
      // UTF-16 order would sort the surrogate (0xD800..) before 0xE000..0xFFFF,
      // UTF-8 byte order sorts the 4-byte sequence after the 3-byte ones.
      const String bmpHigh = '\uE000';
      const String bmpTop = '\uFFFF';
      const String supplementary = '\u{10000}';
      const String emoji = '\u{1F600}';
      expect(sign(compareUtf8Strings(bmpHigh, supplementary)), -1);
      expect(sign(compareUtf8Strings(supplementary, bmpHigh)), 1);
      expect(sign(compareUtf8Strings(bmpTop, supplementary)), -1);
      expect(sign(compareUtf8Strings(bmpTop, emoji)), -1);
      expect(sign(compareUtf8Strings('a$bmpTop', 'a$emoji')), -1);
      expect(sign(compareUtf8Strings('\uFF5E', emoji)), -1);
    });

    test('orders two supplementary characters by code point', () {
      expect(sign(compareUtf8Strings('\u{10000}', '\u{1F600}')), -1);
      expect(sign(compareUtf8Strings('\u{1F600}', '\u{10000}')), 1);
      expect(sign(compareUtf8Strings('\u{1F600}', '\u{1F601}')), -1);
      expect(sign(compareUtf8Strings('\u{1F600}', '\u{1F600}')), 0);
    });

    test('matches UTF-8 byte order', () {
      final List<String> values = <String>[
        '',
        'a',
        'ab',
        'z',
        '\u00e9',
        '\u0301',
        '\u07FF',
        '\u0800',
        '\uD7FF',
        '\uE000',
        '\uFFFF',
        '\u{10000}',
        'a\u{10000}',
        '\u{10FFFF}',
      ];
      int bytes(String a, String b) {
        final List<int> x = utf8.encode(a);
        final List<int> y = utf8.encode(b);
        for (int i = 0; i < x.length && i < y.length; i++) {
          if (x[i] != y[i]) {
            return x[i].compareTo(y[i]);
          }
        }
        return x.length.compareTo(y.length);
      }

      for (final String a in values) {
        for (final String b in values) {
          expect(sign(compareUtf8Strings(a, b)), sign(bytes(a, b)),
              reason: 'comparing ${a.codeUnits} and ${b.codeUnits}');
        }
      }
    });
  });

  test('testToDebugString', () {
    expect('', toDebugString(blob().bytes));
    expect('00ff', toDebugString(blob(<int>[0, 0xFF]).bytes));
    expect('1f3b', toDebugString(blob(<int>[0x1F, 0x3B]).bytes));
    expect(
        '000102030405060708090a0b0c0d0e0f',
        toDebugString(blob(<int>[
          0,
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          0xA,
          0xB,
          0xC,
          0xD,
          0xE,
          0xF
        ]).bytes));
  });
}
