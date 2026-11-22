/// Compound hash of a node, sent as `ch` with a listen. JS: none; Android:
/// `snapshot/CompoundHash.java`.
library;

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';

/// The state a [SplitStrategy] looks at while the hash is being built.
abstract interface class CompoundHashBuildState {
  /// Whether a range is open.
  bool get buildingRange;

  /// The length of the current range text.
  int get currentHashLength;

  /// The path of the current leaf.
  Path get currentPath;
}

/// Decides whether to close the current range at the current leaf.
typedef SplitStrategy = bool Function(CompoundHashBuildState state);

/// A node split into ranges: n [hashes] and the n-1 [posts] (last leaf paths) between them.
final class CompoundHash {
  /// Creates a hash; [posts] has one element fewer than [hashes].
  const CompoundHash(this.posts, this.hashes);

  /// Builds the hash of [node], splitting with [strategy] (by default ranges of
  /// `max(512, sqrt(size * 100))` characters).
  factory CompoundHash.fromNode(Node node, [SplitStrategy? strategy]) =>
      throw UnimplementedError();

  /// The range end paths.
  final List<Path> posts;

  /// The base64 SHA-1 of each range; the last is `''`.
  final List<String> hashes;
}
