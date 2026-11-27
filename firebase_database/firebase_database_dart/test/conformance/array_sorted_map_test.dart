// Ported from the Android SDK, firebase-database-collection/src/test/java/com/google/firebase/database/collection/ArraySortedMapTest.java
// (firebase-android-sdk 2cfdd0389, Apache-2.0), quickcheck properties over seeded random maps of up
// to 20 entries (below the array limit of 25).
import 'package:test/test.dart';

import 'sorted_map_support.dart';

void main() {
  androidProperties(20);

  test('search for a specific key', () {
    final map = emptyIntMap().insert(1, 1).insert(2, 2);
    expect(map[1], 1);
    expect(map[2], 2);
    expect(map[3], isNull);
  });

  test('remove key value pair', () {
    final map = emptyIntMap().insert(1, 1).insert(2, 2).remove(1);
    expect(map[2], 2);
    expect(map[1], isNull);
  });

  test('more removals', () {
    final map = intMap([
      1,
      50,
      3,
      4,
      7,
      9,
      20,
      18,
      2,
      71,
      42,
      88,
    ]).remove(1).remove(3).remove(7);
    expect(map[7], isNull);
    expect(map[3], isNull);
    expect(map[1], isNull);
    expect(map[50], 50);
  });

  test(
    'replaces existing key',
    () {},
    skip:
        'compares object identity of equal strings, which Dart does not guarantee',
  );

  test(
    'replace exact key yields same map',
    () {},
    skip:
        'object identity of the result is an implementation detail, not in the SortedMap contract',
  );
  test(
    'removing a non-existent key yields same map',
    () {},
    skip:
        'object identity of the result is an implementation detail, not in the SortedMap contract',
  );
  test(
    'add above limit yields an RB tree',
    () {},
    skip: 'the representation is not observable through SortedMap',
  );
  test(
    'equals is correct',
    () {},
    skip: 'SortedMap declares no equality in the skeleton',
  );
}
