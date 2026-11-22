// Tree (Android core/utilities/Tree.java, JS core/util/Tree.ts): the transaction queue tree.
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/util/tree.dart';
import 'package:test/test.dart';

void main() {
  test('subTree creates on demand; a value attaches the path', () {
    final Tree<int> root = Tree<int>();
    final Tree<int> deep = root.subTree(Path('a/b/c'));
    expect(root.hasChildren, isFalse);
    expect(deep.path, Path('a/b/c'));
    deep.value = 1;
    expect(root.hasChildren, isTrue);
    expect(root.subTree(Path('a/b/c')).value, 1);
  });

  test('clearing a value removes empty parents', () {
    final Tree<int> root = Tree<int>();
    root.subTree(Path('a/b')).value = 1;
    root.subTree(Path('a/b')).value = null;
    expect(root.isEmpty, isTrue);
  });

  test('forEachDescendant, children first or not', () {
    final Tree<int> root = Tree<int>();
    root.subTree(Path('a')).value = 1;
    root.subTree(Path('a/b')).value = 2;
    final List<String> before = <String>[];
    root.forEachDescendant(
      (Tree<int> t) => before.add('${t.path}'),
      includeSelf: true,
    );
    expect(before, <String>['/', '/a', '/a/b']);
    final List<String> after = <String>[];
    root.forEachDescendant(
      (Tree<int> t) => after.add('${t.path}'),
      includeSelf: true,
      childrenFirst: true,
    );
    expect(after, <String>['/a/b', '/a', '/']);
  });

  test('forEachAncestor stops when the action returns true', () {
    final Tree<int> root = Tree<int>();
    root.subTree(Path('a')).value = 1;
    final Tree<int> leaf = root.subTree(Path('a/b/c'));
    final List<String> seen = <String>[];
    final bool stopped = leaf.forEachAncestor((Tree<int> t) {
      seen.add('${t.path}');
      return t.value == 1;
    });
    expect(stopped, isTrue);
    expect(seen, <String>['/a/b', '/a']);
    expect(
      leaf.forEachAncestor((Tree<int> t) => false, includeSelf: true),
      isFalse,
    );
  });

  test('forEachImmediateDescendantWithValue stops at the first value', () {
    final Tree<int> root = Tree<int>();
    root.subTree(Path('a/b')).value = 1;
    root.subTree(Path('a/b/c')).value = 2;
    root.subTree(Path('d')).value = 3;
    final List<String> seen = <String>[];
    root.forEachImmediateDescendantWithValue(
      (Tree<int> t) => seen.add('${t.path}'),
    );
    expect(seen, unorderedEquals(<String>['/a/b', '/d']));
  });
}
