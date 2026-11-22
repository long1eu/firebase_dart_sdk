// Push ids of lib/src/core/util/push_id.dart; successor/predecessor port JS test/pushid.test.ts.
import 'dart:math';

import 'package:firebase_database_dart/src/core/util/key_order.dart';
import 'package:firebase_database_dart/src/core/util/numbers.dart';
import 'package:firebase_database_dart/src/core/util/push_id.dart';
import 'package:test/test.dart';

const String minPushChar = '-';
const String maxPushChar = 'z';

final class _FixedRandom implements Random {
  _FixedRandom(this.value);

  final int value;

  @override
  int nextInt(int max) => value;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

void main() {
  group('PushIdGenerator', () {
    test('8 time characters then 12 random characters', () {
      final PushIdGenerator generator = PushIdGenerator(
        nowMillis: () => 0,
        random: _FixedRandom(1),
      );
      expect(generator.next(), '--------000000000000');
    });

    test('encodes the time in base 64, most significant first', () {
      final PushIdGenerator generator = PushIdGenerator(
        nowMillis: () => 64 * 64 + 1,
        random: _FixedRandom(0),
      );
      expect(generator.next().substring(0, 8), '-----0-0');
    });

    test('within one millisecond the random part is incremented', () {
      final PushIdGenerator generator = PushIdGenerator(
        nowMillis: () => 1700000000000,
        random: _FixedRandom(62),
      );
      final String first = generator.next();
      final String second = generator.next();
      final String third = generator.next();
      expect(first.substring(8), 'yyyyyyyyyyyy');
      expect(second.substring(8), 'yyyyyyyyyyyz');
      expect(third.substring(8), 'yyyyyyyyyyz-');
      expect(first.compareTo(second), lessThan(0));
      expect(second.compareTo(third), lessThan(0));
    });

    test('ids sort by time and have 20 characters', () {
      int now = 1700000000000;
      final PushIdGenerator generator = PushIdGenerator(
        nowMillis: () => now,
        random: Random(7),
      );
      String previous = generator.next();
      for (int i = 0; i < 200; i++) {
        if (i.isEven) {
          now += 1;
        }
        final String id = generator.next();
        expect(id.length, 20);
        expect(id.split('').every(pushChars.contains), isTrue);
        expect(previous.compareTo(id), lessThan(0));
        expect(nameCompare(previous, id), lessThan(0));
        previous = id;
      }
    });

    test('generators do not share state', () {
      final PushIdGenerator a = PushIdGenerator(
        nowMillis: () => 5,
        random: _FixedRandom(3),
      );
      final PushIdGenerator b = PushIdGenerator(
        nowMillis: () => 5,
        random: _FixedRandom(3),
      );
      expect(a.next(), b.next());
    });

    test('a time beyond 48 bits throws', () {
      final PushIdGenerator generator = PushIdGenerator(
        nowMillis: () => 281474976710656, // 2^48
        random: _FixedRandom(0),
      );
      expect(generator.next, throwsStateError);
    });
  });

  group('predecessor', () {
    test('special values', () {
      expect(predecessor(minPushChar), '$int32Max');
      expect(predecessor('$int32Min'), minName);
    });

    test('basic', () {
      expect(
        predecessor('abc'),
        'abb${maxPushChar * (maxKeyLength - 'abc'.length)}',
      );
      expect(predecessor('abc$minPushChar'), 'abc');
    });

    test('integer keys', () {
      expect(predecessor('5'), '4');
      expect(predecessor('0'), '-1');
    });
  });

  group('successor', () {
    test('special values', () {
      expect(successor('$int32Max'), minPushChar);
      expect(successor(maxPushChar * maxKeyLength), maxName);
    });

    test('basic', () {
      expect(successor('abc'), 'abc$minPushChar');
      expect(
        successor('abc${maxPushChar * (maxKeyLength - 'abc'.length)}'),
        'abd',
      );
      expect(successor('abc$minPushChar'), 'abc${minPushChar * 2}');
    });

    test('integer keys', () {
      expect(successor('5'), '6');
      expect(successor('-1'), '0');
    });
  });
}
