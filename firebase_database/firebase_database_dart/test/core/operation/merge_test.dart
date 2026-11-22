// Own tests for Merge.operationForChild (Android core/operation/Merge.java).
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/operation/operation.dart';
import 'package:firebase_database_dart/src/core/operation/operation_source.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:test/test.dart';

void main() {
  final CompoundWrite children = CompoundWrite.fromValue(<String, Object?>{
    'a': 1,
    'b/c': 2,
  });

  group('at the root', () {
    final Merge op = Merge(OperationSource.user, Path.empty, children);

    test('a child set whole becomes an overwrite', () {
      final Overwrite child = op.operationForChild(ChildKey('a'))! as Overwrite;
      expect(child.path, Path.empty);
      expect(child.snapshot, nodeFromJson(1));
      expect(child.source, same(OperationSource.user));
    });

    test('a child with deeper writes stays a merge', () {
      final Merge child = op.operationForChild(ChildKey('b'))! as Merge;
      expect(child.path, Path.empty);
      expect(child.children.rootWrite(), isNull);
      expect(child.children.getCompleteNode(Path('c')), nodeFromJson(2));
      expect(child.source, same(OperationSource.user));
    });

    test('an untouched child gives null', () {
      expect(op.operationForChild(ChildKey('z')), isNull);
    });
  });

  group('below the root', () {
    final Merge op = Merge(OperationSource.server, Path('x/y'), children);

    test('the front child pops the path', () {
      final Merge child = op.operationForChild(ChildKey('x'))! as Merge;
      expect(child.path, Path('y'));
      expect(child.children, same(children));
      expect(child.source, same(OperationSource.server));
    });

    test('another child gives null', () {
      expect(op.operationForChild(ChildKey('q')), isNull);
    });
  });
}
