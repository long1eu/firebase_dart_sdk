// Ported from the iOS SDK, FirebaseDatabase/Tests/Unit/FNextPushIdTest.m (firebase-ios-sdk cef246fea,
// Apache-2.0).
//
// Disagreement: the iOS test takes MIN_PUSH_CHAR as ' ' and MAX_PUSH_CHAR as U+FFFF; Android and JS
// (and the skeleton, `pushChars`) use '-' and 'z'. The tests that name those characters are skipped
// (the Android values are in push_id_generator_test.dart); the order properties are ported with
// every character of the iOS loops. The supplementary-plane loops use a stride (the iOS loop
// visits all 1,048,576 code points and builds a 786-character key for each).
import 'dart:math';

import 'package:firebase_database_dart/src/core/util/key_order.dart';
import 'package:firebase_database_dart/src/core/util/numbers.dart';
import 'package:firebase_database_dart/src/core/util/push_id.dart';
import 'package:firebase_database_dart/src/core/util/validation.dart';
import 'package:test/test.dart';

void main() {
  test('successor special values (int32 max)', () {
    expect(successor(int32Max.toString()), pushChars[0]);
  });

  test(
    'successor special values (iOS characters)',
    () {},
    skip: 'iOS uses U+FFFF as MAX_PUSH_CHAR; Android/JS use z',
  );

  test('push ids of one timestamp are unique', () {
    // iOS: 1000 concurrent calls with the same timestamp.
    final generator = PushIdGenerator(
      nowMillis: () => 12345,
      random: Random(1),
    );
    final ids = {for (var i = 0; i < 1000; i++) generator.next()};
    expect(ids, hasLength(1000));
  });

  test('push id has 20 characters', () {
    final generator = PushIdGenerator(
      nowMillis: () => 12345,
      random: Random(1),
    );
    expect(generator.next(), hasLength(20));
  });

  test(
    'a generation error does not block later calls',
    () {},
    skip:
        'iOS throws for a negative timestamp; PushIdGenerator takes nowMillis with no documented error case',
  );

  test(
    'successor basic (iOS characters)',
    () {},
    skip:
        'iOS uses space and U+FFFF as MIN/MAX_PUSH_CHAR; Android/JS use - and z',
  );

  test(
    'predecessor special values (iOS characters)',
    () {},
    skip: 'iOS uses space as MIN_PUSH_CHAR; Android/JS use -',
  );

  test(
    'predecessor basic (iOS characters)',
    () {},
    skip: 'iOS pads with U+FFFF; Android/JS pad with z',
  );

  test(
    'predecessor unicode',
    () {},
    skip:
        'expected values pad with U+FFFF and decrement code points; the skeleton follows the JS push characters',
  );

  void expectPredecessorOrdering(String key) {
    final predecessorKey = predecessor(key);
    expect(
      nameCompare(key, predecessorKey),
      isPositive,
      reason: 'predecessor of ${key.codeUnits}',
    );
  }

  void expectSuccessorOrdering(String key) {
    final successorKey = successor(key);
    expect(
      nameCompare(key, successorKey),
      isNegative,
      reason: 'successor of ${key.codeUnits}',
    );
  }

  test('predecessor ordering', () {
    // Start after space because otherwise integer interpretation has to be considered.
    for (var i = 0x20; i < 0xD800; i++) {
      final key = String.fromCharCode(i);
      if (!isValidKey(key)) {
        continue;
      }
      expectPredecessorOrdering(key);
    }
    for (var i = 0xE000; i <= 0xFFFF; i++) {
      expectPredecessorOrdering(String.fromCharCode(i));
    }
    for (var i = 0x10000; i <= 0x10FFFF; i += 0x11) {
      expectPredecessorOrdering(String.fromCharCode(i));
    }
  });

  test('predecessor ordering for a surrogate pair after a prefix', () {
    for (var i = 0x10000; i <= 0x10FFFF; i += 0x100) {
      expectPredecessorOrdering('abc${String.fromCharCode(i)}');
    }
  });

  test('successor ordering', () {
    for (var i = 0x20; i < 0xD800; i++) {
      final key = String.fromCharCode(i);
      if (!isValidKey(key)) {
        continue;
      }
      expectSuccessorOrdering(key);
    }
    for (var i = 0xE000; i <= 0xFFFF; i++) {
      expectSuccessorOrdering(String.fromCharCode(i));
    }
    for (var i = 0x10000; i <= 0x10FFFF; i += 0x11) {
      expectSuccessorOrdering(String.fromCharCode(i));
    }
  });

  test('successor ordering for a surrogate pair after a prefix', () {
    // A full-length key ending in U+107FF (D801 DFFF): the low surrogate is the highest one and the
    // high surrogate is not.
    final pair = String.fromCharCode(0x107FF);
    final key = '${'a' * (maxKeyLength - pair.length)}$pair';
    expect(key.length, maxKeyLength);
    expectSuccessorOrdering(key);
  });
}
