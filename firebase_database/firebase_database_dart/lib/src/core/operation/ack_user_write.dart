// JS: core/operation/AckUserWrite.ts; Android: core/operation/AckUserWrite.java.
part of 'operation.dart';

/// The server acknowledged (or [revert]: rejected) a user write; [affectedTree] marks the paths
/// the write touched. Always from the user source. JS: `core/operation/AckUserWrite.ts`; Android:
/// `core/operation/AckUserWrite.java`.
final class AckUserWrite extends Operation {
  /// Creates an acknowledgement.
  const AckUserWrite(Path path, this.affectedTree, {required this.revert})
    : super(OperationSource.user, path);

  /// The touched paths (value true).
  final ImmutableTree<bool> affectedTree;

  /// Whether the write is rolled back.
  final bool revert;

  /// Below a non-empty [path], the same ack one level down ([key] must be the front of [path]);
  /// at the root, this ack when the whole tree is affected, else the ack of [key]'s subtree.
  /// Android: `AckUserWrite.operationForChild`.
  @override
  Operation? operationForChild(ChildKey key) {
    if (!path.isEmpty) {
      if (path.front != key) {
        throw StateError('operationForChild called for unrelated child.');
      }
      return AckUserWrite(path.popFront(), affectedTree, revert: revert);
    } else if (affectedTree.value != null) {
      if (!affectedTree.children.isEmpty) {
        throw StateError(
          'affectedTree should not have overlapping affected paths.',
        );
      }
      // All child locations are affected as well; return the same operation.
      return this;
    }
    final ImmutableTree<bool> childTree = affectedTree.subtree(
      Path.fromKeys(<ChildKey>[key]),
    );
    return AckUserWrite(Path.empty, childTree, revert: revert);
  }

  /// Android: `AckUserWrite.toString`.
  @override
  String toString() =>
      'AckUserWrite { path=$path, revert=$revert, affectedTree=$affectedTree }';
}
