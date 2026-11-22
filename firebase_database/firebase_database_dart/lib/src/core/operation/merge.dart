// JS: core/operation/Merge.ts; Android: core/operation/Merge.java.
part of 'operation.dart';

/// Writes [children] below [path]. JS: `core/operation/Merge.ts`; Android:
/// `core/operation/Merge.java`.
final class Merge extends Operation {
  /// Creates a merge.
  const Merge(super.source, super.path, this.children);

  /// The writes, relative to [path].
  final CompoundWrite children;

  @override
  Operation? operationForChild(ChildKey key) => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
