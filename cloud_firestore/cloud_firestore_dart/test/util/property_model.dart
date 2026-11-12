// Generators of internal model objects (documents, queries, targets,
// mutations) on top of the value generators of property.dart.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as api;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/array_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_extremum_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_increment_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/server_timestamp_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/verify_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/unknown_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:mockito/mockito.dart';

import 'property.dart';

/// The database of the generated model objects.
final DatabaseId modelDatabaseId = DatabaseId.forProject('project');

class _ModelFirestore extends Mock implements api.Firestore {
  @override
  DatabaseId get databaseId => modelDatabaseId;

  @override
  UserDataConverter get dataConverter => _converter;
}

/// A Firestore that only knows its database id: enough to create references
/// and snapshots in unit tests.
final api.Firestore modelFirestore = _ModelFirestore();

final UserDataConverter _converter = UserDataConverter(modelDatabaseId);

/// The model value of a user value.
FieldValue toModel(Object? value) =>
    _converter.parseQueryValue(value, allowArrays: true);

api.DocumentReference<Map<String, Object?>> modelReference(String path) =>
    api.DocumentReference<Map<String, Object?>>(
        DocumentKey.fromPathString(path), modelFirestore);

extension ModelGen on Gen {
  /// A model value with every type, references and the BSON classes.
  FieldValue modelValue({bool bson = true}) =>
      toModel(value(bson: bson, reference: modelReference));

  ObjectValue objectValue({bool bson = true}) =>
      toModel(map(bson: bson, reference: modelReference)) as ObjectValue;

  DocumentKey documentKey() => DocumentKey.fromPathString(pick(const <String>[
        'coll/a', 'coll/b', 'coll/c', 'coll/A', 'coll/é', 'coll/a/sub/x', //
        'other/a', 'coll/10', 'coll/9', 'coll/doc with space',
      ]));

  SnapshotVersion snapshotVersion() => SnapshotVersion(
      api.Timestamp(between(1, 2000000000), below(1000000) * 1000));

  /// A document as the remote document cache holds it (a document with
  /// local mutations is never stored).
  Document document() => Document(
      documentKey(),
      snapshotVersion(),
      chance(80) ? DocumentState.synced : DocumentState.committedMutations,
      objectValue());

  MaybeDocument maybeDocument() {
    switch (below(4)) {
      case 0:
        return NoDocument(documentKey(), snapshotVersion(),
            hasCommittedMutations: chance(50));
      case 1:
        return UnknownDocument(documentKey(), snapshotVersion());
      default:
        return document();
    }
  }

  FieldPath fieldPath() {
    if (chance(15)) {
      return FieldPath.fromSegments(<String>[
        pick(const <String>['k.dot', 'k space', 'k`tick', 'kü', '0', 'a.b'])
      ]);
    }
    return FieldPath.fromSegments(
        <String>[for (int i = between(1, 2); i > 0; i--) fieldName()]);
  }

  static const List<FilterOperator> _comparisons = <FilterOperator>[
    FilterOperator.lessThan,
    FilterOperator.lessThanOrEqual,
    FilterOperator.equal,
    FilterOperator.notEqual,
    FilterOperator.graterThan,
    FilterOperator.graterThanOrEqual,
  ];

  /// A filter on a field (never on the document key).
  FieldFilter fieldFilter({bool bson = true}) {
    final FieldPath path = fieldPath();
    switch (below(8)) {
      case 0:
        return FieldFilter(
            path, FilterOperator.arrayContains, modelValue(bson: bson));
      case 1:
        return FieldFilter(
            path, FilterOperator.arrayContainsAny, _operands(bson));
      case 2:
        return FieldFilter(path, FilterOperator.IN, _operands(bson));
      case 3:
        return FieldFilter(path, FilterOperator.NOT_IN, _operands(bson));
      default:
        return FieldFilter(path, pick(_comparisons), modelValue(bson: bson));
    }
  }

  ArrayValue _operands(bool bson) => ArrayValue.fromList(<FieldValue>[
        for (int i = between(1, 3); i > 0; i--) modelValue(bson: bson)
      ]);

  /// A field filter or a tree of AND / OR filters.
  Filter filter({bool bson = true, int depth = 2}) {
    if (depth == 0 || chance(65)) {
      return fieldFilter(bson: bson);
    }
    return CompositeFilter(<Filter>[
      // At least two: the SDK never builds a composite of one filter
      // (see the test of `Filter.or([single])`).
      for (int i = between(2, 3); i > 0; i--)
        filter(bson: bson, depth: depth - 1)
    ], chance(50) ? CompositeFilterOperator.and : CompositeFilterOperator.or);
  }

  OrderBy orderBy() => OrderBy.getInstance(
      chance(50) ? OrderByDirection.ascending : OrderByDirection.descending,
      chance(15) ? FieldPath.keyPath : fieldPath());

  /// A query with filters, orderings, cursors and a limit. It is well formed
  /// for the SDK; it does not have to be one the backend accepts.
  Query query({bool bson = true}) {
    Query query = chance(20)
        ? Query(ResourcePath.empty,
            collectionGroup: pick(const <String>['coll', 'sub']))
        : Query(ResourcePath.fromString(
            pick(const <String>['coll', 'coll/a/sub', 'other'])));
    for (int i = below(size.clamp(0, 3) + 1); i > 0; i--) {
      query = query.filter(filter(bson: bson));
    }
    final Set<FieldPath> ordered = <FieldPath>{};
    for (int i = below(size.clamp(0, 3) + 1); i > 0; i--) {
      final OrderBy order = orderBy();
      if (ordered.add(order.field)) {
        query = query.orderBy(order);
      }
      if (order.field.isKeyField) {
        break;
      }
    }
    Bound bound() {
      final List<OrderBy> orders = query.orderByConstraints;
      return Bound(position: <FieldValue>[
        for (int i = 0; i < between(1, orders.length); i++)
          orders[i].field.isKeyField
              ? ReferenceValue.valueOf(modelDatabaseId, documentKey())
              : modelValue(bson: bson)
      ], inclusive: chance(50));
    }

    if (chance(30)) {
      query = query.startAt(bound());
    }
    if (chance(30)) {
      query = query.endAt(bound());
    }
    if (chance(40)) {
      final int limit = between(1, 50);
      query = chance(70) || query.explicitSortOrder.isEmpty
          ? query.limitToFirst(limit)
          : query.limitToLast(limit);
    }
    return query;
  }

  TransformOperation _transform() {
    NumberValue number() => chance(50)
        ? IntegerValue.valueOf(integer())
        : DoubleValue.valueOf(float());
    List<FieldValue> elements() =>
        <FieldValue>[for (int i = between(1, 3); i > 0; i--) modelValue()];
    switch (below(6)) {
      case 0:
        return ServerTimestampOperation();
      case 1:
        return ArrayTransformOperationUnion(elements());
      case 2:
        return ArrayTransformOperationRemove(elements());
      case 3:
        return NumericIncrementTransformOperation(number());
      case 4:
        return NumericMinimumTransformOperation(number());
      default:
        return NumericMaximumTransformOperation(number());
    }
  }

  List<FieldTransform> fieldTransforms() {
    final Map<FieldPath, FieldTransform> transforms =
        <FieldPath, FieldTransform>{};
    for (int i = below(3); i > 0; i--) {
      final FieldPath path = fieldPath();
      transforms[path] = FieldTransform(path, _transform());
    }
    return transforms.values.toList();
  }

  Precondition precondition() {
    switch (below(4)) {
      case 0:
        return Precondition(exists: true);
      case 1:
        return Precondition(exists: false);
      case 2:
        return Precondition(updateTime: snapshotVersion());
      default:
        return Precondition.none;
    }
  }

  /// A mutation of [key] (or of a generated key).
  Mutation mutation([DocumentKey? key]) {
    final DocumentKey target = key ?? documentKey();
    switch (below(8)) {
      case 0:
        return DeleteMutation(target, precondition());
      case 1:
        return VerifyMutation(
            target, Precondition(updateTime: snapshotVersion()));
      case 2:
      case 3:
      case 4:
        return SetMutation(
            target, objectValue(), Precondition.none, fieldTransforms());
      default:
        ObjectValue data = ObjectValue.empty;
        final Set<FieldPath> mask = <FieldPath>{};
        for (int i = below(4); i > 0; i--) {
          final FieldPath path = fieldPath();
          // A mask cannot hold a path together with one of its prefixes
          // when both carry values.
          if (mask
              .any((FieldPath p) => p.isPrefixOf(path) || path.isPrefixOf(p))) {
            continue;
          }
          mask.add(path);
          if (chance(75)) {
            data = data.set(path, modelValue());
          }
        }
        return PatchMutation(
            target,
            data,
            FieldMask(mask),
            chance(60) ? Precondition(exists: true) : precondition(),
            fieldTransforms());
    }
  }
}
