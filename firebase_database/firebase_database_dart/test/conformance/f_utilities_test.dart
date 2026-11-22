// Ported from the iOS SDK, FirebaseDatabase/Tests/Unit/FUtilitiesTest.m (firebase-ios-sdk cef246fea,
// Apache-2.0): the key comparison tests. The URL parsing tests belong to RepoInfo (above the data
// layer); the cache size, system clock and user agent tests are not data-layer behaviour.
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/util/key_order.dart';
import 'package:test/test.dart';

void main() {
  const order = [
    // Treated as integers.
    '-2147483648', '0', '1', '2', '10', '2147483647',
    // Treated as strings.
    '-2147483649', '-2147483650', '-a', '2147483648', '21474836480',
    '2147483649', 'a',
  ];

  test('key comparison (nameCompare)', () {
    for (var i = 0; i < order.length; i++) {
      for (var j = i + 1; j < order.length; j++) {
        final first = order[i];
        final second = order[j];
        expect(
          nameCompare(first, second),
          isNegative,
          reason: 'Expected $first < $second',
        );
        expect(nameCompare(first, first), 0);
        expect(
          nameCompare(second, first),
          isPositive,
          reason: 'Expected $second > $first',
        );
      }
    }
  });

  test('key comparison (ChildKey)', () {
    for (var i = 0; i < order.length; i++) {
      for (var j = i + 1; j < order.length; j++) {
        final first = ChildKey(order[i]);
        final second = ChildKey(order[j]);
        expect(
          first.compareTo(second),
          isNegative,
          reason: 'Expected $first < $second',
        );
        expect(first.compareTo(first), 0);
        expect(
          second.compareTo(first),
          isPositive,
          reason: 'Expected $second > $first',
        );
      }
    }
  });

  // Enforce a > b, b < a, a != b: this happens semi-regularly.
  test('unicode key comparison', () {
    const a = '유주연';
    const b = '윤규완오빠';
    expect(nameCompare(a, b), isNegative);
    expect(nameCompare(b, a), isPositive);
    expect(nameCompare(b, a), isNot(0));
    expect(ChildKey(a).compareTo(ChildKey(b)), isNegative);
    expect(ChildKey(b).compareTo(ChildKey(a)), isPositive);
  });
}
