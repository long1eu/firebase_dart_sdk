// Own tests for SnapshotHolder (Android core/SnapshotHolder.java).
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/snapshot_holder.dart';
import 'package:test/test.dart';

void main() {
  test('starts empty', () {
    expect(SnapshotHolder().getNode(Path.empty), ChildrenNode.empty);
  });

  test('updates and reads by path', () {
    final SnapshotHolder holder = SnapshotHolder();
    holder.updateSnapshot(Path('a/b'), nodeFromJson(1));
    holder.updateSnapshot(Path('a/c'), nodeFromJson(2));
    expect(
      holder.getNode(Path('a')),
      nodeFromJson(<String, Object?>{'b': 1, 'c': 2}),
    );
    expect(holder.getNode(Path('a/b')), nodeFromJson(1));
    holder.updateSnapshot(Path('a'), nodeFromJson(null));
    expect(holder.getNode(Path.empty), ChildrenNode.empty);
  });
}
