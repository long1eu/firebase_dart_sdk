// Ported from the iOS SDK, FirebaseDatabase/Tests/Unit/FArraySortedDictionaryTest.m
// (firebase-ios-sdk cef246fea, Apache-2.0) onto the skeleton's `SortedMap`. The iOS test names the
// array-backed class; here the same behaviour runs with 20 items (the iOS size), which stays below
// the array-to-tree threshold of the JS and Android maps.
import 'package:test/test.dart';

import 'sorted_map_support.dart';

void main() {
  iosScenarios(20);

  test(
    'get nil returns nil',
    () {},
    skip: 'a null key is not possible with SortedMap<K, V> (K is non-nullable)',
  );
  test(
    'array to tree conversion happens at the threshold',
    () {},
    skip:
        'the representation (array or tree) is not observable through SortedMap',
  );
}
