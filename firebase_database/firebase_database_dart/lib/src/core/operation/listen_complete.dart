// JS: core/operation/ListenComplete.ts; Android: core/operation/ListenComplete.java.
part of 'operation.dart';

/// The server finished sending the initial data of a listen at [path]. JS:
/// `core/operation/ListenComplete.ts`; Android: `core/operation/ListenComplete.java`.
final class ListenComplete extends Operation {
  /// Creates the operation.
  const ListenComplete(super.source, super.path);

  @override
  Operation? operationForChild(ChildKey key) => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
