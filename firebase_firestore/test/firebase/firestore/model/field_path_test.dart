// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:test/test.dart';

import '../../../util/comparator_test.dart';
import '../../../util/test_util.dart';

void main() {
  test('testConstructor', () {
    final FieldPath path = field('rooms.Eros.messages');
    expect(path.length, 3);
  });

  test('testIndexing', () {
    final FieldPath path = field('rooms.Eros.messages');
    expect(path.getFirstSegment(), 'rooms');
    expect(path.getSegment(0), 'rooms');

    expect(path.getSegment(1), 'Eros');

    expect(path.getLastSegment(), 'messages');
    expect(path.getSegment(2), 'messages');
  });

  test('testWithoutFirstSegment', () {
    final FieldPath path = field('rooms.Eros.messages');
    final FieldPath same = field('rooms.Eros.messages');
    final FieldPath second = field('Eros.messages');
    final FieldPath third = field('messages');
    const FieldPath empty = FieldPath.emptyPath;

    expect(path.popFirst(), second);
    expect(path.popFirst().popFirst(), third);
    expect(path.popFirst().popFirst().popFirst(), empty);
    expect(same, path);
  });

  test('testWithoutLastSegment', () {
    final FieldPath path = field('rooms.Eros.messages');
    final FieldPath same = field('rooms.Eros.messages');
    final FieldPath second = field('rooms.Eros');
    final FieldPath third = field('rooms');
    const FieldPath empty = FieldPath.emptyPath;

    expect(path.popLast(), second);
    expect(path.popLast().popLast(), third);
    expect(path.popLast().popLast().popLast(), empty);
    expect(same, path);
  });
  test('testAppend', () {
    final FieldPath path = field('rooms');
    final FieldPath rooms = field('rooms');
    final FieldPath roomsEros = field('rooms.Eros');
    final FieldPath roomsEros1 = field('rooms.Eros.1');

    expect(path.appendSegment('Eros'), roomsEros);
    expect(path.appendSegment('Eros').appendSegment('1'), roomsEros1);
    expect(path, rooms);

    final FieldPath sub = field('rooms.eros.1').popLast();
    final FieldPath appended = sub.appendSegment('2');
    expect(field('rooms.eros.2'), appended);
  });

  test('testPathComparison', () {
    final FieldPath path1 = field('a.b.c');
    final FieldPath path2 = field('a.b.c');
    final FieldPath path3 = field('x.y.z');
    expect(path2, path1);
    expect(path3, isNot(path2));

    const FieldPath empty = FieldPath.emptyPath;
    final FieldPath a = field('a');
    final FieldPath b = field('b');
    final FieldPath ab = field('a.b');

    ComparatorTester<FieldPath>()
        .addItem(empty)
        .addItem(a)
        .addItem(ab)
        .addItem(b)
        .permitInconsistencyWithEquals()
        .testCompare();
  });

  test('testIsPrefixOf', () {
    const FieldPath empty = FieldPath.emptyPath;
    final FieldPath a = field('a');
    final FieldPath ab = field('a.b');
    final FieldPath abc = field('a.b.c');
    final FieldPath b = field('b');
    final FieldPath ba = field('b.a');

    expect(empty.isPrefixOf(a), isTrue);
    expect(empty.isPrefixOf(ab), isTrue);
    expect(empty.isPrefixOf(abc), isTrue);
    expect(empty.isPrefixOf(empty), isTrue);
    expect(empty.isPrefixOf(b), isTrue);
    expect(empty.isPrefixOf(ba), isTrue);

    expect(a.isPrefixOf(a), isTrue);
    expect(a.isPrefixOf(ab), isTrue);
    expect(a.isPrefixOf(abc), isTrue);
    expect(a.isPrefixOf(empty), isFalse);
    expect(a.isPrefixOf(b), isFalse);
    expect(a.isPrefixOf(ba), isFalse);

    expect(ab.isPrefixOf(a), isFalse);
    expect(ab.isPrefixOf(ab), isTrue);
    expect(ab.isPrefixOf(abc), isTrue);
    expect(ab.isPrefixOf(empty), isFalse);
    expect(ab.isPrefixOf(b), isFalse);
    expect(ab.isPrefixOf(ba), isFalse);

    expect(abc.isPrefixOf(a), isFalse);
    expect(abc.isPrefixOf(ab), isFalse);
    expect(abc.isPrefixOf(abc), isTrue);
    expect(abc.isPrefixOf(empty), isFalse);
    expect(abc.isPrefixOf(b), isFalse);
    expect(abc.isPrefixOf(ba), isFalse);
  });

  void assertRoundTrip(String input, int numElements) {
    final FieldPath path = FieldPath.fromServerFormat(input);
    expect(path.length, numElements);
    expect(path.toString(), input);
  }

  test('testServerFormat', () {
    assertRoundTrip('foo', 1);
    assertRoundTrip('foo.bar', 2);
    assertRoundTrip('foo.bar.baz', 3);
    assertRoundTrip('`.foo\\\\`.`.foo`', 2);
    assertRoundTrip('foo.`\\``.bar', 3);
  });

  test('testCanonicalStringOfSubstring', () {
    final FieldPath path = field('foo.bar.baz');
    expect(path.toString(), 'foo.bar.baz');

    expect(path.popFirst().toString(), 'bar.baz');
    expect(path.popLast().toString(), 'foo.bar');

    expect(path.popFirst().popLast().toString(), 'bar');
    expect(path.popLast().popFirst().toString(), 'bar');
  });
}

// ignore: always_specify_types
const field = TestUtil.field;
