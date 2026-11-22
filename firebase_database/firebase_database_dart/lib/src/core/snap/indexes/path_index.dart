/// Orders children by the value at a child path. JS: `core/snap/indexes/PathIndex.ts`; Android:
/// `snapshot/PathIndex.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/named_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// Orders children by the value at [indexPath] below each child (`orderByChild`).
final class PathIndex extends Index {
  /// Creates the index; [indexPath] must not be empty or `.priority`.
  const PathIndex(this.indexPath);

  /// The child path.
  final Path indexPath;

  @override
  int compare(NamedNode a, NamedNode b) => throw UnimplementedError();

  @override
  bool isDefinedOn(Node node) => throw UnimplementedError();

  @override
  NamedNode makePost(Node indexValue, ChildKey name) =>
      throw UnimplementedError();

  @override
  NamedNode get maxPost => throw UnimplementedError();

  @override
  String get queryDefinition => throw UnimplementedError();

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
