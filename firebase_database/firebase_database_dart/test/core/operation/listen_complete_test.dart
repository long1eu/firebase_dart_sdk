// Own tests for ListenComplete.operationForChild (Android core/operation/ListenComplete.java).
import 'package:firebase_database_dart/src/core/operation/operation.dart';
import 'package:firebase_database_dart/src/core/operation/operation_source.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:test/test.dart';

void main() {
  test('at the root stays at the root', () {
    const ListenComplete op = ListenComplete(
      OperationSource.server,
      Path.empty,
    );
    final ListenComplete child =
        op.operationForChild(ChildKey('a'))! as ListenComplete;
    expect(child.path, Path.empty);
    expect(child.source, same(OperationSource.server));
  });

  test('below the root pops the front', () {
    final ListenComplete op = ListenComplete(
      OperationSource.server,
      Path('a/b'),
    );
    final ListenComplete child =
        op.operationForChild(ChildKey('a'))! as ListenComplete;
    expect(child.path, Path('b'));
  });
}
