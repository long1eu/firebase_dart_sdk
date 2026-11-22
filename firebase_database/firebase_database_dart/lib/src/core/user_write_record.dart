/// A pending user write. JS: `core/WriteTree.ts` (`WriteRecord`); Android:
/// `core/UserWriteRecord.java`.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';

/// A user overwrite (with [overwrite]) or merge (with [merge]) at [path], as kept in the write
/// tree and in persistence.
final class UserWriteRecord {
  /// An overwrite; [visible] is false for transactions with `applyLocally: false`.
  const UserWriteRecord.overwrite(
    this.writeId,
    this.path,
    Node this.overwrite, {
    required this.visible,
  }) : merge = null;

  /// A merge (always visible).
  const UserWriteRecord.merge(this.writeId, this.path, CompoundWrite this.merge)
    : overwrite = null,
      visible = true;

  /// The write id.
  final WriteId writeId;

  /// The path.
  final Path path;

  /// The new data of an overwrite.
  final Node? overwrite;

  /// The writes of a merge.
  final CompoundWrite? merge;

  /// Whether the write shows in events.
  final bool visible;

  /// Whether this is a merge.
  bool get isMerge => merge != null;

  /// Whether this is an overwrite.
  bool get isOverwrite => overwrite != null;

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
