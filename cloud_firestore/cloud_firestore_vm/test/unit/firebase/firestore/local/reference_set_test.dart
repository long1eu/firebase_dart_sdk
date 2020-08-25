// File created by
// Lung Razvan <long1eu>
// on 29/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  test('testAddOrRemoveReferences', () {
    final DocumentKey _key = key('foo/bar');

    final ReferenceSet set = ReferenceSet();
    expect(set.containsKey(_key), isFalse);
    expect(set, isEmpty);

    set.addReference(_key, 1);
    expect(set.containsKey(_key), isTrue);
    expect(set, isNotEmpty);

    set.addReference(_key, 2);
    expect(set.containsKey(_key), isTrue);

    set.removeReference(_key, 1);
    expect(set.containsKey(_key), isTrue);

    set.removeReference(_key, 3);
    expect(set.containsKey(_key), isTrue);

    set.removeReference(_key, 2);
    expect(set.containsKey(_key), isFalse);
    expect(set, isEmpty);
  });

  test('testRemoveReferencesForId', () {
    final DocumentKey key1 = key('foo/bar');
    final DocumentKey key2 = key('foo/baz');
    final DocumentKey key3 = key('foo/blah');
    final ReferenceSet set = ReferenceSet()
      ..addReference(key1, 1)
      ..addReference(key2, 1)
      ..addReference(key3, 2);

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
