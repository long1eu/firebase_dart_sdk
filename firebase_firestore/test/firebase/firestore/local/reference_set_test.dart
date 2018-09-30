// File created by
// Lung Razvan <long1eu>
// on 29/09/2018

import 'package:firebase_firestore/src/firebase/firestore/local/reference_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart';

void main() {
  test('testAddOrRemoveReferences', () {
    final DocumentKey key = TestUtil.key('foo/bar');

    final ReferenceSet set = ReferenceSet();
    expect(set.containsKey(key), isFalse);
    expect(set, isEmpty);

    set.addReference(key, 1);
    expect(set.containsKey(key), isTrue);
    expect(set, isNotEmpty);

    set.addReference(key, 2);
    expect(set.containsKey(key), isTrue);

    set.removeReference(key, 1);
    expect(set.containsKey(key), isTrue);

    set.removeReference(key, 3);
    expect(set.containsKey(key), isTrue);

    set.removeReference(key, 2);
    expect(set.containsKey(key), isFalse);
    expect(set, isEmpty);
  });

  test('testRemoveReferencesForId', () {
    final DocumentKey key1 = key('foo/bar');
    final DocumentKey key2 = key('foo/baz');
    final DocumentKey key3 = key('foo/blah');
    final ReferenceSet set = ReferenceSet();

    set.addReference(key1, 1);
    set.addReference(key2, 1);
    set.addReference(key3, 2);
    expect(set, isNotEmpty);
    expect(set.containsKey(key1), isTrue);
    expect(set.containsKey(key2), isTrue);
    expect(set.containsKey(key3), isTrue);

    set.removeReferencesForId(1);
    expect(set, isNotEmpty);
    expect(set.containsKey(key1), isFalse);
    expect(set.containsKey(key2), isFalse);
    expect(set.containsKey(key3), isTrue);

    set.removeReferencesForId(2);
    expect(set, isEmpty);
    expect(set.containsKey(key1), isFalse);
    expect(set.containsKey(key2), isFalse);
    expect(set.containsKey(key3), isFalse);
  });
}

// ignore: always_specify_types
const key = TestUtil.key;
