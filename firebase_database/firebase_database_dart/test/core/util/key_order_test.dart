// Key order of lib/src/core/util/key_order.dart and ChildKey: JS nameCompare (util.ts:254-276).
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/util/key_order.dart';
import 'package:test/test.dart';

List<String> _sortNames(List<String> names) =>
    List<String>.of(names)..sort(nameCompare);

List<String> _sortKeys(List<String> names) =>
    (names.map(ChildKey.new).toList()..sort())
        .map((ChildKey k) => k.name)
        .toList();

void main() {
  const List<String> shuffled = <String>[
    'b',
    '[MAX_NAME]',
    '007',
    'a',
    '01',
    '-0',
    '1',
    '0',
    '2147483648',
    '-2147483649',
    '-5',
    '[MIN_NAME]',
    '10',
    '2',
    'B',
    '_',
  ];
  const List<String> expected = <String>[
    '[MIN_NAME]',
    '-5',
    '0',
    '-0',
    '1',
    '01',
    '2',
    '007',
    '10',
    '-2147483649',
    '2147483648',
    'B',
    '_',
    'a',
    'b',
    '[MAX_NAME]',
  ];

  test('nameCompare: min, integers by value, strings by code unit, max', () {
    expect(_sortNames(shuffled), expected);
  });

  test('ChildKey.compareTo agrees with nameCompare', () {
    expect(_sortKeys(shuffled), expected);
    for (final String a in shuffled) {
      for (final String b in shuffled) {
        expect(
          ChildKey(a).compareTo(ChildKey(b)).sign,
          nameCompare(a, b).sign,
          reason: '$a vs $b',
        );
      }
    }
  });

  test('equal integer values order by length, shorter first', () {
    // "1", "01", "001" are all the integer 1 (JS INTEGER_REGEXP_ ^-?(0*)\d{1,10}$).
    expect(_sortNames(<String>['001', '1', '01']), <String>['1', '01', '001']);
    expect(_sortKeys(<String>['001', '1', '01']), <String>['1', '01', '001']);
    expect(nameCompare('-0', '0'), greaterThan(0));
    expect(nameCompare('0', '-0'), lessThan(0));
  });

  test('integer-like keys sort before every string', () {
    expect(nameCompare('2147483647', '-'), lessThan(0));
    expect(nameCompare('-2147483648', '!'), lessThan(0));
  });

  test('strings compare by UTF-16 code unit, not code point', () {
    // U+1F600 is 😀, below ￿ by code unit, above it by code point.
    expect(nameCompare('\u{1F600}', '￿'), lessThan(0));
    expect(ChildKey('\u{1F600}').compareTo(ChildKey('￿')), lessThan(0));
    expect(nameCompare('Z', 'a'), lessThan(0));
    expect(nameCompare('a', 'ab'), lessThan(0));
  });

  test('min and max', () {
    expect(nameCompare(minName, minName), 0);
    expect(nameCompare(minName, '-2147483648'), lessThan(0));
    expect(nameCompare(maxName, '￿'), greaterThan(0));
    expect(nameCompare(minName, maxName), lessThan(0));
  });

  test('stringCompare returns -1, 0 or 1', () {
    expect(stringCompare('a', 'b'), -1);
    expect(stringCompare('b', 'a'), 1);
    expect(stringCompare('a', 'a'), 0);
    expect(stringCompare('10', '9'), -1);
  });
}
