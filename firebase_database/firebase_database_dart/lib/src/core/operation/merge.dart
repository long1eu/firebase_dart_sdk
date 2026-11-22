// JS: core/operation/Merge.ts; Android: core/operation/Merge.java.
part of 'operation.dart';

/// Writes [children] below [path]. JS: `core/operation/Merge.ts`; Android:
/// `core/operation/Merge.java`.
final class Merge extends Operation {
  /// Creates a merge.
  const Merge(super.source, super.path, this.children);

  /// The writes, relative to [path].
  final CompoundWrite children;

  /// At the root, the writes below [key] (an [Overwrite] when they set [key] whole, null when
  /// there are none); else the same merge one level down, or null for an unrelated child.
  /// Android: `Merge.operationForChild`.
  @override
  Operation? operationForChild(ChildKey key) {
    if (path.isEmpty) {
      final CompoundWrite childTree = children.childCompoundWrite(
        Path.fromKeys(<ChildKey>[key]),
      );
      if (childTree.isEmpty) {
        // This child is unaffected.
        return null;
      }
      final Node? rootWrite = childTree.rootWrite();
      if (rootWrite != null) {
        return Overwrite(source, Path.empty, rootWrite);
      }
      return Merge(source, Path.empty, childTree);
    } else if (path.front == key) {
      return Merge(source, path.popFront(), children);
    }
    // The merge does not affect this child.
    return null;
  }

  /// Android: `Merge.toString`.
  @override
  String toString() =>
      'Merge { path=$path, source=$source, children=$children }';
}
