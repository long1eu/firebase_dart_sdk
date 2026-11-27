/// A query: path plus parameters. JS: `QueryContext` (`core/view/EventRegistration.ts`) as used by
/// the sync tree; Android: `core/view/QuerySpec.java`.
library;

import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:meta/meta.dart';

/// The identity of a query in the sync tree and in persistence.
final class QuerySpec {
  /// Creates a spec. Outside this package, use [QuerySpec.defaultAt] or
  /// [QuerySpec.fromPathAndWireObject].
  @internal
  const QuerySpec(this.path, this.params);

  /// The default query at [path].
  factory QuerySpec.defaultAt(Path path) =>
      QuerySpec(path, QueryParams.defaultParams);

  /// The query at [path] with the parameters of a wire object, as [toWireObject] returns it.
  factory QuerySpec.fromPathAndWireObject(
    Path path,
    Map<String, Object?> wire,
  ) => QuerySpec(path, QueryParams.fromWireObject(wire));

  /// The path.
  final Path path;

  /// The parameters. Outside this package, use [toWireObject].
  @internal
  final QueryParams params;

  /// The index of the parameters.
  Index get index => params.index;

  /// Whether this is the default query.
  bool get isDefault => params.isDefault;

  /// Whether the query loads all data at [path].
  bool get loadsAllData => params.loadsAllData;

  /// The parameters as the wire object the server receives (`{}` for the default query). An
  /// engine stores it and passes it back to [QuerySpec.fromPathAndWireObject], which builds an
  /// equal spec.
  Map<String, Object?> toWireObject() => params.toWireObject();

  /// The form the connection takes ([ListenSpec]).
  @internal
  ListenSpec toListenSpec() => ListenSpec(
    path: path.toString(),
    queryObject: params.toWireObject(),
    queryIdentifier: params.toQueryIdentifier(),
    isDefault: params.isDefault,
    loadsAllData: params.loadsAllData,
    indexName: params.index.queryDefinition,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuerySpec && other.path == path && other.params == params;

  @override
  int get hashCode => Object.hash(path, params);

  @override
  String toString() => '$path:$params';
}
