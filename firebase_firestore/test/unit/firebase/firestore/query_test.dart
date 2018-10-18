// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'package:firebase_firestore/src/firebase/firestore/query.dart';
import 'package:test/test.dart';

import 'test_util.dart';

void main() {
  test('testEquals', () {
    final Query foo = query('foo');
    final Query fooDup = query('foo');
    final Query bar = query('bar');
    expect(fooDup, foo);
    expect(bar, isNot(foo));

    expect(fooDup.hashCode, foo.hashCode);
    expect(bar.hashCode, isNot(foo.hashCode));
  });
}
