// Own tests for WriteTreeRef: each method is the WriteTree method at the ref's path (Android
// core/WriteTreeRef.java).
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/write_tree.dart';
import 'package:firebase_database_dart/src/core/write_tree_ref.dart';
import 'package:test/test.dart';

Node n(Object? json) => nodeFromJson(json);
Path p(String path) => Path(path);
ChildKey k(String key) => ChildKey(key);

void main() {
  late WriteTree tree;
  late WriteTreeRef ref;
  setUp(() {
    tree = WriteTree();
    ref = tree.childWrites(p('a'));
  });

  test('child extends the path and shares the tree', () {
    final WriteTreeRef child = ref.child(k('b'));
    expect(child.treePath, p('a/b'));
    expect(child.writeTree, same(tree));
  });

  test('shadowingWrite is relative to the ref', () {
    tree.addOverwrite(p('a/b'), n(1), 1, visible: true);
    expect(ref.shadowingWrite(p('b')), n(1));
    expect(ref.shadowingWrite(p('c')), isNull);
    expect(ref.shadowingWrite(p('')), isNull);
  });

  test('calcCompleteEventCache', () {
    tree.addOverwrite(p('a/b'), n(1), 1, visible: true);
    tree.addOverwrite(p('a/c'), n(2), 2, visible: false);
    final Node server = n(<String, Object?>{'d': 3});
    expect(
      ref.calcCompleteEventCache(server),
      n(<String, Object?>{'b': 1, 'd': 3}),
    );
    expect(
      ref.calcCompleteEventCache(server, includeHiddenWrites: true),
      n(<String, Object?>{'b': 1, 'c': 2, 'd': 3}),
    );
    expect(
      ref.calcCompleteEventCache(server, writeIdsToExclude: <int>[1]),
      server,
    );
  });

  test('calcCompleteEventChildren', () {
    tree.addOverwrite(p('a/b'), n(1), 1, visible: true);
    expect(
      ref.calcCompleteEventChildren(n(<String, Object?>{'c': 2})),
      n(<String, Object?>{'b': 1, 'c': 2}),
    );
  });

  test('calcEventCacheAfterServerOverwrite', () {
    tree.addOverwrite(p('a/b'), n(1), 1, visible: true);
    final Node server = n(<String, Object?>{'b': 9, 'c': 8});
    expect(
      ref.calcEventCacheAfterServerOverwrite(p('b'), null, server),
      isNull,
    );
    expect(ref.calcEventCacheAfterServerOverwrite(p('c'), null, server), n(8));
  });

  test('calcNextNodeAfterPost', () {
    tree.addOverwrite(p('a/b'), n(null), 1, visible: true);
    expect(
      ref.calcNextNodeAfterPost(
        n(<String, Object?>{'a': 1, 'b': 2, 'c': 3}),
        NamedNode(k('a'), n(1)),
        priorityIndex,
        reverse: false,
      ),
      NamedNode(k('c'), n(3)),
    );
  });

  test('calcCompleteChild', () {
    tree.addOverwrite(p('a/b'), n(1), 1, visible: true);
    expect(
      ref.calcCompleteChild(
        k('b'),
        CacheNode(ChildrenNode.empty, fullyInitialized: false, filtered: false),
      ),
      n(1),
    );
  });
}
