// Review L3: `IN (...)` lists come in a few SQL texts, so that the 64-statement cache keeps them.
import 'package:firebase_database_dart_sqlite/src/sql_in_list.dart';
import 'package:test/test.dart';

void main() {
  // Mutation: in SqlInList.paddedLength, return `length` itself (one text per list length): the
  // count of distinct sizes for 1..512 becomes 512.
  test('lists of 1 to 512 values use six SQL texts', () {
    final Set<int> sizes = <int>{
      for (int n = 1; n <= SqlInList.maxSize; n++) SqlInList.paddedLength(n),
    };
    expect(sizes, SqlInList.sizes.toSet());
    expect(SqlInList.paddedLength(1), 1);
    expect(SqlInList.paddedLength(2), 4);
    expect(SqlInList.paddedLength(17), 64);
    expect(() => SqlInList.paddedLength(513), throwsArgumentError);
  });

  // Mutation: in SqlInList.pad, pad with null instead of the last value: `IN` still matches, but a
  // NULL would be bound where a key is expected; the expectation on the padding fails.
  test('padding repeats the last value', () {
    expect(SqlInList.pad(<Object?>['a', 'b']), <Object?>['a', 'b', 'b', 'b']);
    expect(SqlInList.marks(<Object?>['a', 'b']), '?, ?, ?, ?');
    expect(SqlInList.pad(<Object?>[7]), <Object?>[7]);
  });

  test('chunks hold at most maxSize values, in order', () {
    final List<int> values = <int>[for (int i = 0; i < 1200; i++) i];
    final List<List<int>> chunks = SqlInList.chunks(values).toList();
    expect(chunks.map((List<int> c) => c.length), <int>[512, 512, 176]);
    expect(chunks.expand((List<int> c) => c), values);
    expect(SqlInList.chunks(<int>[]), isEmpty);
  });
}
