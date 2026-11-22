/// Where an operation comes from. JS: `core/operation/Operation.ts` (`OperationSource`,
/// `newOperationSource*`); Android: `core/operation/OperationSource.java`.
library;

import 'package:firebase_database_dart/src/core/view/query_params.dart';

/// The origin of an operation: the user, or the server (optionally for one tagged query).
final class OperationSource {
  const OperationSource._({required this.fromUser, required this.tagged})
    : queryParams = null;

  /// A user write.
  static const OperationSource user = OperationSource._(
    fromUser: true,
    tagged: false,
  );

  /// Server data for untagged listens.
  static const OperationSource server = OperationSource._(
    fromUser: false,
    tagged: false,
  );

  /// Server data for the tagged query with [queryParams].
  const OperationSource.forServerTaggedQuery(QueryParams this.queryParams)
    : fromUser = false,
      tagged = true;

  /// Whether the user wrote it.
  final bool fromUser;

  /// The parameters of the tagged query, else null.
  final QueryParams? queryParams;

  /// Whether it is for one tagged query.
  final bool tagged;

  /// Whether the server sent it. Android: `OperationSource.isFromServer`.
  bool get fromServer => !fromUser;

  /// Android: `OperationSource.toString`.
  @override
  String toString() =>
      'OperationSource{source=${fromUser ? 'User' : 'Server'}, '
      'queryParams=$queryParams, tagged=$tagged}';
}
