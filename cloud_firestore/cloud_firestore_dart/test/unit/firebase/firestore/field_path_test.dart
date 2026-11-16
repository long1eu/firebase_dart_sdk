// File created by
// Lung Razvan <long1eu>
// on 28/09/2018
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:test/test.dart';

void main() {
  test('pathWithArray', () {
    final FieldPath fieldPath = FieldPath(<String>['a', 'b', 'c']);
    expect(fieldPath.toString(), 'a.b.c');
  });

  test('emptyPathIsInvalid', () {
    expect(() => FieldPath.fromString(''), throwsArgumentError);
  });

  test('emptyFirstSegmentIsInvalid', () {
    expect(() => FieldPath.fromString('.a'), throwsArgumentError);
  });

  test('emptyLastSegmentIsInvalid', () {
    expect(() => FieldPath.fromString('a.'), throwsArgumentError);
  });

  test('emptyMiddleSegmentIsInvalid', () {
    expect(() => FieldPath.fromString('a..b'), throwsArgumentError);
  });

  test('testEquals', () {
    final FieldPath foo = FieldPath(<String>['f', 'o', 'o']);
    final FieldPath fooDup = FieldPath(<String>['f', 'o', 'o']);
    final FieldPath bar = FieldPath(<String>['b', 'a', 'r']);
    expect(fooDup, foo);
    expect(bar, isNot(foo));

    expect(foo.hashCode, fooDup.hashCode);
    expect(foo.hashCode, isNot(bar.hashCode));
  });

  // Ported from the JS SDK's test/unit/api/field_path.test.ts.
  group('FieldPath', () {
    test('support equality checking with isEqual()', () {
      expect(FieldPath.fromString('foo'), FieldPath.fromString('foo'));
      expect(
        FieldPath.fromString('foo').hashCode,
        FieldPath.fromString('foo').hashCode,
      );
      expect(FieldPath.fromString('foo'), isNot(FieldPath.fromString('bar')));
    });
  });
}
