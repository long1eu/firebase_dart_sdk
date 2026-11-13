// File created by
// Lung Razvan <long1eu>
// on 28/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart';
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

  // Ported from the JS SDK's test/unit/api/field_value.test.ts.
  group('FieldValue', () {
    test('support equality checking with isEqual()', () {
      expect(FieldValue.delete(), FieldValue.delete());
      expect(FieldValue.serverTimestamp(), FieldValue.serverTimestamp());
      expect(FieldValue.delete(), isNot(FieldValue.serverTimestamp()));

      expect(FieldValue.minimum(1), FieldValue.minimum(1));
      expect(FieldValue.minimum(1), isNot(FieldValue.minimum(2)));
      expect(FieldValue.maximum(1), FieldValue.maximum(1));
      expect(FieldValue.maximum(1), isNot(FieldValue.maximum(2)));
      expect(FieldValue.minimum(1), isNot(FieldValue.maximum(1)));

      // Test NaN equality
      expect(FieldValue.minimum(double.nan), FieldValue.minimum(double.nan));
      expect(FieldValue.maximum(double.nan), FieldValue.maximum(double.nan));
    });

    test('support instanceof checks', () {
      expect(FieldValue.delete(), isA<FieldValue>());
      expect(FieldValue.serverTimestamp(), isA<FieldValue>());
      expect(FieldValue.arrayRemove(<Object?>[1]), isA<FieldValue>());
      expect(FieldValue.arrayUnion(<Object?>['a']), isA<FieldValue>());
      expect(FieldValue.arrayRemove(<Object?>['a']), isA<FieldValue>());
      expect(FieldValue.increment(1), isA<FieldValue>());
      expect(FieldValue.minimum(1), isA<FieldValue>());
      expect(FieldValue.maximum(1), isA<FieldValue>());
    });

    // FieldValue has no JSON form in Dart (jsonEncode needs a toJson), so the
    // port checks the string form instead.
    test('JSON.stringify() does not throw', () {
      for (final FieldValue value in <FieldValue>[
        FieldValue.delete(),
        FieldValue.serverTimestamp(),
        FieldValue.increment(1),
        FieldValue.arrayUnion(<Object?>[2]),
        FieldValue.arrayRemove(<Object?>[3]),
        FieldValue.minimum(4),
        FieldValue.maximum(5),
      ]) {
        expect(value.toString, returnsNormally);
      }
    });
  });
}
