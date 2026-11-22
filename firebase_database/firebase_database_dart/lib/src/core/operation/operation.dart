/// Operations applied to the sync tree. JS: `core/operation/Operation.ts`; Android:
/// `core/operation/Operation.java`.
///
/// The subclasses live in part files, one per upstream file: `overwrite.dart`, `merge.dart`,
/// `ack_user_write.dart`, `listen_complete.dart`.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/operation/operation_source.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/util/immutable_tree.dart';

part 'ack_user_write.dart';
part 'listen_complete.dart';
part 'merge.dart';
part 'overwrite.dart';

/// A change to apply at [path]: an [Overwrite], a [Merge], an [AckUserWrite] or a
/// [ListenComplete]. Switch over it exhaustively.
sealed class Operation {
  const Operation(this.source, this.path);

  /// Where it comes from.
  final OperationSource source;

  /// Where it applies, relative to the sync point it is given to.
  final Path path;

  /// The part of this operation that applies to child [key], or null when none does.
  Operation? operationForChild(ChildKey key);
}
