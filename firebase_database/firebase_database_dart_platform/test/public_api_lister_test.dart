// Tests of the source-reading public API lister (public_api_lister.dart).

import 'package:flutter_test/flutter_test.dart';

import 'public_api_lister.dart';

const String _fixture = r'''
import 'package:meta/meta.dart';

/// A class.
@immutable
class Point<T extends num> extends Base implements Comparable<Point<T>> {
  /// With an initializer list.
  const Point(this.x, this.y, {String tag = '{(;'})
    : assert(x >= 0, '<;)'),
      _label = tag,
      super();

  /// A factory with a block body.
  factory Point.parse(String text) {
    final String key = '${text.split(',').first}|${text.isEmpty ? '}' : '{'}';
    return Point<T>(0 as T, 0 as T, label: key);
  }

  /// A redirecting constructor.
  Point.origin() : this(0 as T, 0 as T);

  /// A redirecting factory.
  factory Point.copy(Point<T> other) = Point<T>.origin;

  Point._hidden() : this(0 as T, 0 as T);

  /// Fields.
  final T x, y;
  final String _label;

  /// A static field with a map default.
  @Deprecated('Use defaults ({});')
  static Map<String, List<int>> defaults = <String, List<int>>{'a': <int>[1]};

  /// A getter.
  T get sum => x + y as T;

  /// A setter.
  set label(String value) {}

  /// An operator.
  Point<T> operator +(Point<T> other) => Point<T>(x, y);

  /// Another operator.
  bool operator >(Point<T> other) => true;

  /// A method with a nested function type and a multi-line signature.
  Future<void> visit(
    void Function(T value, {int Function(String)? parse}) visitor, [
    int depth = 1,
  ]) async {}

  /// Code in a doc comment: `void notAMember() {}`
  static int count() => 0;

  void _secret() {}

  @override
  int compareTo(Point<T> other) => 0;
}

/// An extension.
extension PointText on Point<int> {
  /// The text.
  String get text => '($x, $y)';
}

/// An enum.
enum Shape {
  circle,
  square(4);

  const Shape([this.sides = 0]);

  /// Number of sides.
  final int sides;
}

class _Private {
  void hidden() {}
}

/// A function type.
typedef Visitor<T> = void Function(T value);
''';

const String _expected = '''
@immutable class Point<T extends num> extends Base implements Comparable<Point<T>>
  @Deprecated('Use defaults ({});') static Map<String, List<int>> defaults
  Future<void> visit(void Function(T value, {int Function(String)? parse}) visitor, [int depth = 1])
  Point.origin() : this(0 as T, 0 as T)
  Point<T> operator +(Point<T> other)
  T get sum
  bool operator >(Point<T> other)
  const Point(this.x, this.y, {String tag = '{(;'}) : assert(x >= 0, '<;)'), _label = tag, super()
  factory Point.copy(Point<T> other) = Point<T>.origin
  factory Point.parse(String text)
  final T x
  final T y
  int compareTo(Point<T> other)
  set label(String value)
  static int count()
extension PointText on Point<int>
  String get text
enum Shape
  circle
  const Shape([this.sides = 0])
  final int sides
  square
typedef Visitor<T> = void Function(T value)
''';

void main() {
  test('lists a fixture with each kind of declaration and member', () {
    expect(listPublicApiOfSource(_fixture), _expected);
  });

  group('guard', () {
    test('throws for a class with no member lines but public members', () {
      expect(
        () => formatApiEntries(<ApiEntry>[
          ApiEntry(name: 'A', header: 'class A', publicMembersInSource: 2),
        ]),
        throwsStateError,
      );
    });

    test('throws for a line without a name', () {
      expect(
        () => formatApiEntries(<ApiEntry>[
          ApiEntry(
            name: 'A',
            header: 'class A',
            members: <String>[':'],
            publicMembersInSource: 1,
          ),
        ]),
        throwsStateError,
      );
    });

    test('throws for a header that does not name the entry', () {
      expect(
        () => formatApiEntries(<ApiEntry>[
          ApiEntry(name: 'A', header: 'class B'),
        ]),
        throwsStateError,
      );
    });

    test('accepts a class whose members are all private', () {
      expect(listPublicApiOfSource('class A { void _a() {} }'), 'class A\n');
    });
  });
}
