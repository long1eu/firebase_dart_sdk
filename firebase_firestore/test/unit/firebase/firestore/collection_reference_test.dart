// File created by
// Lung Razvan <long1eu>
// on 28/09/2018
import 'package:firebase_firestore/src/firebase/firestore/collection_reference.dart';
import 'package:test/test.dart';

import 'test_util.dart';

void main() {
  test('testEquals', () {
    final CollectionReference foo = TestUtil.collectionReference('foo');
    final CollectionReference fooDup = TestUtil.collectionReference('foo');
    final CollectionReference bar = TestUtil.collectionReference('bar');
    expect(foo, fooDup);
    expect(foo, isNot(bar));

    expect(foo.hashCode, fooDup.hashCode);
    expect(bar.hashCode, isNot(foo.hashCode));
  });
}
