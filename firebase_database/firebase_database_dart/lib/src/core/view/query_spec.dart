/// A query: path plus parameters. JS: `QueryContext` (`core/view/EventRegistration.ts`) as used by
/// the sync tree; Android: `core/view/QuerySpec.java`.
library;

import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';

/// The identity of a query in the sync tree and in persistence.
final class QuerySpec {
  /// Creates a spec.
  const QuerySpec(this.path, this.params);

  /// The default query at [path].
  factory QuerySpec.defaultAt(Path path) => throw UnimplementedError();

  /// The query at [path] with the parameters of a wire object.
  factory QuerySpec.fromPathAndWireObject(
    Path path,
    Map<String, Object?> wire,
  ) => throw UnimplementedError();

  /// The path.
  final Path path;

  /// The parameters.
  final QueryParams params;

  /// The index of [params].
  Index get index => throw UnimplementedError();

  /// Whether this is the default query.
  bool get isDefault => throw UnimplementedError();

  /// Whether the query loads all data at [path].
  bool get loadsAllData => throw UnimplementedError();

  /// The form the connection takes ([ListenSpec]).
  ListenSpec toListenSpec() => throw UnimplementedError();

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
}
