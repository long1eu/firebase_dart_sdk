// Own tests for AckUserWrite.operationForChild (Android core/operation/AckUserWrite.java).
import 'package:firebase_database_dart/src/core/operation/operation.dart';
import 'package:firebase_database_dart/src/core/operation/operation_source.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';
import 'package:test/test.dart';

void main() {
  test('is from the user', () {
    final AckUserWrite op = AckUserWrite(
      Path.empty,
      ImmutableTree<bool>(true),
      revert: false,
    );
    expect(op.source, same(OperationSource.user));
  });

  test('below the root pops the front and keeps tree and revert', () {
    final ImmutableTree<bool> affected = ImmutableTree<bool>(true);
    final AckUserWrite op = AckUserWrite(Path('a/b'), affected, revert: true);
    final AckUserWrite child =
        op.operationForChild(ChildKey('a'))! as AckUserWrite;
    expect(child.path, Path('b'));
    expect(child.affectedTree, same(affected));
    expect(child.revert, isTrue);
  });

  test('below the root an unrelated child throws', () {
    final AckUserWrite op = AckUserWrite(
      Path('a/b'),
      ImmutableTree<bool>(true),
      revert: false,
    );
    expect(() => op.operationForChild(ChildKey('z')), throwsStateError);
  });

  test('a fully affected root returns the same operation', () {
    final AckUserWrite op = AckUserWrite(
      Path.empty,
      ImmutableTree<bool>(true),
      revert: false,
    );
    expect(op.operationForChild(ChildKey('a')), same(op));
  });

  test('a root value with children throws', () {
    final AckUserWrite op = AckUserWrite(
      Path.empty,
      ImmutableTree<bool>(true).set(Path('x'), true),
      revert: false,
    );
    expect(() => op.operationForChild(ChildKey('a')), throwsStateError);
  });

  test('otherwise the subtree of the child', () {
    final ImmutableTree<bool> affected = ImmutableTree<bool>.fromMap(
      <Path, bool>{Path('a/b'): true, Path('c'): true},
    );
    final AckUserWrite op = AckUserWrite(Path.empty, affected, revert: true);

    final AckUserWrite a = op.operationForChild(ChildKey('a'))! as AckUserWrite;
    expect(a.path, Path.empty);
    expect(a.affectedTree.value, isNull);
    expect(a.affectedTree.get(Path('b')), isTrue);
    expect(a.revert, isTrue);

    final AckUserWrite c = op.operationForChild(ChildKey('c'))! as AckUserWrite;
    expect(c.affectedTree.value, isTrue);

    final AckUserWrite z = op.operationForChild(ChildKey('z'))! as AckUserWrite;
    expect(z.affectedTree.isEmpty, isTrue);
  });
}
