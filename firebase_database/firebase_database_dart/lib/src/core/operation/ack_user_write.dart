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

  @override
  Operation? operationForChild(ChildKey key) => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
