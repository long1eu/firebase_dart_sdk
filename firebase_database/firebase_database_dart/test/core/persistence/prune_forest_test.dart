// Port of Android PruneForestTest.java.
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/prune_forest.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:test/test.dart';

ChildKey ck(String name) => ChildKey(name);

void main() {
  test('empty does not affect any paths', () {
    final PruneForest forest = PruneForest();
    expect(forest.affectsPath(Path.empty), isFalse);
    expect(forest.affectsPath(Path('foo')), isFalse);
  });

  test('prune affects path', () {
    PruneForest forest = PruneForest();
    forest = forest.prune(Path('foo/bar'));
    forest = forest.keep(Path('foo/bar/baz'));
    expect(forest.affectsPath(Path('foo')), isTrue);
    expect(forest.affectsPath(Path('baz')), isFalse);
    expect(forest.affectsPath(Path('baz/bar')), isFalse);
    expect(forest.affectsPath(Path('foo/bar')), isTrue);
    expect(forest.affectsPath(Path('foo/bar/baz')), isTrue);
    expect(forest.affectsPath(Path('foo/bar/qux')), isTrue);
  });

  test('prunesAnything works', () {
    final PruneForest empty = PruneForest();
    expect(empty.prunesAnything(), isFalse);
    expect(empty.prune(Path('foo')).prunesAnything(), isTrue);

    expect(
      empty.prune(Path('foo/bar')).keep(Path('foo')).prunesAnything(),
      isFalse,
    );

    expect(
      empty.prune(Path('foo')).keep(Path('foo/bar')).prunesAnything(),
      isTrue,
    );
  });

  test('keep under prune works', () {
    PruneForest forest = PruneForest();
    forest = forest.prune(Path('foo/bar'));
    forest = forest.keep(Path('foo/bar/baz'));
    forest = forest.keepAll(Path('foo/bar'), <ChildKey>{ck('qux'), ck('quu')});
  });

  test('prune under keep throws', () {
    PruneForest forest = PruneForest();
    forest = forest.prune(Path('foo'));
    forest = forest.keep(Path('foo/bar'));
    expect(() => forest.prune(Path('foo/bar/baz')), throwsA(anything));
    expect(
      () => forest.pruneAll(Path('foo/bar'), <ChildKey>{ck('qux'), ck('quu')}),
      throwsA(anything),
    );
  });

  test('child keeps prune info', () {
    PruneForest forest = PruneForest();
    forest = forest.keep(Path('foo/bar'));
    expect(forest.child(ck('foo')).affectsPath(Path('bar')), isTrue);
    expect(
      forest.child(ck('foo')).child(ck('bar')).affectsPath(Path('')),
      isTrue,
    );
    expect(
      forest
          .child(ck('foo'))
          .child(ck('bar'))
          .child(ck('baz'))
          .affectsPath(Path('')),
      isTrue,
    );

    forest = PruneForest().prune(Path('foo/bar'));
    expect(forest.child(ck('foo')).affectsPath(Path('bar')), isTrue);
    expect(
      forest.child(ck('foo')).child(ck('bar')).affectsPath(Path('')),
      isTrue,
    );
    expect(
      forest
          .child(ck('foo'))
          .child(ck('bar'))
          .child(ck('baz'))
          .affectsPath(Path('')),
      isTrue,
    );

    expect(forest.child(ck('non-existent')).affectsPath(Path('')), isFalse);
  });

  test('shouldPrune works', () {
    PruneForest forest = PruneForest();
    forest = forest.prune(Path('foo'));
    forest = forest.keep(Path('foo/bar/baz'));
    expect(forest.shouldPruneUnkeptDescendants(Path('foo')), isTrue);
    expect(forest.shouldPruneUnkeptDescendants(Path('foo/bar')), isTrue);
    expect(forest.shouldPruneUnkeptDescendants(Path('foo/bar/baz')), isFalse);
    expect(forest.shouldPruneUnkeptDescendants(Path('qux')), isFalse);
  });

  test('foldKeptNodes visits all kept nodes', () {
    PruneForest forest = PruneForest();
    forest = forest.prune(Path('foo'));
    forest = forest.keepAll(Path('foo/bar'), <ChildKey>{ck('qux'), ck('quu')});
    forest = forest.keep(Path('foo/baz'));
    forest = forest.keep(Path('bar'));
    final Set<Path> actualPaths = <Path>{};
    forest.foldKeptNodes<Object?>(null, (Path relativePath, Object? accum) {
      actualPaths.add(relativePath);
      return null;
    });
    expect(actualPaths, <Path>{
      Path('foo/bar/qux'),
      Path('foo/bar/quu'),
      Path('foo/baz'),
      Path('bar'),
    });
  });
}
