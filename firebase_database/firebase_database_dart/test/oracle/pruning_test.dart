// Oracle: Android androidTest/.../core/persistence/PruningTest.java, one test per upstream test, in
// upstream order. Upstream runs on SqlPersistenceStorageEngine; here on the engine [runPruningOracle]
// is given (InMemoryPersistenceStorageEngine by default).
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/prune_forest.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:test/test.dart';

import 'oracle_support.dart';

void main() => runPruningOracle(openInMemoryEngine);

/// Android `IntegrationTestHelpers.leafNodeOfSize`.
Node _leafNodeOfSize(int size) {
  const String pattern =
      'abdefghijklmopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final StringBuffer builder = StringBuffer();
  for (int i = 0; i < size - pattern.length; i = i + pattern.length) {
    builder.write(pattern);
  }
  builder.write(pattern.substring(0, size - builder.length));
  return n(builder.toString());
}

/// Android `PruningTest.PruneForestBuilder`.
final class _PruneForestBuilder {
  _PruneForestBuilder([PruneForest? pruneForest])
    : _pruneForest = pruneForest ?? PruneForest();

  final PruneForest _pruneForest;

  _PruneForestBuilder prune(String prunePathString) =>
      _PruneForestBuilder(_pruneForest.prune(Path(prunePathString)));

  _PruneForestBuilder pruneExcept(
    String prunePathString,
    Set<String> keepPathStrings,
  ) {
    final Path prunePath = Path(prunePathString);
    PruneForest newPruneForest = _pruneForest.prune(prunePath);
    for (final String keepPathString in keepPathStrings) {
      newPruneForest = newPruneForest.keep(
        prunePath.childPath(Path(keepPathString)),
      );
    }
    return _PruneForestBuilder(newPruneForest);
  }

  PruneForest get() => _pruneForest;
}

/// The PruningTest suite against the engines [openEngine] opens (clean ones).
///
/// [keepsOverwrittenRows] is true for an engine that, like Android's SQLite one, keeps the write at
/// `/` as its own row when a later write lands below it; only such an engine can pass
/// `testPruningBelowDocuments2`.
void runPruningOracle(
  OpenEngine openEngine, {
  bool keepsOverwrittenRows = false,
}) {
  final Node emptyNode = ChildrenNode.empty;
  final Node largeNode = _leafNodeOfSize(5 * 1024 * 1024);
  final Node abcNode = n(<String, Object?>{
    'a': <String, Object?>{'aa': 1.1, 'ab': 1.2},
    'b': 2,
    'c': 3,
  });
  final Node aNode = emptyNode.updateChild(p('a'), abcNode.getChild(p('a')));
  final Node bcNode = abcNode.updateChild(p('a'), emptyNode);
  final Node defNode = n(<String, Object?>{'d': 4, 'e': 5, 'f': 6});
  final Node dNode = emptyNode.updateChild(p('d'), defNode.getChild(p('d')));
  final _PruneForestBuilder pf = _PruneForestBuilder();

  late PersistenceStorageEngine engine;

  void writeToCache(String path, Node node) => inEngineTransaction(
    engine,
    () => engine.overwriteServerCache(Path(path), node),
  );

  void pruneCache(String locationToPrune, _PruneForestBuilder pruneForest) =>
      inEngineTransaction(
        engine,
        () => engine.pruneCache(Path(locationToPrune), pruneForest.get()),
      );

  Node cache(String pathString) => engine.serverCache(Path(pathString));

  setUp(() {
    engine = openEngine();
    inEngineTransaction(engine, () {
      engine.removeAllUserWrites();
      // Android getCleanStorageEngine also calls purgeCache, which our interface lacks: the
      // factory opens a clean engine.
    });
  });

  tearDown(() => engine.close());

  group('PruningTest', () {
    // Write document at root, prune it.
    test('test010', () {
      writeToCache('', abcNode);
      pruneCache('', pf.prune(''));
      expectNode(cache(''), emptyNode);
    });

    // Write document at /x, prune it via PruneForest for /x, at root.
    test('test020', () {
      writeToCache('x', abcNode);
      pruneCache('', pf.prune('x'));
      expectNode(cache('x'), emptyNode);
    });

    // Write document at /x, prune it via PruneForest for root, at /x.
    test('test030', () {
      writeToCache('x', abcNode);
      pruneCache('x', pf.prune(''));
      expectNode(cache('x'), emptyNode);
    });

    // Write document at /x, prune it via PruneForest for root, at root
    test('test040', () {
      writeToCache('x', abcNode);
      pruneCache('', pf.prune(''));
      expectNode(cache('x'), emptyNode);
    });

    // Write document at /x/y, prune it via PruneForest for /y, at /x
    test('test050', () {
      writeToCache('x/y', abcNode);
      pruneCache('x', pf.prune('y'));
      expectNode(cache('x/y'), emptyNode);
    });

    // Write abc at /x/y, prune /x/y except b,c via PruneForest for /x/y -b,c, at root
    test('test060', () {
      writeToCache('x/y', abcNode);
      pruneCache('', pf.pruneExcept('x/y', <String>{'b', 'c'}));
      expectNode(cache('x/y'), bcNode);
    });

    // Write abc at /x/y, prune /x/y except b,c via PruneForest for /y -b,c, at /x
    test('test070', () {
      writeToCache('x/y', abcNode);
      pruneCache('x', pf.pruneExcept('y', <String>{'b', 'c'}));
      expectNode(cache('x/y'), bcNode);
    });

    // Write abc at /x/y, prune /x/y except not-there via PruneForest for /x/y -d, at root
    test('test080', () {
      writeToCache('x/y', abcNode);
      pruneCache('', pf.pruneExcept('x/y', <String>{'not-there'}));
      expectNode(cache('x/y'), emptyNode);
    });

    // Write abc at / and def at /a, prune all via PruneForest for / at root
    test('test090', () {
      writeToCache('', abcNode);
      writeToCache('a', defNode);
      pruneCache('', pf.prune(''));
      expectNode(cache(''), emptyNode);
    });

    // Write abc at / and def at /a, prune all except b,c via PruneForest for root -b,c, at root
    test('test100', () {
      writeToCache('', abcNode);
      writeToCache('a', defNode);
      pruneCache('', pf.pruneExcept('', <String>{'b', 'c'}));
      expectNode(cache(''), bcNode);
    });

    // Write abc at /x and def at /x/a, prune /x except b,c via PruneForest for /x -b,c, at root
    test('test110', () {
      writeToCache('x', abcNode);
      writeToCache('x/a', defNode);
      pruneCache('', pf.pruneExcept('x', <String>{'b', 'c'}));
      expectNode(cache('x'), bcNode);
    });

    // Write abc at /x and def at /x/a, prune /x except b,c via PruneForest for root -b,c, at /x
    test('test120', () {
      writeToCache('x', abcNode);
      writeToCache('x/a', defNode);
      pruneCache('x', pf.pruneExcept('', <String>{'b', 'c'}));
      expectNode(cache('x'), bcNode);
    });

    // Write abc at /x and def at /x/a, prune /x except a via PruneForest for /x -a, at root
    test('test130', () {
      writeToCache('x', abcNode);
      writeToCache('x/a', defNode);
      expectNode(cache('x'), abcNode.updateChild(p('a'), defNode));
      pruneCache('', pf.pruneExcept('x', <String>{'a'}));
      expectNode(cache('x'), emptyNode.updateChild(p('a'), defNode));
    });

    // Write abc at /x and def at /x/a, prune /x except a via PruneForest for root -a, at /x
    test('test140', () {
      writeToCache('x', abcNode);
      writeToCache('x/a', defNode);
      pruneCache('x', pf.pruneExcept('', <String>{'a'}));
      expectNode(cache('x'), emptyNode.updateChild(p('a'), defNode));
    });

    // Write abc at /x and def at /x/a, prune /x except a/d via PruneForest for /x -a/d, at root
    test('test150', () {
      writeToCache('x', abcNode);
      writeToCache('x/a', defNode);
      pruneCache('', pf.pruneExcept('x', <String>{'a/d'}));
      expectNode(cache('x'), emptyNode.updateChild(p('a'), dNode));
    });

    // Write abc at /x and def at /x/a, prune /x except a/d via PruneForest for / -a/d, at /x
    test('test160', () {
      writeToCache('x', abcNode);
      writeToCache('x/a', defNode);
      pruneCache('x', pf.pruneExcept('', <String>{'a/d'}));
      expectNode(cache('x'), emptyNode.updateChild(p('a'), dNode));
    });

    // Write abc at /x and def at /x/a/aa, prune /x except a via PruneForest for /x -a, at root
    test('test170', () {
      writeToCache('x', abcNode);
      writeToCache('x/a/aa', defNode);
      pruneCache('', pf.pruneExcept('x', <String>{'a'}));
      expectNode(cache('x'), aNode.updateChild(p('a/aa'), defNode));
    });

    // Write abc at /x and def at /x/a/aa, prune /x except a via PruneForest for / -a, at /x
    test('test180', () {
      writeToCache('x', abcNode);
      writeToCache('x/a/aa', defNode);
      pruneCache('x', pf.pruneExcept('', <String>{'a'}));
      expectNode(cache('x'), aNode.updateChild(p('a/aa'), defNode));
    });

    // Write abc at /x and def at /x/a/aa, prune /x except a/aa via PruneForest for /x -a/aa, at
    // root
    test('test190', () {
      writeToCache('x', abcNode);
      writeToCache('x/a/aa', defNode);
      pruneCache('', pf.pruneExcept('x', <String>{'a/aa'}));
      expectNode(cache('x'), emptyNode.updateChild(p('a/aa'), defNode));
    });

    // Write abc at /x and def at /x/a/aa, prune /x except a/aa via PruneForest for / -a/aa, at /x
    test('test200', () {
      writeToCache('x', abcNode);
      writeToCache('x/a/aa', defNode);
      pruneCache('x', pf.pruneExcept('', <String>{'a/aa'}));
      expectNode(cache('x'), emptyNode.updateChild(p('a/aa'), defNode));
    });

    // Write large node at /x, prune x via PruneForest for x at root
    test('test210', () {
      writeToCache('x', largeNode);
      pruneCache('', pf.prune('x'));
      expectNode(cache('x'), emptyNode);
    });

    // Write abc at x and large node at /x/a, prune x except a via PruneForest for / -a, at x
    test('test220', () {
      writeToCache('x', abcNode);
      writeToCache('x/a', largeNode);
      pruneCache('x', pf.pruneExcept('', <String>{'a'}));
      expectNode(cache('x'), emptyNode.updateChild(p('a'), largeNode));
    });

    // This isn't an expected situation so we ignore documents above a prune location.
    // Write abc at /, prune /a via PruneForest for root, at /a
    test('testPruningBelowDocuments1', () {
      writeToCache('', abcNode);
      pruneCache('a', pf.prune(''));
      expectNode(cache(''), abcNode);
    });

    // This isn't an expected situation so we currently ignore documents above a prune location.
    // Write abc at / and def at /a, prune /a via PruneForest for root, at /a
    test(
      'testPruningBelowDocuments2',
      () {
        writeToCache('', abcNode);
        writeToCache('a', defNode);
        pruneCache('a', pf.prune(''));
        // DEF gets pruned, but not ABC.
        expectNode(cache(''), abcNode);
      },
      skip: keepsOverwrittenRows
          ? null
          : 'Not portable: the engine folds the write at /a into the one at /, so the first value '
                'of /a is gone; upstream calls the situation unexpected.',
    );
  });
}
