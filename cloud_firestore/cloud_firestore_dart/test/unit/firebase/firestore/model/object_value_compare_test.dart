import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

ObjectValue build(int fields, {int? differAt}) {
  return ObjectValue.fromMap(<String, FieldValue>{
    for (int i = 0; i < fields; i++)
      'f${i.toString().padLeft(6, '0')}': IntegerValue(i == differAt ? -1 : i)
  });
}

void main() {
  test('compareTo walks large objects field by field', () {
    expect(build(3000).compareTo(build(3000)), 0);
    expect(build(3000, differAt: 2999).compareTo(build(3000)), lessThan(0));
    expect(build(3000).compareTo(build(3000, differAt: 1500)), greaterThan(0));
    expect(build(2999).compareTo(build(3000)), lessThan(0));
    expect(build(3000).compareTo(build(2999)), greaterThan(0));
    expect(build(0).compareTo(build(0)), 0);
  });
}
