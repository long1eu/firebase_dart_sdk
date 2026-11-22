// Port of JS test/sparsesnapshottree.test.ts.
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/sparse_snapshot_tree.dart';
import 'package:test/test.dart';

void main() {
  test('Basic remember and find.', () {
    final SparseSnapshotTree st = SparseSnapshotTree();
    st.remember(Path('a/b'), nodeFromJson('sdfsd'));
    expect(st.find(Path('a/b'))!.isEmpty, isFalse);
    expect(st.find(Path('a')), isNull);
  });

  test('Find inside an existing snapshot', () {
    final SparseSnapshotTree st = SparseSnapshotTree();
    Node node = nodeFromJson(<String, Object?>{
      'a': 'sdfsd',
      'x': 5,
      '999i': true,
    });
    node = node.updateImmediateChild(
      ChildKey('apples'),
      nodeFromJson(<String, Object?>{'goats': 88}),
    );
    st.remember(Path('t/tt'), node);

    expect(st.find(Path('t/tt'))!.isEmpty, isFalse);
    expect(st.find(Path('t/tt/a'))!.value, 'sdfsd');
    expect(st.find(Path('t/tt/999i'))!.value, true);
    expect(st.find(Path('t/tt/apples'))!.isEmpty, isFalse);
    expect(st.find(Path('t/tt/apples/goats'))!.value, 88);
  });

  test('Write a snapshot inside a snapshot.', () {
    final SparseSnapshotTree st = SparseSnapshotTree();
    st.remember(
      Path('t'),
      nodeFromJson(<String, Object?>{
        'a': <String, Object?>{'b': 'v'},
      }),
    );
    st.remember(Path('t/a/rr'), nodeFromJson(19));
    expect(st.find(Path('t/a/b'))!.value, 'v');
    expect(st.find(Path('t/a/rr'))!.value, 19);
  });

  test('Write a null value and confirm it is remembered.', () {
    final SparseSnapshotTree st = SparseSnapshotTree();
    st.remember(Path('awq/fff'), nodeFromJson(null));
    expect(st.find(Path('awq/fff')), ChildrenNode.empty);
    expect(st.find(Path('awq/sdf')), isNull);
    expect(st.find(Path('awq/fff/jjj')), ChildrenNode.empty);
    expect(st.find(Path('awq/sdf/sdf/q')), isNull);
  });

  test('Overwrite with null and confirm it is remembered.', () {
    final SparseSnapshotTree st = SparseSnapshotTree();
    st.remember(
      Path('t'),
      nodeFromJson(<String, Object?>{
        'a': <String, Object?>{'b': 'v'},
      }),
    );
    expect(st.find(Path('t'))!.isEmpty, isFalse);
    st.remember(Path('t'), ChildrenNode.empty);
    expect(st.find(Path('t'))!.isEmpty, isTrue);
  });

  test('Simple remember and forget.', () {
    final SparseSnapshotTree st = SparseSnapshotTree();
    st.remember(
      Path('t'),
      nodeFromJson(<String, Object?>{
        'a': <String, Object?>{'b': 'v'},
      }),
    );
    expect(st.find(Path('t'))!.isEmpty, isFalse);
    st.forget(Path('t'));
    expect(st.find(Path('t')), isNull);
  });

  test('Forget the root.', () {
    final SparseSnapshotTree st = SparseSnapshotTree();
    st.remember(
      Path('t'),
      nodeFromJson(<String, Object?>{
        'a': <String, Object?>{'b': 'v'},
      }),
    );
    expect(st.find(Path('t'))!.isEmpty, isFalse);
    st.forget(Path.empty);
    expect(st.find(Path('t')), isNull);
  });

  test('Forget snapshot inside snapshot.', () {
    final SparseSnapshotTree st = SparseSnapshotTree();
    st.remember(
      Path('t'),
      nodeFromJson(<String, Object?>{
        'a': <String, Object?>{'b': 'v', 'c': 9, 'art': false},
      }),
    );
    expect(st.find(Path('t/a/c'))!.isEmpty, isFalse);
    expect(st.find(Path('t'))!.isEmpty, isFalse);

    st.forget(Path('t/a/c'));
    expect(st.find(Path('t')), isNull);
    expect(st.find(Path('t/a')), isNull);
    expect(st.find(Path('t/a/b'))!.value, 'v');
    expect(st.find(Path('t/a/c')), isNull);
    expect(st.find(Path('t/a/art'))!.value, false);
  });

  test('Forget path shallower than snapshots.', () {
    final SparseSnapshotTree st = SparseSnapshotTree();
    st.remember(Path('t/x1'), nodeFromJson(false));
    st.remember(Path('t/x2'), nodeFromJson(true));
    st.forget(Path('t'));
    expect(st.find(Path('t')), isNull);
  });

  test('Iterate children.', () {
    final SparseSnapshotTree st = SparseSnapshotTree();
    st.remember(
      Path('t'),
      nodeFromJson(<String, Object?>{'b': 'v', 'c': 9, 'art': false}),
    );
    st.remember(Path('q'), ChildrenNode.empty);

    final List<String> keys = <String>[];
    st.forEachChild((ChildKey key, SparseSnapshotTree child) {
      keys.add(key.name);
    });
    expect(keys, unorderedEquals(<String>['t', 'q']));
  });

  test('Iterate trees.', () {
    final SparseSnapshotTree st = SparseSnapshotTree();

    int count = 0;
    st.forEachTree(Path.empty, (Path path, Node tree) => count += 1);
    expect(count, 0);

    st.remember(Path('t'), nodeFromJson(1));
    st.remember(Path('a/b'), nodeFromJson(2));
    st.remember(Path('a/x/g'), nodeFromJson(3));
    st.remember(Path('a/x/null'), nodeFromJson(null));

    final Map<Path, Object?> seen = <Path, Object?>{};
    st.forEachTree(Path('q'), (Path path, Node node) {
      seen[path] = node.value;
    });
    expect(seen, <Path, Object?>{
      Path('q/t'): 1,
      Path('q/a/b'): 2,
      Path('q/a/x/g'): 3,
      Path('q/a/x/null'): null,
    });
  });

  test('Set leaf, then forget deeper path', () {
    final SparseSnapshotTree st = SparseSnapshotTree();
    st.remember(Path('foo'), nodeFromJson('bar'));
    // It is not safe to remove this node.
    expect(st.forget(Path('foo/baz')), isFalse);
  });
}
