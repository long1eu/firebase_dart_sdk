// ChildKey of lib/src/core/snap/child_key.dart (order is in test/core/util/key_order_test.dart).
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:test/test.dart';

void main() {
  test('integer-like names carry their value', () {
    expect(ChildKey('12').intValue, 12);
    expect(ChildKey('12').isInt, isTrue);
    expect(ChildKey('01').intValue, 1);
    expect(ChildKey('-3').intValue, -3);
    expect(ChildKey('a').intValue, isNull);
    expect(ChildKey('a').isInt, isFalse);
    expect(ChildKey('2147483648').isInt, isFalse);
  });

  test('special names return the constants', () {
    expect(identical(ChildKey('.priority'), ChildKey.priority), isTrue);
    expect(identical(ChildKey('.info'), ChildKey.info), isTrue);
    expect(identical(ChildKey('[MIN_NAME]'), ChildKey.min), isTrue);
    expect(identical(ChildKey('[MAX_NAME]'), ChildKey.max), isTrue);
    expect(ChildKey('.priority').isPriorityKey, isTrue);
    expect(ChildKey('priority').isPriorityKey, isFalse);
  });

  test('equality and hash by name', () {
    expect(ChildKey('a'), ChildKey('a'));
    expect(ChildKey('a').hashCode, ChildKey('a').hashCode);
    expect(ChildKey('1'), isNot(ChildKey('01')));
    expect(ChildKey('1').compareTo(ChildKey('01')), isNot(0));
    expect(ChildKey('a').compareTo(ChildKey('a')), 0);
  });

  test('toString is the name', () {
    expect(ChildKey('ada').toString(), 'ada');
  });
}
