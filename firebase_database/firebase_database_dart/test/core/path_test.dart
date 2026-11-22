// Path and ValidationPath of lib/src/core/path.dart; ports JS test/path.test.ts.
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:test/test.dart';

void main() {
  void expectGreater(String left, String right) {
    expect(Path(left).compareTo(Path(right)), greaterThan(0));
    expect(Path(right).compareTo(Path(left)), lessThan(0));
  }

  void expectEqual(String left, String right) {
    expect(Path(left).compareTo(Path(right)), 0);
    expect(Path(left), Path(right));
    expect(Path(left).hashCode, Path(right).hashCode);
  }

  group('parse', () {
    test('accepts a/b and /a/b; toString gives /a/b', () {
      expect(Path('a/b'), Path('/a/b'));
      expect(Path('a/b').toString(), '/a/b');
      expect(Path('/a/b').toString(), '/a/b');
      expect(Path('/a//b/').toString(), '/a/b');
    });

    test('the root', () {
      expect(Path('').isEmpty, isTrue);
      expect(Path('/').isEmpty, isTrue);
      expect(Path('///'), Path.empty);
      expect(Path.empty.toString(), '/');
      expect(Path.empty.length, 0);
      expect(Path.empty.front, isNull);
      expect(Path.empty.back, isNull);
    });

    test('segments are child keys', () {
      final Path path = Path('/users/42/.priority');
      expect(path.length, 3);
      expect(path.front, ChildKey('users'));
      expect(path.back, ChildKey.priority);
      expect(path.segments[1].intValue, 42);
      expect(path.toStringList(), <String>['users', '42', '.priority']);
    });

    test('fromStrings skips empty segments', () {
      expect(Path.fromStrings(<String>['a', '', 'b']), Path('/a/b'));
      expect(Path.fromStrings(<String>[]), Path.empty);
    });
  });

  test('contains() contains the path and any child path', () {
    expect(Path('/').contains(Path('/a/b/c')), isTrue);
    expect(Path('/a').contains(Path('/a/b/c')), isTrue);
    expect(Path('/a/b').contains(Path('/a/b/c')), isTrue);
    expect(Path('/a/b/c').contains(Path('/a/b/c')), isTrue);

    expect(Path('/a/b/c').contains(Path('/a/b')), isFalse);
    expect(Path('/a/b/c').contains(Path('/a')), isFalse);
    expect(Path('/a/b/c').contains(Path('/')), isFalse);

    expect(Path('/a/b/c').popFront().contains(Path('/b/c')), isTrue);
    expect(Path('/a/b/c').popFront().contains(Path('/b/c/d')), isTrue);

    expect(Path('/a/b/c').contains(Path('/b/c')), isFalse);
    expect(Path('/a/b/c').contains(Path('/a/c/b')), isFalse);

    expect(Path('/a/b/c').popFront().contains(Path('/a/b/c')), isFalse);
  });

  test('popFront() drops the first segment', () {
    expect(Path('/a/b/c').popFront().toString(), '/b/c');
    expect(Path('/a/b/c').popFront().popFront().toString(), '/c');
    expect(Path('/a/b/c').popFront().popFront().popFront().toString(), '/');
    expect(
      Path('/a/b/c').popFront().popFront().popFront().popFront().toString(),
      '/',
    );
  });

  test('parent returns the parent', () {
    expect(Path('/a/b/c').parent.toString(), '/a/b');
    expect(Path('/a/b/c').parent!.parent.toString(), '/a');
    expect(Path('/a/b/c').parent!.parent!.parent.toString(), '/');
    expect(Path('/a/b/c').parent!.parent!.parent!.parent, isNull);
  });

  test('compareTo works as expected', () {
    expectEqual('/', '');
    expectEqual('/a', '/a');
    expectEqual('/a', '/a//');
    expectEqual('/a///b/b//', '/a/b/b');
    expectGreater('/b', '/a');
    expectGreater('/ab', '/a');
    expectGreater('/a/b', '/a');
    expectGreater('/a/b', '/a//');
    expectGreater('/a/0971500000', '/a/00403311635');
    expectGreater('/a/0971500000', '/a/971500000');
  });

  test('child and childPath', () {
    expect(Path('/a').child(ChildKey('b')), Path('/a/b'));
    expect(Path.empty.child(ChildKey('b')), Path('/b'));
    expect(Path('/a').childPath(Path('b/c')), Path('/a/b/c'));
    expect(Path('/a').childPath(Path.empty), Path('/a'));
    expect(Path.empty.childPath(Path('/a')), Path('/a'));
  });

  test('relative', () {
    expect(Path.relative(Path('/a'), Path('/a/b/c')), Path('/b/c'));
    expect(Path.relative(Path.empty, Path('/a/b')), Path('/a/b'));
    expect(Path.relative(Path('/a/b'), Path('/a/b')), Path.empty);
    expect(() => Path.relative(Path('/a/b'), Path('/a/c')), throwsStateError);
    expect(() => Path.relative(Path('/a/b'), Path('/a')), throwsStateError);
  });

  test('equality distinguishes integer spellings', () {
    expect(Path('/1'), isNot(Path('/01')));
  });

  test('toUrlEncodedString encodes as encodeURIComponent', () {
    expect(Path.empty.toUrlEncodedString(), '/');
    expect(
      Path.fromStrings(<String>['a b', "!*'()~", 'é']).toUrlEncodedString(),
      "/a%20b/!*'()~/%C3%A9",
    );
  });

  group('ValidationPath', () {
    test('error string uses dots', () {
      final ValidationPath path = ValidationPath(Path.empty, 'p ');
      expect(path.toErrorString(), '');
      path
        ..push('a')
        ..push('b');
      expect(path.toErrorString(), "in property 'a.b'");
      path.pop();
      expect(path.toErrorString(), "in property 'a'");
    });

    test('depth over 32 throws', () {
      final ValidationPath path = ValidationPath(Path.empty, 'p ');
      for (int i = 0; i < maxPathDepth; i++) {
        path.push('k');
      }
      expect(() => path.push('k'), throwsArgumentError);
    });

    test('length over 768 bytes throws, counting UTF-8 and slashes', () {
      // "/" + 767 bytes = 768: allowed.
      expect(() => ValidationPath(Path('a' * 767), 'p '), returnsNormally);
      expect(() => ValidationPath(Path('a' * 768), 'p '), throwsArgumentError);
      // Two-byte characters.
      expect(() => ValidationPath(Path('é' * 384), 'p '), throwsArgumentError);
      final ValidationPath path = ValidationPath(Path('a' * 760), 'p ');
      path.push('bbbbbb'); // 1 + 760 + 1 + 6 = 768
      path.pop();
      path.push('bbbbbb');
      expect(() => path.push('c'), throwsArgumentError);
    });

    test('a starting path that is too deep throws', () {
      expect(
        () => ValidationPath(Path(List<String>.filled(33, 'a').join('/')), ''),
        throwsArgumentError,
      );
    });
  });
}
