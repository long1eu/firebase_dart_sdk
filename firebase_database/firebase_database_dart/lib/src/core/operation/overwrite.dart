// JS: core/operation/Overwrite.ts; Android: core/operation/Overwrite.java.
part of 'operation.dart';

/// Replaces the data at [path] with [snapshot]. JS: `core/operation/Overwrite.ts`; Android:
/// `core/operation/Overwrite.java`.
final class Overwrite extends Operation {
  /// Creates an overwrite.
  const Overwrite(super.source, super.path, this.snapshot);

  /// The new data.
  final Node snapshot;

  @override
  Operation? operationForChild(ChildKey key) => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
