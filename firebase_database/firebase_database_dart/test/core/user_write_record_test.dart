// Own tests for UserWriteRecord (Android core/UserWriteRecord.java).
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:test/test.dart';

void main() {
  test('overwrite', () {
    final UserWriteRecord record = UserWriteRecord.overwrite(
      1,
      Path('a'),
      nodeFromJson(1),
      visible: false,
    );
    expect(record.isOverwrite, isTrue);
    expect(record.isMerge, isFalse);
    expect(record.visible, isFalse);
  });

  test('merge is always visible', () {
    final UserWriteRecord record = UserWriteRecord.merge(
      1,
      Path('a'),
      CompoundWrite.fromValue(<String, Object?>{'b': 1}),
    );
    expect(record.isMerge, isTrue);
    expect(record.isOverwrite, isFalse);
    expect(record.visible, isTrue);
  });

  test('equality and hash', () {
    UserWriteRecord over(int id, {bool visible = true, Object? value = 1}) =>
        UserWriteRecord.overwrite(
          id,
          Path('a'),
          nodeFromJson(value),
          visible: visible,
        );
    expect(over(1), over(1));
    expect(over(1).hashCode, over(1).hashCode);
    expect(over(1), isNot(over(2)));
    expect(over(1), isNot(over(1, visible: false)));
    expect(over(1), isNot(over(1, value: 2)));

    final UserWriteRecord merge1 = UserWriteRecord.merge(
      1,
      Path('a'),
      CompoundWrite.fromValue(<String, Object?>{'b': 1}),
    );
    final UserWriteRecord merge2 = UserWriteRecord.merge(
      1,
      Path('a'),
      CompoundWrite.fromValue(<String, Object?>{'b': 1}),
    );
    expect(merge1, merge2);
    expect(merge1.hashCode, merge2.hashCode);
    expect(merge1, isNot(over(1)));
  });

  test('toString', () {
    expect(
      UserWriteRecord.overwrite(
        7,
        Path('a'),
        nodeFromJson(1),
        visible: true,
      ).toString(),
      startsWith('UserWriteRecord{id=7 path='),
    );
  });
}
