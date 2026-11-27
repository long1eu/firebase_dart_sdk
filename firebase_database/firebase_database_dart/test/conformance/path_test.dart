// Ported from the Android SDK, firebase-database/src/test/java/com/google/firebase/database/core/PathTest.java
// (firebase-android-sdk 2cfdd0389, Apache-2.0) and, case for case identical, from the iOS SDK,
// FirebaseDatabase/Tests/Unit/FPathTests.m (firebase-ios-sdk cef246fea, Apache-2.0).
//
// Disagreement: Android `wireFormat()` has no leading slash (`a/b/c`); the skeleton follows JS, where
// `Path.toString()` is the wire form (`/a/b/c`), so the expectations below use the leading slash.
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('contains', () {
    expect(p('/').contains(p('/a/b/c')), isTrue);
    expect(p('/a').contains(p('/a/b/c')), isTrue);
    expect(p('/a/b').contains(p('/a/b/c')), isTrue);
    expect(p('/a/b/c').contains(p('/a/b/c')), isTrue);

    expect(p('/a/b/c').contains(p('/a/b')), isFalse);
    expect(p('/a/b/c').contains(p('/a')), isFalse);
    expect(p('/a/b/c').contains(p('/')), isFalse);

    expect(p('/a/b/c').popFront().contains(p('/b/c')), isTrue);
    expect(p('/a/b/c').popFront().contains(p('/b/c/d')), isTrue);

    expect(p('/a/b/c').contains(p('/b/c')), isFalse);
    expect(p('/a/b/c').contains(p('/a/c/b')), isFalse);

    expect(p('/a/b/c').popFront().contains(p('/a/b/c')), isFalse);
    expect(p('/a/b/c').popFront().contains(p('/b/c')), isTrue);
    expect(p('/a/b/c').popFront().contains(p('/b/c/d')), isTrue);
  });

  test('popFront', () {
    expect(p('/a/b/c').popFront(), p('/b/c'));
    expect(p('/a/b/c').popFront().popFront(), p('/c'));
    expect(p('/a/b/c').popFront().popFront().popFront(), p('/'));
    expect(p('/a/b/c').popFront().popFront().popFront().popFront(), p('/'));
  });

  test('parent', () {
    expect(p('/a/b/c').parent, p('/a/b/'));
    expect(p('/a/b/c').parent!.parent, p('/a/'));
    expect(p('/a/b/c').parent!.parent!.parent, p('/'));
    expect(p('/a/b/c').parent!.parent!.parent!.parent, isNull);
  });

  test('wire format', () {
    expect(Path.empty.toString(), '/');
    expect(p('/a/b//c/').toString(), '/a/b/c');
    expect(p('/a/b//c/').popFront().toString(), '/b/c');
  });

  test('compare', () {
    const inOrder = [
      '1', '2', '10', 'a', 'a/1', 'a/2', 'a/10', 'a/a', 'a/aa', 'a/b', //
      'a/b/c', 'b', 'b/a',
    ];
    for (var i = 0; i < inOrder.length; i++) {
      final path1 = p(inOrder[i]);
      expect(path1.compareTo(path1), 0);
      expect(path1 == p(inOrder[i]), isTrue);
      expect(path1.hashCode, p(inOrder[i]).hashCode);
      for (var j = i + 1; j < inOrder.length; j++) {
        final path2 = p(inOrder[j]);
        expect(path1.compareTo(path2), isNegative, reason: '$path1 < $path2');
        expect(path2.compareTo(path1), isPositive, reason: '$path2 > $path1');
        expect(path1 == path2, isFalse);
      }
    }
  });
}
