// Own tests for Overwrite.operationForChild (Android core/operation/Overwrite.java).
import 'package:firebase_database_dart/src/core/operation/operation.dart';
import 'package:firebase_database_dart/src/core/operation/operation_source.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:test/test.dart';

void main() {
  final Node snap = nodeFromJson(<String, Object?>{'a': 1, 'b': 2});

  test('at the root gives the child of the snapshot', () {
    const Path root = Path.empty;
    final Overwrite op = Overwrite(OperationSource.server, root, snap);
    final Overwrite child = op.operationForChild(ChildKey('a'))! as Overwrite;
    expect(child.path, Path.empty);
    expect(child.snapshot, nodeFromJson(1));
    expect(child.source, same(OperationSource.server));

    final Overwrite missing = op.operationForChild(ChildKey('z'))! as Overwrite;
    expect(missing.snapshot, ChildrenNode.empty);
  });

  test('below the root pops the front and keeps the snapshot', () {
    final Overwrite op = Overwrite(OperationSource.user, Path('a/b'), snap);
    final Overwrite child = op.operationForChild(ChildKey('a'))! as Overwrite;
    expect(child.path, Path('b'));
    expect(child.snapshot, same(snap));
    expect(child.source, same(OperationSource.user));
  });
}
