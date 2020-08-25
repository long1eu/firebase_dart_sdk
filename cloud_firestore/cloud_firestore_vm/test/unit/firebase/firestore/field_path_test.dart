// File created by
// Lung Razvan <long1eu>
// on 28/09/2018
import 'package:cloud_firestore_vm/src/firebase/firestore/field_path.dart';
import 'package:test/test.dart';

void main() {
  test('pathWithArray', () {
    final FieldPath fieldPath = FieldPath.of(<String>['a', 'b', 'c']);
    expect(fieldPath.toString(), 'a.b.c');
  });

  test('emptyPathIsInvalid', () {
    expect(() => FieldPath.fromDotSeparatedPath(''), throwsArgumentError);
  });

  test('emptyFirstSegmentIsInvalid', () {
    expect(() => FieldPath.fromDotSeparatedPath('.a'), throwsArgumentError);
  });

  test('emptyLastSegmentIsInvalid', () {
    expect(() => FieldPath.fromDotSeparatedPath('a.'), throwsArgumentError);
  });

  test('emptyMiddleSegmentIsInvalid', () {
    expect(() => FieldPath.fromDotSeparatedPath('a..b'), throwsArgumentError);
  });

  test('testEquals', () {
    final FieldPath foo = FieldPath.of(<String>['f', 'o', 'o']);
    final FieldPath fooDup = FieldPath.of(<String>['f', 'o', 'o']);
    final FieldPath bar = FieldPath.of(<String>['b', 'a', 'r']);
    expect(fooDup, foo);
    expect(bar, isNot(foo));

    expect(foo.hashCode, fooDup.hashCode);
    expect(foo.hashCode, isNot(bar.hashCode));
  });
}
