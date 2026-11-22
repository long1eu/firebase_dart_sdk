// Ported from the iOS SDK, FirebaseDatabase/Tests/Unit/FTreeSortedDictionaryTests.m
// (firebase-ios-sdk cef246fea, Apache-2.0) onto the skeleton's `SortedMap`, with 100 items where
// the iOS tests insert and remove a hundred.
import 'package:test/test.dart';

import 'sorted_map_support.dart';

void main() {
  iosScenarios(100);

  test(
    'get nil returns nil',
    () {},
    skip: 'a null key is not possible with SortedMap<K, V> (K is non-nullable)',
  );
  for (final name in [
    'structure should be valid after insertion A',
    'structure should be valid after insertion B',
    'structure should be valid after insertion C',
    'rotate left leaves tree in a valid state',
    'rotate right leaves tree in a valid state',
    'balance problem (root and depth checks)',
  ]) {
    test(
      name,
      () {},
      skip:
          'checks the red-black root, children and checkMaxDepth, which SortedMap does not expose; '
          'order and size after the same operations are covered by the shared scenarios',
    );
  }
}
