// JS: core/operation/Overwrite.ts; Android: core/operation/Overwrite.java.
part of 'operation.dart';

/// Replaces the data at [path] with [snapshot]. JS: `core/operation/Overwrite.ts`; Android:
/// `core/operation/Overwrite.java`.
final class Overwrite extends Operation {
  /// Creates an overwrite.
  const Overwrite(super.source, super.path, this.snapshot);

  /// The new data.
  final Node snapshot;

  /// At the root, the child [key] of [snapshot]; else the same overwrite one level down.
  /// Android: `Overwrite.operationForChild`.
  @override
  Operation? operationForChild(ChildKey key) {
    if (path.isEmpty) {
      return Overwrite(source, Path.empty, snapshot.getImmediateChild(key));
    }
    return Overwrite(source, path.popFront(), snapshot);
  }

  /// Android: `Overwrite.toString`.
  @override
  String toString() =>
      'Overwrite { path=$path, source=$source, snapshot=$snapshot }';
}
