// File created by
// Lung Razvan <long1eu>
// on 23/09/2018

import 'dart:typed_data';

import 'package:cloud_firestore_vm/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/target_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/array_transform_operation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/numeric_increment_transform_operation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/server_timestamp_operation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/verify_mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/object_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/values.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/existence_filter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart' as proto_v1;
import 'package:cloud_firestore_vm/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:meta/meta.dart';

/// Serializer that converts to and from Firestore API protos.
class RemoteSerializer {
  RemoteSerializer(this.databaseId) : databaseName = _encodedDatabaseId(databaseId).canonicalString;

  final DatabaseId databaseId;
  final String databaseName;

  // Timestamps and Versions
  proto.Timestamp encodeTimestamp(Timestamp timestamp) {
    return proto.Timestamp.create()
      ..seconds = Int64(timestamp.seconds)
      ..nanos = timestamp.nanoseconds;
  }

  Timestamp decodeTimestamp(proto.Timestamp proto) {
    return Timestamp(proto.seconds.toInt(), proto.nanos);
  }

  proto.Timestamp encodeVersion(SnapshotVersion version) {
    return encodeTimestamp(version.timestamp);
  }

  SnapshotVersion decodeVersion(proto.Timestamp proto) {
    if (proto.seconds == 0 && proto.nanos == 0) {
      return SnapshotVersion.none;
    } else {
      return SnapshotVersion(decodeTimestamp(proto));
    }
  }

  // Names and Keys

  /// Encodes the given document [key] as a fully qualified name. This includes the [databaseId] from the constructor
  /// and the key path.
  String encodeKey(DocumentKey key) {
    return _encodeResourceName(databaseId, key.path);
  }

  DocumentKey decodeKey(String name) {
    final ResourcePath resource = _decodeResourceName(name);
    hardAssert(resource[1] == databaseId.projectId, 'Tried to deserialize key from different project.');
    hardAssert(resource[3] == databaseId.databaseId, 'Tried to deserialize key from different database.');
    return DocumentKey.fromPath(_extractLocalPathFromResourceName(resource));
  }

  String _encodeQueryPath(ResourcePath path) {
    return _encodeResourceName(databaseId, path);
  }

  ResourcePath _decodeQueryPath(String name) {
    final ResourcePath resource = _decodeResourceName(name);
    if (resource.length == 4) {
      // In v1beta1 queries for collections at the root did not have a trailing "/documents". In v1 all resource paths
      // contain "/documents". Preserve the ability to read the v1 form for compatibility with queries persisted in the
      // local query cache.
      return ResourcePath.empty;
    } else {
      return _extractLocalPathFromResourceName(resource);
    }
  }

  /// Encodes a [databaseId] and resource path into the following form:
  /// '/projects/$projectId/database/$databaseId/documents/$path'
  String _encodeResourceName(DatabaseId databaseId, ResourcePath path) {
    return _encodedDatabaseId(databaseId).appendSegment('documents').appendField(path).canonicalString;
  }

  /// Decodes a fully qualified resource name into a resource path and validates that there is a project and database
  /// encoded in the path. There are no guarantees that a local path is also encoded in this resource name.
  ResourcePath _decodeResourceName(String encoded) {
    final ResourcePath resource = ResourcePath.fromString(encoded);
    hardAssert(_isValidResourceName(resource), 'Tried to deserialize invalid key $resource');
    return resource;
  }

  /// Creates the prefix for a fully qualified resource path, without a local path on the end.
  static ResourcePath _encodedDatabaseId(DatabaseId databaseId) {
    return ResourcePath.fromSegments(<String>['projects', databaseId.projectId, 'databases', databaseId.databaseId]);
  }

  /// Decodes a fully qualified resource name into a resource path and validates that there is a project and database
  /// encoded in the path along with a local path.
  static ResourcePath _extractLocalPathFromResourceName(ResourcePath resourceName) {
    hardAssert(
        resourceName.length > 4 && resourceName[4] == 'documents', 'Tried to deserialize invalid key $resourceName');
    return resourceName.popFirst(5);
  }

  /// Validates that a path has a prefix that looks like a valid encoded [databaseId].
  static bool _isValidResourceName(ResourcePath path) {
    // Resource names have at least 4 components (project ID, database ID) and commonly the (root)
    // resource type, e.g. documents
    return path.length >= 4 && path[0] == 'projects' && path[2] == 'databases';
  }

  // Documents

  proto.Document encodeDocument(DocumentKey key, ObjectValue value) {
    return proto.Document.create()
      ..name = encodeKey(key)
      ..fields.addAll(value.fields)
      ..freeze();
  }

  MaybeDocument decodeMaybeDocument(proto.BatchGetDocumentsResponse response) {
    if (response.hasFound()) {
      return _decodeFoundDocument(response);
    } else if (response.hasMissing()) {
      return _decodeMissingDocument(response);
    } else {
      throw ArgumentError('Unknown result case: $response');
    }
  }

  Document _decodeFoundDocument(proto.BatchGetDocumentsResponse response) {
    hardAssert(response.hasFound(), 'Tried to deserialize a found document from a missing document.');
    final DocumentKey key = decodeKey(response.found.name);
    final ObjectValue value = ObjectValue.fromMap(response.found.fields);
    final SnapshotVersion version = decodeVersion(response.found.updateTime);
    hardAssert(version != SnapshotVersion.none, 'Got a document response with no snapshot version');
    return Document(key, version, value, DocumentState.synced);
  }

  NoDocument _decodeMissingDocument(proto.BatchGetDocumentsResponse response) {
    hardAssert(response.hasMissing(), 'Tried to deserialize a missing document from a found document.');
    final DocumentKey key = decodeKey(response.missing);
    final SnapshotVersion version = decodeVersion(response.readTime);
    hardAssert(version != SnapshotVersion.none, 'Got a no document response with no snapshot version');
    return NoDocument(key, version, hasCommittedMutations: false);
  }

  // Mutations

  /// Converts a Mutation model to a Write proto
  proto.Write encodeMutation(Mutation mutation) {
    final proto.Write builder = proto.Write.create();
    if (mutation is SetMutation) {
      builder.update = encodeDocument(mutation.key, mutation.value);
    } else if (mutation is PatchMutation) {
      builder
        ..update = encodeDocument(mutation.key, mutation.value)
        ..updateMask = _encodeDocumentMask(mutation.mask);
    } else if (mutation is DeleteMutation) {
      builder.delete = encodeKey(mutation.key);
    } else if (mutation is VerifyMutation) {
      builder.verify = encodeKey(mutation.key);
    } else {
      throw fail('unknown mutation type ${mutation.runtimeType}');
    }

    builder.updateTransforms.addAll(mutation.fieldTransforms.map(_encodeFieldTransform));

    if (!mutation.precondition.isNone) {
      builder.currentDocument = _encodePrecondition(mutation.precondition);
    }
    return builder..freeze();
  }

  Mutation decodeMutation(proto.Write mutation) {
    final Precondition precondition =
        mutation.hasCurrentDocument() ? _decodePrecondition(mutation.currentDocument) : Precondition.none;

    final List<FieldTransform> fieldTransforms = mutation.updateTransforms.map(_decodeFieldTransform).toList();

    switch (mutation.whichOperation()) {
      case proto.Write_Operation.update:
        if (mutation.hasUpdateMask()) {
          return PatchMutation(
            decodeKey(mutation.update.name),
            ObjectValue.fromMap(mutation.update.fields),
            _decodeDocumentMask(mutation.updateMask),
            precondition,
            fieldTransforms,
          );
        } else {
          return SetMutation(
            decodeKey(mutation.update.name),
            ObjectValue.fromMap(mutation.update.fields),
            precondition,
            fieldTransforms,
          );
        }
        break;
      case proto.Write_Operation.delete:
        return DeleteMutation(decodeKey(mutation.delete), precondition);
      case proto.Write_Operation.verify:
        return VerifyMutation(decodeKey(mutation.verify), precondition);
      default:
        throw fail('Unknown mutation operation: $mutation');
    }
  }

  proto.Precondition _encodePrecondition(Precondition precondition) {
    hardAssert(!precondition.isNone, 'Can\'t serialize an empty precondition');
    final proto.Precondition builder = proto.Precondition.create();
    if (precondition.updateTime != null) {
      return builder
        ..updateTime = encodeVersion(precondition.updateTime)
        ..freeze();
    } else if (precondition.exists != null) {
      return builder
        ..exists = precondition.exists
        ..freeze();
    } else {
      throw fail('Unknown Precondition');
    }
  }

  Precondition _decodePrecondition(proto.Precondition precondition) {
    if (precondition.hasUpdateTime()) {
      return Precondition(updateTime: decodeVersion(precondition.updateTime));
    } else if (precondition.hasExists()) {
      return Precondition(exists: precondition.exists);
    } else {
      return Precondition.none;
    }
  }

  proto.DocumentMask _encodeDocumentMask(FieldMask mask) {
    final proto.DocumentMask builder = proto.DocumentMask.create();
    for (FieldPath path in mask.mask) {
      builder.fieldPaths.add(path.canonicalString);
    }
    return builder..freeze();
  }

  FieldMask _decodeDocumentMask(proto.DocumentMask mask) {
    final Set<FieldPath> paths = mask.fieldPaths.map((String path) => FieldPath.fromServerFormat(path)).toSet();
    return FieldMask(paths);
  }

  proto.DocumentTransform_FieldTransform _encodeFieldTransform(FieldTransform fieldTransform) {
    final TransformOperation transform = fieldTransform.operation;
    if (transform is ServerTimestampOperation) {
      return proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = fieldTransform.fieldPath.canonicalString
        ..setToServerValue = proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME
        ..freeze();
    } else if (transform is ArrayTransformOperationUnion) {
      return proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = fieldTransform.fieldPath.canonicalString
        ..appendMissingElements = proto.ArrayValue(values: transform.elements)
        ..freeze();
    } else if (transform is ArrayTransformOperationRemove) {
      return proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = fieldTransform.fieldPath.canonicalString
        ..removeAllFromArray = proto.ArrayValue(values: transform.elements)
        ..freeze();
    } else if (transform is NumericIncrementTransformOperation) {
      return proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = fieldTransform.fieldPath.canonicalString
        ..increment = transform.operand
        ..freeze();
    } else {
      throw fail('Unknown transform: $transform');
    }
  }

  FieldTransform _decodeFieldTransform(proto.DocumentTransform_FieldTransform fieldTransform) {
    switch (fieldTransform.whichTransformType()) {
      case proto.DocumentTransform_FieldTransform_TransformType.setToServerValue:
        hardAssert(
          fieldTransform.setToServerValue == proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME,
          'Unknown transform setToServerValue: ${fieldTransform.setToServerValue}',
        );
        return FieldTransform(
          FieldPath.fromServerFormat(fieldTransform.fieldPath),
          ServerTimestampOperation.sharedInstance,
        );
        break;
      case proto.DocumentTransform_FieldTransform_TransformType.appendMissingElements:
        return FieldTransform(
          FieldPath.fromServerFormat(fieldTransform.fieldPath),
          ArrayTransformOperationUnion(fieldTransform.appendMissingElements.values),
        );
        break;
      case proto.DocumentTransform_FieldTransform_TransformType.removeAllFromArray:
        return FieldTransform(
          FieldPath.fromServerFormat(fieldTransform.fieldPath),
          ArrayTransformOperationRemove(fieldTransform.removeAllFromArray.values),
        );
        break;
      case proto.DocumentTransform_FieldTransform_TransformType.increment:
        return FieldTransform(
          FieldPath.fromServerFormat(fieldTransform.fieldPath),
          NumericIncrementTransformOperation(fieldTransform.increment),
        );
        break;
      default:
        throw fail('Unknown FieldTransform proto: $fieldTransform');
    }
  }

  MutationResult decodeMutationResult(proto.WriteResult writeProto, SnapshotVersion commitVersion) {
    // NOTE: Deletes don't have an [updateTime] but the commit timestamp from the containing [CommitResponse] or
    // [WriteResponse] indicates essentially that the delete happened no later than that. For our purposes we don't care
    // exactly when the delete happened so long as we can tell when an update on the watch stream is at or later than
    // that change.
    SnapshotVersion version = decodeVersion(writeProto.updateTime);
    if (version == SnapshotVersion.none) {
      version = commitVersion;
    }

    return MutationResult(version, writeProto.transformResults.isEmpty ? null : writeProto.transformResults);
  }

  // Queries

  Map<String, String> encodeListenRequestLabels(TargetData targetData) {
    final String value = _encodeLabel(targetData.purpose);
    if (value == null) {
      return <String, String>{};
    }

    return <String, String>{'goog-listen-tags': value};
  }

  String _encodeLabel(QueryPurpose purpose) {
    switch (purpose) {
      case QueryPurpose.listen:
        return null;
      case QueryPurpose.existenceFilterMismatch:
        return 'existence-filter-mismatch';
      case QueryPurpose.limboResolution:
        return 'limbo-document';
      default:
        throw fail('Unrecognized query purpose: $purpose');
    }
  }

  proto_v1.Target encodeTarget(TargetData targetData) {
    final proto_v1.Target builder = proto_v1.Target.create();
    final Target target = targetData.target;

    if (target.isDocumentQuery) {
      builder.documents = encodeDocumentsTarget(target);
    } else {
      builder.query = encodeQueryTarget(target);
    }

    return builder
      ..targetId = targetData.targetId
      ..resumeToken = targetData.resumeToken
      ..freeze();
  }

  proto.Target_DocumentsTarget encodeDocumentsTarget(Target target) {
    return proto.Target_DocumentsTarget.create()
      ..documents.add(_encodeQueryPath(target.path))
      ..freeze();
  }

  Target decodeDocumentsTarget(proto.Target_DocumentsTarget target) {
    final int count = target.documents.length;
    hardAssert(count == 1, 'DocumentsTarget contained other than 1 document $count');

    final String name = target.documents[0];
    return Query(_decodeQueryPath(name)).toTarget();
  }

  proto.Target_QueryTarget encodeQueryTarget(Target target) {
    // Dissect the path into [parent], [collectionId], and optional [key] filter.
    final proto.Target_QueryTarget builder = proto.Target_QueryTarget.create();
    final proto.StructuredQuery structuredQueryBuilder = proto.StructuredQuery.create();
    final ResourcePath path = target.path;
    if (target.collectionGroup != null) {
      hardAssert(path.length % 2 == 0, 'Collection Group queries should be within a document path or root.');
      builder.parent = _encodeQueryPath(path);

      structuredQueryBuilder.from.add(proto.StructuredQuery_CollectionSelector(
        collectionId: target.collectionGroup,
        allDescendants: true,
      ));
    } else {
      hardAssert(path.length.remainder(2) != 0, 'Document queries with filters are not supported.');
      builder.parent = _encodeQueryPath(path.popLast());

      structuredQueryBuilder.from.add(proto.StructuredQuery_CollectionSelector(collectionId: path.last));
    }

    // Encode the filters.
    if (target.filters.isNotEmpty) {
      structuredQueryBuilder.where = _encodeFilters(target.filters);
    }

    // Encode the orders.
    structuredQueryBuilder.orderBy.addAll(target.orderBy.map(_encodeOrderBy));

    // Encode the limit.
    if (target.hasLimit) {
      structuredQueryBuilder.limit = proto.Int32Value(value: target.limit);
    }

    if (target.startAt != null) {
      structuredQueryBuilder.startAt = _encodeBound(target.startAt);
    }

    if (target.endAt != null) {
      structuredQueryBuilder.endAt = _encodeBound(target.endAt);
    }

    builder.structuredQuery = structuredQueryBuilder;
    return builder..freeze();
  }

  Target decodeQueryTarget(proto.Target_QueryTarget target) {
    ResourcePath path = _decodeQueryPath(target.parent);

    final proto.StructuredQuery query = target.structuredQuery;

    String collectionGroup;
    final int fromCount = query.from.length;
    if (fromCount > 0) {
      hardAssert(fromCount == 1, 'StructuredQuery.from with more than one collection is not supported.');

      final proto_v1.StructuredQuery_CollectionSelector from = query.from[0];
      if (from.allDescendants) {
        collectionGroup = from.collectionId;
      } else {
        path = path.appendSegment(from.collectionId);
      }
    }

    List<Filter> filterBy;
    if (query.hasWhere()) {
      filterBy = _decodeFilters(query.where);
    } else {
      filterBy = <Filter>[];
    }

    List<OrderBy> orderBy;
    final int orderByCount = query.orderBy.length;
    if (orderByCount > 0) {
      orderBy = List<OrderBy>(orderByCount);
      for (int i = 0; i < orderByCount; i++) {
        orderBy[i] = _decodeOrderBy(query.orderBy[i]);
      }
    } else {
      orderBy = <OrderBy>[];
    }

    int limit = Target.kNoLimit;
    if (query.hasLimit()) {
      limit = query.limit.value;
    }

    Bound startAt;
    if (query.hasStartAt()) {
      startAt = _decodeBound(query.startAt);
    }

    Bound endAt;
    if (query.hasEndAt()) {
      endAt = _decodeBound(query.endAt);
    }

    return Query(
      path,
      collectionGroup: collectionGroup,
      filters: filterBy,
      explicitSortOrder: orderBy,
      limit: limit,
      limitType: QueryLimitType.limitToFirst,
      startAt: startAt,
      endAt: endAt,
    ).toTarget();
  }

  // Filters

  proto.StructuredQuery_Filter _encodeFilters(List<Filter> filters) {
    final List<proto.StructuredQuery_Filter> protos = List<proto.StructuredQuery_Filter>(filters.length);
    int i = 0;
    for (Filter filter in filters) {
      if (filter is FieldFilter) {
        protos[i] = encodeUnaryOrFieldFilter(filter);
      }
      i++;
    }
    if (filters.length == 1) {
      return protos[0];
    } else {
      final proto.StructuredQuery_CompositeFilter composite = proto.StructuredQuery_CompositeFilter.create()
        ..op = proto.StructuredQuery_CompositeFilter_Operator.AND
        ..filters.addAll(protos);

      return proto.StructuredQuery_Filter.create()
        ..compositeFilter = composite
        ..freeze();
    }
  }

  List<Filter> _decodeFilters(proto.StructuredQuery_Filter value) {
    List<proto.StructuredQuery_Filter> filters;
    if (value.hasCompositeFilter()) {
      hardAssert(value.compositeFilter.op == proto.StructuredQuery_CompositeFilter_Operator.AND,
          'Only AND-type composite filters are supported, got ${value.compositeFilter.op}');
      filters = value.compositeFilter.filters;
    } else {
      filters = <proto.StructuredQuery_Filter>[value];
    }

    final List<Filter> result = List<Filter>(filters.length);
    int i = 0;
    for (proto.StructuredQuery_Filter filter in filters) {
      if (filter.hasCompositeFilter()) {
        throw fail('Nested composite filters are not supported.');
      } else if (filter.hasFieldFilter()) {
        result[i] = decodeFieldFilter(filter.fieldFilter);
      } else if (filter.hasUnaryFilter()) {
        result[i] = _decodeUnaryFilter(filter.unaryFilter);
      } else {
        throw fail('Unrecognized Filter.filterType $filter');
      }
      i++;
    }

    return result;
  }

  @visibleForTesting
  proto.StructuredQuery_Filter encodeUnaryOrFieldFilter(FieldFilter filter) {
    if (filter.operator == FilterOperator.equal || filter.operator == FilterOperator.notEqual) {
      final proto.StructuredQuery_UnaryFilter unaryProto = proto.StructuredQuery_UnaryFilter(
        field_2: _encodeFieldPath(filter.field),
      );

      if (isNanValue(filter.value)) {
        unaryProto.op = filter.operator == FilterOperator.equal
            ? proto.StructuredQuery_UnaryFilter_Operator.IS_NAN
            : proto.StructuredQuery_UnaryFilter_Operator.IS_NOT_NAN;
      } else if (isNullValue(filter.value)) {
        unaryProto.op = filter.operator == FilterOperator.equal
            ? proto.StructuredQuery_UnaryFilter_Operator.IS_NULL
            : proto.StructuredQuery_UnaryFilter_Operator.IS_NOT_NULL;
      }

      return proto.StructuredQuery_Filter(unaryFilter: unaryProto);
    }
    final proto.StructuredQuery_FieldFilter builder = proto.StructuredQuery_FieldFilter()
      ..field_1 = _encodeFieldPath(filter.field)
      ..op = _encodeFieldFilterOperator(filter.operator)
      ..value = filter.value;

    return proto.StructuredQuery_Filter.create()
      ..fieldFilter = builder
      ..freeze();
  }

  @visibleForTesting
  Filter decodeFieldFilter(proto.StructuredQuery_FieldFilter builder) {
    final FieldPath fieldPath = FieldPath.fromServerFormat(builder.field_1.fieldPath);

    final FilterOperator filterOperator = _decodeFieldFilterOperator(builder.op);
    return FieldFilter(fieldPath, filterOperator, builder.value);
  }

  Filter _decodeUnaryFilter(proto.StructuredQuery_UnaryFilter value) {
    final FieldPath fieldPath = FieldPath.fromServerFormat(value.field_2.fieldPath);
    switch (value.op) {
      case proto.StructuredQuery_UnaryFilter_Operator.IS_NAN:
        return FieldFilter(fieldPath, FilterOperator.equal, NAN_VALUE);
      case proto.StructuredQuery_UnaryFilter_Operator.IS_NULL:
        return FieldFilter(fieldPath, FilterOperator.equal, NULL_VALUE);
        break;
      case proto.StructuredQuery_UnaryFilter_Operator.IS_NOT_NAN:
        return FieldFilter(fieldPath, FilterOperator.notEqual, NAN_VALUE);
        break;
      case proto.StructuredQuery_UnaryFilter_Operator.IS_NOT_NULL:
        return FieldFilter(fieldPath, FilterOperator.notEqual, NULL_VALUE);
        break;
      default:
        throw fail('Unrecognized UnaryFilter.operator ${value.op}');
    }
  }

  proto.StructuredQuery_FieldReference _encodeFieldPath(FieldPath field) {
    return proto.StructuredQuery_FieldReference.create()
      ..fieldPath = field.canonicalString
      ..freeze();
  }

  proto.StructuredQuery_FieldFilter_Operator _encodeFieldFilterOperator(FilterOperator operator) {
    switch (operator) {
      case FilterOperator.lessThan:
        return proto.StructuredQuery_FieldFilter_Operator.LESS_THAN;
      case FilterOperator.lessThanOrEqual:
        return proto.StructuredQuery_FieldFilter_Operator.LESS_THAN_OR_EQUAL;
      case FilterOperator.equal:
        return proto.StructuredQuery_FieldFilter_Operator.EQUAL;
      case FilterOperator.notEqual:
        return proto.StructuredQuery_FieldFilter_Operator.NOT_EQUAL;
      case FilterOperator.graterThan:
        return proto.StructuredQuery_FieldFilter_Operator.GREATER_THAN;
      case FilterOperator.graterThanOrEqual:
        return proto.StructuredQuery_FieldFilter_Operator.GREATER_THAN_OR_EQUAL;
      case FilterOperator.arrayContains:
        return proto.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS;
      case FilterOperator.IN:
        return proto.StructuredQuery_FieldFilter_Operator.IN;
      case FilterOperator.arrayContainsAny:
        return proto.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS_ANY;
      case FilterOperator.notIn:
        return proto.StructuredQuery_FieldFilter_Operator.NOT_IN;
      default:
        throw fail('Unknown operator $operator');
    }
  }

  FilterOperator _decodeFieldFilterOperator(proto.StructuredQuery_FieldFilter_Operator operator) {
    switch (operator) {
      case proto.StructuredQuery_FieldFilter_Operator.LESS_THAN:
        return FilterOperator.lessThan;
      case proto.StructuredQuery_FieldFilter_Operator.LESS_THAN_OR_EQUAL:
        return FilterOperator.lessThanOrEqual;
      case proto.StructuredQuery_FieldFilter_Operator.EQUAL:
        return FilterOperator.equal;
      case proto.StructuredQuery_FieldFilter_Operator.NOT_EQUAL:
        return FilterOperator.notEqual;
      case proto.StructuredQuery_FieldFilter_Operator.GREATER_THAN_OR_EQUAL:
        return FilterOperator.graterThanOrEqual;
      case proto.StructuredQuery_FieldFilter_Operator.GREATER_THAN:
        return FilterOperator.graterThan;
      case proto.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS:
        return FilterOperator.arrayContains;
      case proto.StructuredQuery_FieldFilter_Operator.IN:
        return FilterOperator.IN;
      case proto.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS_ANY:
        return FilterOperator.arrayContainsAny;
      case proto.StructuredQuery_FieldFilter_Operator.NOT_IN:
        return FilterOperator.notIn;
      default:
        throw fail('Unhandled FieldFilter.operator $operator');
    }
  }

  // Property orders

  proto.StructuredQuery_Order _encodeOrderBy(OrderBy orderBy) {
    final proto.StructuredQuery_Order builder = proto.StructuredQuery_Order.create();
    if (orderBy.direction == OrderByDirection.ascending) {
      builder.direction = proto.StructuredQuery_Direction.ASCENDING;
    } else {
      builder.direction = proto.StructuredQuery_Direction.DESCENDING;
    }

    builder.field_1 = _encodeFieldPath(orderBy.field);

    return builder..freeze();
  }

  OrderBy _decodeOrderBy(proto.StructuredQuery_Order value) {
    final FieldPath fieldPath = FieldPath.fromServerFormat(value.field_1.fieldPath);
    OrderByDirection direction;

    switch (value.direction) {
      case proto.StructuredQuery_Direction.ASCENDING:
        direction = OrderByDirection.ascending;
        break;
      case proto.StructuredQuery_Direction.DESCENDING:
        direction = OrderByDirection.descending;
        break;
      default:
        throw fail('Unrecognized direction ${value.direction}');
    }
    return OrderBy.getInstance(direction, fieldPath);
  }

  // Bounds

  proto.Cursor _encodeBound(Bound bound) {
    return proto.Cursor(
      before: bound.before,
      values: bound.position,
    );
  }

  Bound _decodeBound(proto.Cursor value) {
    return Bound(position: value.values, before: value.before);
  }

  // Watch changes

  WatchChange decodeWatchChange(proto.ListenResponse protoChange) {
    switch (protoChange.whichResponseType()) {
      case proto.ListenResponse_ResponseType.targetChange:
        final proto.TargetChange targetChange = protoChange.targetChange;
        WatchTargetChangeType changeType;
        GrpcError cause;
        switch (targetChange.targetChangeType) {
          case proto.TargetChange_TargetChangeType.NO_CHANGE:
            changeType = WatchTargetChangeType.noChange;
            break;
          case proto.TargetChange_TargetChangeType.ADD:
            changeType = WatchTargetChangeType.added;
            break;
          case proto.TargetChange_TargetChangeType.REMOVE:
            changeType = WatchTargetChangeType.removed;
            cause = _fromStatus(targetChange.cause);
            break;
          case proto.TargetChange_TargetChangeType.CURRENT:
            changeType = WatchTargetChangeType.current;
            break;
          case proto.TargetChange_TargetChangeType.RESET:
            changeType = WatchTargetChangeType.reset;
            break;
          default:
            throw ArgumentError('Unknown target change type');
        }
        return WatchChangeWatchTargetChange(
          changeType,
          targetChange.targetIds,
          Uint8List.fromList(targetChange.resumeToken),
          cause,
        );
      case proto.ListenResponse_ResponseType.documentChange:
        final proto.DocumentChange docChange = protoChange.documentChange;
        final List<int> added = docChange.targetIds;
        final List<int> removed = docChange.removedTargetIds;
        final DocumentKey key = decodeKey(docChange.document.name);
        final SnapshotVersion version = decodeVersion(docChange.document.updateTime);
        hardAssert(version != SnapshotVersion.none, 'Got a document change without an update time');
        final ObjectValue data = ObjectValue.fromMap(docChange.document.fields);
        final Document document = Document(key, version, data, DocumentState.synced);
        return WatchChangeDocumentChange(added, removed, document.key, document);
      case proto.ListenResponse_ResponseType.documentDelete:
        final proto.DocumentDelete docDelete = protoChange.documentDelete;
        final List<int> removed = docDelete.removedTargetIds;
        final DocumentKey key = decodeKey(docDelete.document);
        // Note that version might be unset in which case we use SnapshotVersion.none
        final SnapshotVersion version = decodeVersion(docDelete.readTime);
        final NoDocument doc = NoDocument(key, version, hasCommittedMutations: false);
        return WatchChangeDocumentChange(<int>[], removed, doc.key, doc);
      case proto.ListenResponse_ResponseType.filter:
        final proto.ExistenceFilter protoFilter = protoChange.filter;
        // TODO(long1eu): implement existence filter parsing (see b/33076578)
        final ExistenceFilter filter = ExistenceFilter(protoFilter.count);
        final int targetId = protoFilter.targetId;
        return WatchChangeExistenceFilterWatchChange(targetId, filter);
      case proto.ListenResponse_ResponseType.documentRemove:
        final proto.DocumentRemove docRemove = protoChange.documentRemove;
        final List<int> removed = docRemove.removedTargetIds;
        final DocumentKey key = decodeKey(docRemove.document);
        return WatchChangeDocumentChange(<int>[], removed, key, null);
      default:
        throw ArgumentError('Unknown change type set');
    }
  }

  SnapshotVersion decodeVersionFromListenResponse(proto.ListenResponse watchChange) {
    // We have only reached a consistent snapshot for the entire stream if there is a [read_time] set and it applies to
    // all targets (i.e. the list of targets is empty). The backend is guaranteed to send such responses.

    if (!watchChange.hasTargetChange()) {
      return SnapshotVersion.none;
    }

    if (watchChange.targetChange.targetIds.isNotEmpty) {
      return SnapshotVersion.none;
    }
    return decodeVersion(watchChange.targetChange.readTime);
  }

  GrpcError _fromStatus(proto.Status status) {
    // TODO(long1eu): Use details?
    return GrpcError.custom(status.code, status.hasMessage() ? status.message : null);
  }
}
