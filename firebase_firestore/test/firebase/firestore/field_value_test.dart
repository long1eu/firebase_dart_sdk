// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'package:firebase_firestore/src/firebase/firestore/field_value.dart';
import 'package:test/test.dart';

void main() {
  test('testEquals', () {
    final FieldValue delete = FieldValue.delete();
    final FieldValue deleteDup = FieldValue.delete();
    final FieldValue serverTimestamp = FieldValue.serverTimestamp();
    final FieldValue serverTimestampDup = FieldValue.serverTimestamp();
    expect(deleteDup, delete);
    expect(serverTimestampDup, serverTimestamp);
    expect(serverTimestamp, isNot(delete));

    expect(deleteDup.hashCode == delete.hashCode, isTrue);
    expect(serverTimestampDup.hashCode == serverTimestamp.hashCode, isTrue);
    expect(serverTimestamp.hashCode == delete.hashCode, isFalse);
  });
}
