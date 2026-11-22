/// An immutable copy of the data at a location. JS: `api/Reference_impl.ts` (`DataSnapshot`); Android:
/// `DataSnapshot.java`.
library;

import 'package:firebase_database_dart/src/api/database_reference.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:meta/meta.dart';

/// The data at a location at one moment, from an event, `Query.get`, `Query.once` or a transaction.
///
/// [value] holds plain Dart data: `null`, `bool`, `int`, `double`, `String`, `List<Object?>` or
/// `Map<String, Object?>`, at every depth, with no converters. Read it with patterns:
///
/// ```dart
/// final DataSnapshot snapshot = await db.ref('users/ada').get();
/// if (snapshot.value case {'name': String name, 'age': num age}) {
///   print('$name is $age');
/// }
/// ```
///
/// Numbers: an integral number reads as `int`, any other as `double`, the same on the VM and with
/// dart2wasm; a `5.0` you wrote reads back as the `int` 5, also before the server answers. On dart2js an
/// integral value is both `int` and `double`, so match numeric fields as `num`, never `double`. Integers
/// beyond 2^53 stored in integer form are exact on the VM (up to 64 bits) but not on the web. A `-0.0`
/// stored by another client reads as the double `-0.0`.
///
/// Lists: a node whose keys are all integer-like, with largest key below twice the number of keys, reads as a
/// `List` with `null` in the holes, as in the JS SDK. The same location can therefore read as a `Map` after
/// one change and a `List` after another; iterate [children] when the shape can vary.
@immutable
final class DataSnapshot {
  /// Creates the snapshot of [node] at [ref], whose children iterate in [index] order. The client creates
  /// them.
  @internal
  const DataSnapshot.internal(this.ref, this.node, this.index);

  /// The location this data was read from. For the snapshot of a child event, the child's location.
  final DatabaseReference ref;

  /// The data.
  @internal
  final Node node;

  /// The order of [children]: the index of the query that produced the snapshot.
  @internal
  final Index index;

  /// The last segment of [ref]'s path, or null at the root.
  String? get key => throw UnimplementedError();

  /// Whether the location holds data. A location with no data reads [value] as null.
  bool get exists => throw UnimplementedError();

  /// The data as plain Dart values (see the class documentation), or null when there is none.
  ///
  /// It is built once per snapshot and then cached. It is unmodifiable at every depth: changing a map or list
  /// throws [UnsupportedError] where the change is attempted. Copy it to change it.
  Object? get value => throw UnimplementedError();

  /// The priority of the location: null, a `num` or a `String`. Every snapshot has its own, child snapshots
  /// included.
  Object? get priority => throw UnimplementedError();

  /// The snapshot of the location at [path] below this one. [path] may have several segments (`'a/b'`) and
  /// may name a list index (`'0'`). A missing child is a snapshot whose [exists] is false.
  DataSnapshot child(String path) => throw UnimplementedError();

  /// Whether the location at [path] below this one holds data; [path] may have several segments.
  bool hasChild(String path) => throw UnimplementedError();

  /// Whether the location has children (a leaf value or no data has none).
  bool get hasChildren => throw UnimplementedError();

  /// The number of direct children.
  int get childrenCount => throw UnimplementedError();

  /// The direct children in the query's index order, built lazily, each with its own [ref] and [priority].
  ///
  /// ```dart
  /// for (final DataSnapshot child in snapshot.children) {
  ///   print('${child.key}: ${child.value}');
  /// }
  /// ```
  Iterable<DataSnapshot> get children => throw UnimplementedError();

  /// The data in export form, as the JS SDK's `exportVal()`: a node with a priority becomes a map with
  /// `.value` (for a leaf) or its children plus `.priority`. So `jsonEncode(snapshot)` works.
  Object? toJson() => throw UnimplementedError();
}
