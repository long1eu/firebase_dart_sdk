// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:test/test.dart';

import 'test_util.dart';

void main() {
  test('testEquals', () {
    final DocumentReference foo = TestUtil.documentReference('rooms/foo');
    final DocumentReference fooDup = TestUtil.documentReference('rooms/foo');
    final DocumentReference bar = TestUtil.documentReference('rooms/bar');
    expect(fooDup, foo);
    expect(foo == bar, isFalse);

    expect(fooDup.hashCode, foo.hashCode);
    expect(foo.hashCode == bar.hashCode, isFalse);
  });
}
