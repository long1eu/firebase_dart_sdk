// Ported from the iOS SDK, FirebaseDatabase/Tests/Unit/FCompoundHashTest.m (firebase-ios-sdk
// cef246fea, Apache-2.0). The cases with fixed texts repeat Android's CompoundHashTest with the same
// data (compound_hash_test.dart); this file has the default-split case with the iOS data (keys `0`
// to `n`, integer keys) and the tolerance of the iOS test (absolute, not a percentage).
import 'package:firebase_database_dart/src/core/snap/compound_hash.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('default split has sensible amount of hashes (integer keys)', () {
    Map<String, Object?> data(int count) => {
      for (var i = 0; i < count; i++) '$i': 'value',
    };
    // Roughly 15-20 bytes serialized per node: 10k, 100k and 1M in total.
    final hash10k = CompoundHash.fromNode(n(data(500)));
    final hash100k = CompoundHash.fromNode(n(data(5000)));
    final hash1M = CompoundHash.fromNode(n(data(50000)));
    expect(hash10k.hashes.length, closeTo(15, 3));
    expect(hash100k.hashes.length, closeTo(50, 5));
    expect(hash1M.hashes.length, closeTo(150, 10));
  });
}
