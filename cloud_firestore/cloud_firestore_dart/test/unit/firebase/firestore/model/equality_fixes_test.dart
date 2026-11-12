import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_increment_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

void main() {
  group('ServerTimestampValue', () {
    test('equal when they carry equal map or list previous values', () {
      const Timestamp t = Timestamp(100, 0);
      final FieldValue map1 = ObjectValue.fromMap(<String, FieldValue>{
        'a': IntegerValue.valueOf(1),
      });
      final FieldValue map2 = ObjectValue.fromMap(<String, FieldValue>{
        'a': IntegerValue.valueOf(1),
      });
      expect(ServerTimestampValue(t, map1) == ServerTimestampValue(t, map2),
          isTrue);
      expect(ServerTimestampValue(t, map1).hashCode,
          ServerTimestampValue(t, map2).hashCode);

      final FieldValue list1 = ArrayValue.fromList(<FieldValue>[
        IntegerValue.valueOf(1),
      ]);
      final FieldValue list2 = ArrayValue.fromList(<FieldValue>[
        IntegerValue.valueOf(1),
      ]);
      expect(ServerTimestampValue(t, list1) == ServerTimestampValue(t, list2),
          isTrue);
    });

    test('different previous values or write times are not equal', () {
      const Timestamp t = Timestamp(100, 0);
      expect(
          ServerTimestampValue(t, IntegerValue.valueOf(1)) ==
              ServerTimestampValue(t, IntegerValue.valueOf(2)),
          isFalse);
      expect(
          ServerTimestampValue(t, null) ==
              ServerTimestampValue(const Timestamp(101, 0), null),
          isFalse);
    });
  });

  test('DoubleValue distinguishes -0.0 from 0.0 and equates NaN', () {
    expect(DoubleValue.valueOf(-0.0) == DoubleValue.valueOf(0.0), isFalse);
    expect(DoubleValue.valueOf(0.0) == DoubleValue.valueOf(-0.0), isFalse);
    expect(DoubleValue.valueOf(-0.0) == DoubleValue.valueOf(-0.0), isTrue);
    expect(DoubleValue.valueOf(0.0) == DoubleValue.valueOf(0.0), isTrue);
    expect(DoubleValue.valueOf(double.nan) == DoubleValue.valueOf(double.nan),
        isTrue);
  });

  test('NumericIncrementTransformOperation has value equality', () {
    final NumericIncrementTransformOperation a =
        NumericIncrementTransformOperation(IntegerValue.valueOf(1));
    final NumericIncrementTransformOperation b =
        NumericIncrementTransformOperation(IntegerValue.valueOf(1));
    final NumericIncrementTransformOperation c =
        NumericIncrementTransformOperation(DoubleValue.valueOf(1.5));
    expect(a == b, isTrue);
    expect(a.hashCode, b.hashCode);
    expect(a == c, isFalse);
  });

  test('Precondition rejects exists together with updateTime', () {
    expect(
        () => Precondition(updateTime: SnapshotVersion.none, exists: true),
        throwsA(anything));
    expect(Precondition(exists: true).isNone, isFalse);
  });
}
