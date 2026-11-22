// ImmutableTree (JS core/util/ImmutableTree.ts, Android core/utilities/ImmutableTree.java). Neither
// SDK has a dedicated test file; these pin the upstream behaviour method by method.
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';
import 'package:test/test.dart';

ImmutableTree<String> sample() => ImmutableTree<String>.fromMap(<Path, String>{
  Path('a'): 'A',
  Path('a/b/c'): 'C',
  Path('x/y'): 'Y',
});

void main() {
  test('empty tree is empty', () {
    expect(ImmutableTree<int>.empty().isEmpty, isTrue);
    expect(ImmutableTree<int>(null).isEmpty, isTrue);
    expect(ImmutableTree<int>(1).isEmpty, isFalse);
  });

  test('set and get', () {
    final ImmutableTree<String> tree = sample();
    expect(tree.get(Path('a')), 'A');
    expect(tree.get(Path('a/b')), isNull);
    expect(tree.get(Path('a/b/c')), 'C');
    expect(tree.get(Path('x/y')), 'Y');
    expect(tree.get(Path('nope')), isNull);
    expect(tree.get(Path.empty), isNull);
  });

  test('set does not change the original tree', () {
    final ImmutableTree<String> tree = sample();
    tree.set(Path('a'), 'changed');
    expect(tree.get(Path('a')), 'A');
  });

  test('rootMostValue and leafMostValue', () {
    final ImmutableTree<String> tree = sample();
    expect(tree.rootMostValue(Path('a/b/c/d')), 'A');
    expect(tree.leafMostValue(Path('a/b/c/d')), 'C');
    expect(tree.leafMostValue(Path('a/b')), 'A');
    expect(tree.rootMostValue(Path('x')), isNull);
    expect(tree.rootMostValue(Path('q')), isNull);
  });

  test('matching variants skip values the predicate rejects', () {
    final ImmutableTree<String> tree = sample();
    expect(
      tree.rootMostValueMatching(Path('a/b/c'), (String v) => v == 'C'),
      'C',
    );
    expect(
      tree.leafMostValueMatching(Path('a/b/c'), (String v) => v == 'A'),
      'A',
    );
    expect(tree.containsMatchingValue((String v) => v == 'Y'), isTrue);
    expect(tree.containsMatchingValue((String v) => v == 'Z'), isFalse);
  });

  test('findRootMostValueAndPath gives the path of the value', () {
    final ImmutableTree<String> tree = sample();
    final PathAndValue<String>? found = tree.findRootMostValueAndPath(
      Path('a/b/c'),
    );
    expect(found!.path, Path('a'));
    expect(found.value, 'A');
    final PathAndValue<String>? matching = tree
        .findRootMostMatchingPathAndValue(
          Path('a/b/c'),
          (String v) => v == 'C',
        );
    expect(matching!.path, Path('a/b/c'));
    expect(tree.findRootMostValueAndPath(Path('x')), isNull);
  });

  test('subtree and getChild', () {
    final ImmutableTree<String> tree = sample();
    expect(tree.subtree(Path('a/b')).get(Path('c')), 'C');
    expect(tree.subtree(Path('missing')).isEmpty, isTrue);
    expect(tree.getChild(ChildKey('x')).get(Path('y')), 'Y');
    expect(tree.getChild(ChildKey('missing')).isEmpty, isTrue);
    expect(identical(tree.subtree(Path.empty), tree), isTrue);
  });

  test('remove prunes empty branches', () {
    final ImmutableTree<String> tree = sample().remove(Path('x/y'));
    expect(tree.get(Path('x/y')), isNull);
    expect(tree.children.containsKey(ChildKey('x')), isFalse);
    final ImmutableTree<String> keepsChildren = sample().remove(Path('a'));
    expect(keepsChildren.get(Path('a')), isNull);
    expect(keepsChildren.get(Path('a/b/c')), 'C');
    expect(ImmutableTree<String>('root').remove(Path.empty).isEmpty, isTrue);
    final ImmutableTree<String> unchanged = sample();
    expect(identical(unchanged.remove(Path('nope')), unchanged), isTrue);
  });

  test('setTree replaces a subtree and removes empty ones', () {
    final ImmutableTree<String> tree = sample().setTree(
      Path('a/b'),
      ImmutableTree<String>('B'),
    );
    expect(tree.get(Path('a/b')), 'B');
    expect(tree.get(Path('a/b/c')), isNull);
    final ImmutableTree<String> cleared = sample().setTree(
      Path('x'),
      ImmutableTree<String>.empty(),
    );
    expect(cleared.children.containsKey(ChildKey('x')), isFalse);
  });

  test('forEach visits children before the value, in key order', () {
    final ImmutableTree<String> tree = ImmutableTree<String>.fromMap(
      <Path, String>{
        Path.empty: 'root',
        Path('b'): 'b',
        Path('a'): 'a',
        Path('10'): '10',
        Path('9'): '9',
      },
    );
    final List<String> visited = <String>[];
    tree.forEach((Path path, String value) => visited.add('$path=$value'));
    // Integer-like keys sort numerically first (Android ChildKey order).
    expect(visited, <String>['/9=9', '/10=10', '/a=a', '/b=b', '/=root']);
    expect(
      tree.entries.map((MapEntry<Path, String> e) => e.value).toList(),
      <String>['9', '10', 'a', 'b', 'root'],
    );
  });

  test('forEachChild visits immediate children with values', () {
    final List<String> visited = <String>[];
    sample().forEachChild((ChildKey key, String value) => visited.add(value));
    expect(visited, <String>['A']);
  });

  test('fold folds bottom-up', () {
    final int count = sample().fold<int>(
      (Path path, String? value, Map<ChildKey, int> children) =>
          (value == null ? 0 : 1) +
          children.values.fold<int>(0, (int a, int b) => a + b),
    );
    expect(count, 3);
  });

  test('foldValues accumulates every value', () {
    final List<String> result = sample().foldValues<List<String>>(
      <String>[],
      (Path path, String value, List<String> acc) => <String>[...acc, '$path'],
    );
    expect(result, <String>['/a/b/c', '/a', '/x/y']);
  });

  test('findOnPath returns the first non-null result', () {
    final ImmutableTree<String> tree = sample();
    expect(
      tree.findOnPath<String>(Path('a/b/c'), (Path p, String v) => '$p:$v'),
      '/a:A',
    );
    expect(
      tree.findOnPath<String>(
        Path('a/b/c'),
        (Path p, String v) => v == 'C' ? '$p' : null,
      ),
      '/a/b/c',
    );
    expect(tree.findOnPath<String>(Path('q'), (Path p, String v) => v), isNull);
  });

  test('forEachOnPath visits values above the path and returns the subtree', () {
    final List<String> visited = <String>[];
    final ImmutableTree<String> sub = sample().forEachOnPath(
      Path('a/b/c'),
      (Path p, String v) => visited.add('$p=$v'),
    );
    // The value at the end of the path itself is not visited (JS foreachOnPath).
    expect(visited, <String>['/a=A']);
    expect(sub.value, 'C');
  });

  test('equality is structural', () {
    expect(sample(), sample());
    expect(sample().hashCode, sample().hashCode);
    expect(sample() == sample().set(Path('x/y'), 'other'), isFalse);
  });
}
