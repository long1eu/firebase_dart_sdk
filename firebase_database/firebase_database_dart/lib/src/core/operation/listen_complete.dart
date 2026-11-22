// JS: core/operation/ListenComplete.ts; Android: core/operation/ListenComplete.java.
part of 'operation.dart';

/// The server finished sending the initial data of a listen at [path]. JS:
/// `core/operation/ListenComplete.ts`; Android: `core/operation/ListenComplete.java`.
final class ListenComplete extends Operation {
  /// Creates the operation.
  const ListenComplete(super.source, super.path);

  /// The same listen complete one level down (still at the root when [path] is empty).
  /// Android: `ListenComplete.operationForChild`.
  @override
  Operation? operationForChild(ChildKey key) {
    if (path.isEmpty) {
      return ListenComplete(source, Path.empty);
    }
    return ListenComplete(source, path.popFront());
  }

  /// Android: `ListenComplete.toString`.
  @override
  String toString() => 'ListenComplete { path=$path, source=$source }';
}
