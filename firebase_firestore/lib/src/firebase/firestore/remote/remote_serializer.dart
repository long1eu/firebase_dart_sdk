// File created by
// Lung Razvan <long1eu>
// on 23/09/2018

import 'dart:typed_data';

import 'package:firebase_firestore/src/firebase/firestore/blob.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/bound.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/nan_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/null_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/order_by.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/relation_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/geo_point.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/array_transform_operation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/server_timestamp_operation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/transform_mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/array_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/blob_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/bool_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/double_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/geo_point_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/integer_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/null_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/reference_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/string_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/timestamp_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/existence_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/index.dart' as proto_beta;
import 'package:firebase_firestore/src/proto/google/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';

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

  // GeoPoint

  proto.LatLng _encodeGeoPoint(GeoPoint geoPoint) {
    return proto.LatLng.create()
      ..latitude = geoPoint.latitude
      ..longitude = geoPoint.longitude;
  }

  GeoPoint _decodeGeoPoint(proto.LatLng latLng) {
    return GeoPoint(latLng.latitude, latLng.longitude);
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
    if (path.length == 0) {
      // If the path is empty, the backend requires we leave off the /documents at the end.
      return databaseName;
    }
    return _encodeResourceName(databaseId, path);
  }

  ResourcePath _decodeQueryPath(String name) {
    final ResourcePath resource = _decodeResourceName(name);
    if (resource.length == 4) {
      // Path missing the trailing documents path segment, indicating an empty path.
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

  // Values

  /// Converts the [FieldValue] model passed into the [Value] proto equivalent.
  proto_beta.Value encodeValue(FieldValue value) {
    final proto_beta.Value builder = proto_beta.Value.create();

    if (value is NullValue) {
      return builder //
        ..nullValue = proto.NullValue.NULL_VALUE;
    }

    hardAssert(value.value != null, 'Encoded field value should not be null.');

    if (value is BoolValue) {
      builder.booleanValue = value.value;
    } else if (value is IntegerValue) {
      builder.integerValue = Int64(value.value);
    } else if (value is DoubleValue) {
      builder.doubleValue = value.value;
    } else if (value is StringValue) {
      builder.stringValue = value.value;
    } else if (value is ArrayValue) {
      builder.arrayValue = _encodeArrayValue(value);
    } else if (value is ObjectValue) {
      builder.mapValue = _encodeMapValue(value);
    } else if (value is TimestampValue) {
      builder.timestampValue = encodeTimestamp(value.value);
    } else if (value is GeoPointValue) {
      builder.geoPointValue = _encodeGeoPoint(value.value);
    } else if (value is BlobValue) {
      builder.bytesValue = value.value.bytes;
    } else if (value is ReferenceValue) {
      final DatabaseId id = value.databaseId;
      final DocumentKey key = value.value;
      builder.referenceValue = _encodeResourceName(id, key.path);
    } else {
      throw fail('Can\'t serialize $value');
    }

    return builder..freeze();
  }

  /// Converts from the proto [Value] format to the model [FieldValue] format
  FieldValue decodeValue(proto_beta.Value proto) {
    switch (proto.whichValueType()) {
      case proto_beta.Value_ValueType.booleanValue:
        return BoolValue.valueOf(proto.booleanValue);
      case proto_beta.Value_ValueType.integerValue:
        return IntegerValue.valueOf(proto.integerValue.toInt());
      case proto_beta.Value_ValueType.doubleValue:
        return DoubleValue.valueOf(proto.doubleValue);
      case proto_beta.Value_ValueType.referenceValue:
        final ResourcePath resourceName = _decodeResourceName(proto.referenceValue);
        final DatabaseId id = DatabaseId.forDatabase(resourceName[1], resourceName[3]);
        final DocumentKey key = DocumentKey.fromPath(_extractLocalPathFromResourceName(resourceName));
        return ReferenceValue.valueOf(id, key);
      case proto_beta.Value_ValueType.mapValue:
        return _decodeMapValue(proto.mapValue);
      case proto_beta.Value_ValueType.geoPointValue:
        final dynamic /*proto.LatLng*/ latLng = proto.geoPointValue;
        return GeoPointValue.valueOf(_decodeGeoPoint(latLng));
      case proto_beta.Value_ValueType.arrayValue:
        return _decodeArrayValue(proto.arrayValue);
      case proto_beta.Value_ValueType.timestampValue:
        final Timestamp timestamp = decodeTimestamp(proto.timestampValue);
        return TimestampValue.valueOf(timestamp);
      case proto_beta.Value_ValueType.nullValue:
        return NullValue.nullValue();

      case proto_beta.Value_ValueType.stringValue:
        return StringValue.valueOf(proto.stringValue);
      case proto_beta.Value_ValueType.bytesValue:
        final Blob bytes = Blob(Uint8List.fromList(proto.bytesValue));
        return BlobValue.valueOf(bytes);
      default:
        throw fail('Unknown value $proto');
    }
  }

  proto.ArrayValue _encodeArrayValue(ArrayValue value) {
    final List<FieldValue> internalValue = value.internalValue;

    final proto.ArrayValue arrayBuilder = proto.ArrayValue.create();
    for (FieldValue subValue in internalValue) {
      arrayBuilder.values.add(encodeValue(subValue));
    }

    return arrayBuilder..freeze();
  }

  ArrayValue _decodeArrayValue(proto.ArrayValue protoArray) {
    final int count = protoArray.values.length;
    final List<FieldValue> wrappedList = List<FieldValue>(count);
    for (int i = 0; i < count; i++) {
      wrappedList[i] = decodeValue(protoArray.values[i]);
    }
    return ArrayValue.fromList(wrappedList);
  }

  proto.MapValue _encodeMapValue(ObjectValue value) {
    final proto.MapValue builder = proto.MapValue.create();
    for (MapEntry<String, FieldValue> entry in value.internalValue) {
      builder.fields[entry.key] = encodeValue(entry.value);
    }
    return builder..freeze();
  }

  ObjectValue _decodeMapValue(proto.MapValue value) {
    return decodeMapFields(value.fields);
  }

  // PORTING NOTE: There's no encodeFields here because there's no way to write  it that doesn't
  // involve creating a temporary map.
  ObjectValue decodeMapFields(Map<String, proto_beta.Value> fields) {
    ObjectValue result = ObjectValue.empty;
    for (String key in fields.keys) {
      final FieldPath path = FieldPath.fromSingleSegment(key);
      final FieldValue value = decodeValue(fields[key]);
      result = result.set(path, value);
    }
    return result;
  }

  ObjectValue decodeDocumentFields(Map<String, proto_beta.Value> fields) {
    ObjectValue result = ObjectValue.empty;
    for (String key in fields.keys) {
      final FieldPath path = FieldPath.fromSingleSegment(key);
      final FieldValue value = decodeValue(fields[key]);
      result = result.set(path, value);
    }
    return result;
  }

  // Documents

  proto.Document encodeDocument(DocumentKey key, ObjectValue value) {
    final proto.Document builder = proto.Document.create()..name = encodeKey(key);

    for (MapEntry<String, FieldValue> entry in value.internalValue) {
      builder.fields[entry.key] = encodeValue(entry.value);
    }
    return builder..freeze();
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
    final ObjectValue value = decodeDocumentFields(response.found.fields);
    final SnapshotVersion version = decodeVersion(response.found.updateTime);
    hardAssert(version != SnapshotVersion.none, 'Got a document response with no snapshot version');
    return Document(key, version, value, DocumentState.synced, response.found);
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
    } else if (mutation is TransformMutation) {
      final proto.DocumentTransform transformBuilder = proto.DocumentTransform.create()
        ..document = encodeKey(mutation.key);

      for (FieldTransform fieldTransform in mutation.fieldTransforms) {
        transformBuilder.fieldTransforms.add(_encodeFieldTransform(fieldTransform));
      }

      builder.transform = transformBuilder;
    } else if (mutation is DeleteMutation) {
      builder.delete = encodeKey(mutation.key);
    } else {
      throw fail('unknown mutation type ${mutation.runtimeType}');
    }

    if (!mutation.precondition.isNone) {
      builder.currentDocument = _encodePrecondition(mutation.precondition);
    }
    return builder..freeze();
  }

  Mutation decodeMutation(proto.Write mutation) {
    final Precondition precondition =
        mutation.hasCurrentDocument() ? _decodePrecondition(mutation.currentDocument) : Precondition.none;

    if (mutation.hasUpdate()) {
      if (mutation.hasUpdateMask()) {
        return PatchMutation(decodeKey(mutation.update.name), decodeDocumentFields(mutation.update.fields),
            _decodeDocumentMask(mutation.updateMask), precondition);
      } else {
        return SetMutation(decodeKey(mutation.update.name), decodeDocumentFields(mutation.update.fields), precondition);
      }
    } else if (mutation.hasDelete()) {
      return DeleteMutation(decodeKey(mutation.delete), precondition);
    } else if (mutation.hasTransform()) {
      final List<FieldTransform> fieldTransforms = <FieldTransform>[];
      for (proto.DocumentTransform_FieldTransform fieldTransform in mutation.transform.fieldTransforms) {
        fieldTransforms.add(_decodeFieldTransform(fieldTransform));
      }
      final bool exists = precondition.exists;
      hardAssert(exists != null && exists, 'Transforms only support precondition \'exists == true\'');
      return TransformMutation(decodeKey(mutation.transform.document), fieldTransforms);
    } else {
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
        ..appendMissingElements = _encodeArrayTransformElements(transform.elements)
        ..freeze();
    } else if (transform is ArrayTransformOperationRemove) {
      return proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = fieldTransform.fieldPath.canonicalString
        ..removeAllFromArray = _encodeArrayTransformElements(transform.elements)
        ..freeze();
    } else {
      throw fail('Unknown transform: $transform');
    }
  }

  proto.ArrayValue _encodeArrayTransformElements(List<FieldValue> elements) {
    final proto.ArrayValue arrayBuilder = proto.ArrayValue.create();
    for (FieldValue subValue in elements) {
      arrayBuilder.values.add(encodeValue(subValue));
    }
    return arrayBuilder..freeze();
  }

  FieldTransform _decodeFieldTransform(proto.DocumentTransform_FieldTransform fieldTransform) {
    if (fieldTransform.hasSetToServerValue()) {
      hardAssert(fieldTransform.setToServerValue == proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME,
          'Unknown transform setToServerValue: ${fieldTransform.setToServerValue}');
      return FieldTransform(
          FieldPath.fromServerFormat(fieldTransform.fieldPath), ServerTimestampOperation.sharedInstance);
    } else if (fieldTransform.hasAppendMissingElements()) {
      return FieldTransform(FieldPath.fromServerFormat(fieldTransform.fieldPath),
          ArrayTransformOperationUnion(_decodeArrayTransformElements(fieldTransform.appendMissingElements)));
    } else if (fieldTransform.hasRemoveAllFromArray()) {
      return FieldTransform(FieldPath.fromServerFormat(fieldTransform.fieldPath),
          ArrayTransformOperationRemove(_decodeArrayTransformElements(fieldTransform.removeAllFromArray)));
    } else {
      throw fail(
        'Unknown FieldTransform proto: $fieldTransform',
      );
    }
  }

  List<FieldValue> _decodeArrayTransformElements(proto.ArrayValue elementsProto) {
    final int count = elementsProto.values.length;
    final List<FieldValue> result = List<FieldValue>(count);
    for (int i = 0; i < count; i++) {
      result[i] = decodeValue(elementsProto.values[i]);
    }
    return result;
  }

  MutationResult decodeMutationResult(proto.WriteResult proto, SnapshotVersion commitVersion) {
    // NOTE: Deletes don't have an [updateTime] but the commit timestamp from the containing [CommitResponse] or
    // [WriteResponse] indicates essentially that the delete happened no later than that. For our purposes we don't care
    // exactly when the delete happened so long as we can tell when an update on the watch stream is at or later than
    // that change.
    SnapshotVersion version = decodeVersion(proto.updateTime);
    if (version == SnapshotVersion.none) {
      version = commitVersion;
    }

    List<FieldValue> transformResults;
    final int transformResultsCount = proto.transformResults.length;
    if (transformResultsCount > 0) {
      transformResults = List<FieldValue>(transformResultsCount);
      for (int i = 0; i < transformResultsCount; i++) {
        transformResults[i] = decodeValue(proto.transformResults[i]);
      }
    }
    return MutationResult(version, transformResults);
  }

  // Queries

  MapEntry<String, String> encodeListenRequestLabels(QueryData queryData) {
    final String value = _encodeLabel(queryData.purpose);
    if (value == null) {
      return null;
    }

    return MapEntry<String, String>('goog-listen-tags', value);
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

  proto_beta.Target encodeTarget(QueryData queryData) {
    final proto_beta.Target builder = proto_beta.Target.create();
    final Query query = queryData.query;

    if (query.isDocumentQuery) {
      builder.documents = encodeDocumentsTarget(query);
    } else {
      builder.query = encodeQueryTarget(query);
    }

    return builder
      ..targetId = queryData.targetId
      ..resumeToken = queryData.resumeToken
      ..freeze();
  }

  proto.Target_DocumentsTarget encodeDocumentsTarget(Query query) {
    return proto.Target_DocumentsTarget.create()
      ..documents.add(_encodeQueryPath(query.path))
      ..freeze();
  }

  Query decodeDocumentsTarget(proto.Target_DocumentsTarget target) {
    final int count = target.documents.length;
    hardAssert(count == 1, 'DocumentsTarget contained other than 1 document $count');

    final String name = target.documents[0];
    return Query(_decodeQueryPath(name));
  }

  proto.Target_QueryTarget encodeQueryTarget(Query query) {
    // Dissect the path into [parent], [collectionId], and optional [key] filter.
    final proto.Target_QueryTarget builder = proto.Target_QueryTarget.create();
    final proto.StructuredQuery structuredQueryBuilder = proto.StructuredQuery.create();
    if (query.path.isEmpty) {
      builder.parent = _encodeQueryPath(ResourcePath.empty);
    } else {
      final ResourcePath path = query.path;
      hardAssert(path.length.remainder(2) != 0, 'Document queries with filters are not supported.');
      builder.parent = _encodeQueryPath(path.popLast());

      final proto.StructuredQuery_CollectionSelector from = proto.StructuredQuery_CollectionSelector.create()
        ..collectionId = path.last;
      structuredQueryBuilder.from.add(from);
    }

    // Encode the filters.
    if (query.filters.isNotEmpty) {
      structuredQueryBuilder.where = _encodeFilters(query.filters);
    }

    // Encode the orders.
    for (OrderBy orderBy in query.orderByConstraints) {
      structuredQueryBuilder.orderBy.add(_encodeOrderBy(orderBy));
    }

    // Encode the limit.
    if (query.hasLimit) {
      final proto.Int32Value limit = proto.Int32Value.create()..value = query.getLimit();
      structuredQueryBuilder.limit = limit;
    }

    if (query.getStartAt() != null) {
      structuredQueryBuilder.startAt = _encodeBound(query.getStartAt());
    }

    if (query.getEndAt() != null) {
      structuredQueryBuilder.endAt = _encodeBound(query.getEndAt());
    }

    builder.structuredQuery = structuredQueryBuilder;
    return builder..freeze();
  }

  Query decodeQueryTarget(proto.Target_QueryTarget target) {
    ResourcePath path = _decodeQueryPath(target.parent);

    final proto.StructuredQuery query = target.structuredQuery;
    final int fromCount = query.from.length;
    if (fromCount > 0) {
      hardAssert(fromCount == 1, 'StructuredQuery.from with more than one collection is not supported.');

      final proto.StructuredQuery_CollectionSelector from = query.from[0];
      path = path.appendSegment(from.collectionId);
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

    int limit = Query.noLimit;
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
      filters: filterBy,
      explicitSortOrder: orderBy,
      limit: limit,
      startAt: startAt,
      endAt: endAt,
    );
  }

  // Filters

  proto.StructuredQuery_Filter _encodeFilters(List<Filter> filters) {
    final List<proto.StructuredQuery_Filter> protos = List<proto.StructuredQuery_Filter>(filters.length);
    int i = 0;
    for (Filter filter in filters) {
      if (filter is RelationFilter) {
        protos[i] = _encodeRelationFilter(filter);
      } else {
        protos[i] = _encodeUnaryFilter(filter);
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
        result[i] = _decodeRelationFilter(filter.fieldFilter);
      } else if (filter.hasUnaryFilter()) {
        result[i] = _decodeUnaryFilter(filter.unaryFilter);
      } else {
        throw fail('Unrecognized Filter.filterType $filter');
      }
      i++;
    }

    return result;
  }

  proto.StructuredQuery_Filter _encodeRelationFilter(RelationFilter filter) {
    final proto.StructuredQuery_FieldFilter builder = proto.StructuredQuery_FieldFilter.create()
      ..field_1 = _encodeFieldPath(filter.field)
      ..op = _encodeRelationFilterOperator(filter.operator)
      ..value = encodeValue(filter.value);

    return proto.StructuredQuery_Filter.create()
      ..fieldFilter = builder
      ..freeze();
  }

  Filter _decodeRelationFilter(proto.StructuredQuery_FieldFilter builder) {
    final FieldPath fieldPath = FieldPath.fromServerFormat(builder.field_1.fieldPath);

    final FilterOperator filterOperator = _decodeRelationFilterOperator(builder.op);
    final FieldValue value = decodeValue(builder.value);
    return Filter.create(fieldPath, filterOperator, value);
  }

  proto.StructuredQuery_Filter _encodeUnaryFilter(Filter filter) {
    final proto.StructuredQuery_UnaryFilter builder = proto.StructuredQuery_UnaryFilter.create()
      ..field_2 = _encodeFieldPath(filter.field);

    if (filter is NaNFilter) {
      builder.op = proto.StructuredQuery_UnaryFilter_Operator.IS_NAN;
    } else if (filter is NullFilter) {
      builder.op = proto.StructuredQuery_UnaryFilter_Operator.IS_NULL;
    } else {
      throw fail('Unrecognized filter: ${filter.canonicalId}');
    }
    return proto.StructuredQuery_Filter.create()
      ..unaryFilter = builder
      ..freeze();
  }

  Filter _decodeUnaryFilter(proto.StructuredQuery_UnaryFilter value) {
    final FieldPath fieldPath = FieldPath.fromServerFormat(value.field_2.fieldPath);
    switch (value.op) {
      case proto.StructuredQuery_UnaryFilter_Operator.IS_NAN:
        return NaNFilter(fieldPath);

      case proto.StructuredQuery_UnaryFilter_Operator.IS_NULL:
        return NullFilter(fieldPath);

      default:
        throw fail('Unrecognized UnaryFilter.operator ${value.op}');
    }
  }

  proto.StructuredQuery_FieldReference _encodeFieldPath(FieldPath field) {
    return proto.StructuredQuery_FieldReference.create()
      ..fieldPath = field.canonicalString
      ..freeze();
  }

  proto.StructuredQuery_FieldFilter_Operator _encodeRelationFilterOperator(FilterOperator operator) {
    switch (operator) {
      case FilterOperator.lessThan:
        return proto.StructuredQuery_FieldFilter_Operator.LESS_THAN;
      case FilterOperator.lessThanOrEqual:
        return proto.StructuredQuery_FieldFilter_Operator.LESS_THAN_OR_EQUAL;
      case FilterOperator.equal:
        return proto.StructuredQuery_FieldFilter_Operator.EQUAL;
      case FilterOperator.graterThan:
        return proto.StructuredQuery_FieldFilter_Operator.GREATER_THAN;
      case FilterOperator.graterThanOrEqual:
        return proto.StructuredQuery_FieldFilter_Operator.GREATER_THAN_OR_EQUAL;
      case FilterOperator.arrayContains:
        return proto.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS;
      default:
        throw fail('Unknown operator $operator');
    }
  }

  FilterOperator _decodeRelationFilterOperator(proto.StructuredQuery_FieldFilter_Operator operator) {
    switch (operator) {
      case proto.StructuredQuery_FieldFilter_Operator.LESS_THAN:
        return FilterOperator.lessThan;
      case proto.StructuredQuery_FieldFilter_Operator.LESS_THAN_OR_EQUAL:
        return FilterOperator.lessThanOrEqual;
      case proto.StructuredQuery_FieldFilter_Operator.EQUAL:
        return FilterOperator.equal;
      case proto.StructuredQuery_FieldFilter_Operator.GREATER_THAN_OR_EQUAL:
        return FilterOperator.graterThanOrEqual;
      case proto.StructuredQuery_FieldFilter_Operator.GREATER_THAN:
        return FilterOperator.graterThan;
      case proto.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS:
        return FilterOperator.arrayContains;
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
    final proto.Cursor builder = proto.Cursor.create()..before = bound.before;
    for (FieldValue component in bound.position) {
      builder.values.add(encodeValue(component));
    }
    return builder..freeze();
  }

  Bound _decodeBound(proto.Cursor value) {
    final int valuesCount = value.values.length;
    final List<FieldValue> indexComponents = List<FieldValue>(valuesCount);

    for (int i = 0; i < valuesCount; i++) {
      final proto_beta.Value valueProto = value.values[i];
      indexComponents[i] = decodeValue(valueProto);
    }
    return Bound(position: indexComponents, before: value.before);
  }

  // Watch changes

  WatchChange decodeWatchChange(proto.ListenResponse protoChange) {
    WatchChange watchChange;

    if (protoChange.hasTargetChange()) {
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
      watchChange = WatchChangeWatchTargetChange(
        changeType,
        targetChange.targetIds,
        Uint8List.fromList(targetChange.resumeToken),
        cause,
      );
    } else if (protoChange.hasDocumentChange()) {
      final proto.DocumentChange docChange = protoChange.documentChange;
      final List<int> added = docChange.targetIds;
      final List<int> removed = docChange.removedTargetIds;
      final DocumentKey key = decodeKey(docChange.document.name);
      final SnapshotVersion version = decodeVersion(docChange.document.updateTime);
      hardAssert(version != SnapshotVersion.none, 'Got a document change without an update time');
      final ObjectValue data = decodeDocumentFields(docChange.document.fields);
      // The document may soon be re-serialized back to protos in order to store it in local persistence. Memoize the
      // encoded form to avoid encoding it again.
      final Document document = Document(key, version, data, DocumentState.synced, docChange.document);
      watchChange = WatchChangeDocumentChange(added, removed, document.key, document);
    } else if (protoChange.hasDocumentDelete()) {
      final proto.DocumentDelete docDelete = protoChange.documentDelete;
      final List<int> removed = docDelete.removedTargetIds;
      final DocumentKey key = decodeKey(docDelete.document);
      // Note that version might be unset in which case we use SnapshotVersion.none
      final SnapshotVersion version = decodeVersion(docDelete.readTime);
      final NoDocument doc = NoDocument(key, version, hasCommittedMutations: false);
      watchChange = WatchChangeDocumentChange(<int>[], removed, doc.key, doc);
    } else if (protoChange.hasDocumentRemove()) {
      final proto.DocumentRemove docRemove = protoChange.documentRemove;
      final List<int> removed = docRemove.removedTargetIds;
      final DocumentKey key = decodeKey(docRemove.document);
      watchChange = WatchChangeDocumentChange(<int>[], removed, key, null);
    } else if (protoChange.hasFilter()) {
      final proto.ExistenceFilter protoFilter = protoChange.filter;
      // TODO(long1eu): implement existence filter parsing (see b/33076578)
      final ExistenceFilter filter = ExistenceFilter(protoFilter.count);
      final int targetId = protoFilter.targetId;
      watchChange = WatchChangeExistenceFilterWatchChange(targetId, filter);
    } else {
      throw ArgumentError('Unknown change type set');
    }

    return watchChange;
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
