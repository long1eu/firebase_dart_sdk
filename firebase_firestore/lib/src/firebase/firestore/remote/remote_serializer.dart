// File created by
// Lung Razvan <long1eu>
// on 23/09/2018

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
import 'package:firebase_firestore/src/firebase/firestore/no_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/existence_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/common.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/document.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/firestore.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/query.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/write.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/protobuf/struct.pb.dart'
    as proto show NullValue;
import 'package:firebase_firestore/src/proto/google/protobuf/timestamp.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/protobuf/wrappers.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/rpc/status.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/type/latlng.pb.dart'
    as proto;
import 'package:grpc/grpc.dart';

/// Serializer that converts to and from Firestore API protos.
class RemoteSerializer {
  final DatabaseId databaseId;
  final String databaseName;

  RemoteSerializer(this.databaseId)
      : databaseName = encodedDatabaseId(databaseId).canonicalString;

  // Timestamps and Versions
  proto.Timestamp encodeTimestamp(Timestamp timestamp) {
    return proto.Timestamp.create()
      ..seconds = timestamp.seconds
      ..nanos = timestamp.nanoseconds;
  }

  Timestamp decodeTimestamp(proto.Timestamp proto) {
    return new Timestamp(proto.seconds, proto.nanos);
  }

  proto.Timestamp encodeVersion(SnapshotVersion version) {
    return encodeTimestamp(version.timestamp);
  }

  SnapshotVersion decodeVersion(proto.Timestamp proto) {
    if (proto.seconds == 0 && proto.nanos == 0) {
      return SnapshotVersion.none;
    } else {
      return new SnapshotVersion(decodeTimestamp(proto));
    }
  }

  // GeoPoint

  /*private*/
  proto.LatLng encodeGeoPoint(GeoPoint geoPoint) {
    return proto.LatLng.create()
      ..latitude = geoPoint.latitude
      ..longitude = geoPoint.longitude;
  }

  /*private*/
  GeoPoint decodeGeoPoint(proto.LatLng latLng) {
    return new GeoPoint(latLng.latitude, latLng.longitude);
  }

  // Names and Keys

  /// Encodes the given document [key] as a fully qualified name. This includes
  /// the [databaseId] from the constructor and the key path.
  String encodeKey(DocumentKey key) {
    return encodeResourceName(databaseId, key.path);
  }

  DocumentKey decodeKey(String name) {
    final ResourcePath resource = decodeResourceName(name);
    Assert.hardAssert(resource[1] == databaseId.projectId,
        'Tried to deserialize key from different project.');
    Assert.hardAssert(resource[3] == databaseId.databaseId,
        'Tried to deserialize key from different database.');
    return DocumentKey.fromPath(extractLocalPathFromResourceName(resource));
  }

  /*private*/
  String encodeQueryPath(ResourcePath path) {
    if (path.length == 0) {
      // If the path is empty, the backend requires we leave off the /documents
      // at the end.
      return databaseName;
    }
    return encodeResourceName(databaseId, path);
  }

  /*private*/
  ResourcePath decodeQueryPath(String name) {
    ResourcePath resource = decodeResourceName(name);
    if (resource.length == 4) {
      // Path missing the trailing documents path segment, indicating an empty
      // path.
      return ResourcePath.empty;
    } else {
      return extractLocalPathFromResourceName(resource);
    }
  }

  /// Encodes a [databaseId] and resource path into the following form:
  /// '/projects/$projectId/database/$databaseId/documents/$path'
  /*private*/
  String encodeResourceName(DatabaseId databaseId, ResourcePath path) {
    return encodedDatabaseId(databaseId)
        .appendSegment("documents")
        .appendPath(path)
        .canonicalString;
  }

  /// Decodes a fully qualified resource name into a resource path and validates
  /// that there is a project and database encoded in the path. There are no
  /// guarantees that a local path is also encoded in this resource name.
  /*private*/
  ResourcePath decodeResourceName(String encoded) {
    ResourcePath resource = ResourcePath.fromString(encoded);
    Assert.hardAssert(isValidResourceName(resource),
        'Tried to deserialize invalid key $resource');
    return resource;
  }

  /// Creates the prefix for a fully qualified resource path, without a local
  /// path on the end.
  /*private*/
  static ResourcePath encodedDatabaseId(DatabaseId databaseId) {
    return ResourcePath.fromSegments(
        ["projects", databaseId.projectId, "databases", databaseId.databaseId]);
  }

  /// Decodes a fully qualified resource name into a resource path and validates
  /// that there is a project and database encoded in the path along with a
  /// local path.
  /*private*/
  static ResourcePath extractLocalPathFromResourceName(
      ResourcePath resourceName) {
    Assert.hardAssert(resourceName.length > 4 && resourceName[4] == 'documents',
        'Tried to deserialize invalid key $resourceName');
    return resourceName.popFirst(5);
  }

  /// Validates that a path has a prefix that looks like a valid encoded
  /// [databaseId].
  /*private*/
  static bool isValidResourceName(ResourcePath path) {
    // Resource names have at least 4 components (project ID, database ID)
    // and commonly the (root) resource type, e.g. documents
    return path.length >= 4 && path[0] == 'projects' && path[2] == 'databases';
  }

  // Values

  /// Converts the [FieldValue] model passed into the [Value] proto equivalent.
  proto.Value encodeValue(FieldValue value) {
    proto.Value builder = proto.Value.create();

    if (value is NullValue) {
      return builder //
        ..nullValue = proto.NullValue.NULL_VALUE;
    }

    Assert.hardAssert(
        value.value != null, 'Encoded field value should not be null.');

    if (value is BoolValue) {
      builder.booleanValue = value.value;
    } else if (value is IntegerValue) {
      builder.integerValue = value.value;
    } else if (value is DoubleValue) {
      builder.doubleValue = value.value;
    } else if (value is StringValue) {
      builder.stringValue = value.value;
    } else if (value is ArrayValue) {
      builder.arrayValue = encodeArrayValue(value);
    } else if (value is ObjectValue) {
      builder.mapValue = encodeMapValue(value);
    } else if (value is TimestampValue) {
      builder.timestampValue = encodeTimestamp(value.value);
    } else if (value is GeoPointValue) {
      builder.geoPointValue = encodeGeoPoint(value.value);
    } else if (value is BlobValue) {
      builder.bytesValue = value.value.bytes;
    } else if (value is ReferenceValue) {
      final DatabaseId id = value.databaseId;
      final DocumentKey key = value.value;
      builder.referenceValue = encodeResourceName(id, key.path);
    } else {
      throw Assert.fail('Can\'t serialize $value');
    }

    return builder.freeze();
  }

  /// Converts from the proto [Value] format to the model [FieldValue] format
  FieldValue decodeValue(proto.Value proto) {
    if (proto.hasNullValue()) {
      return NullValue.nullValue();
    } else if (proto.hasBooleanValue()) {
      return BoolValue.valueOf(proto.booleanValue);
    } else if (proto.hasIntegerValue()) {
      return IntegerValue.valueOf(proto.integerValue);
    } else if (proto.hasDoubleValue()) {
      return DoubleValue.valueOf(proto.doubleValue);
    } else if (proto.hasTimestampValue()) {
      final Timestamp timestamp = decodeTimestamp(proto.timestampValue);
      return TimestampValue.valueOf(timestamp);
    } else if (proto.hasGeoPointValue()) {
      final proto.LatLng latLng = proto.geoPointValue;
      return GeoPointValue.valueOf(decodeGeoPoint(latLng));
    } else if (proto.hasBytesValue()) {
      final Blob bytes = Blob(proto.bytesValue);
      return BlobValue.valueOf(bytes);
    } else if (proto.hasReferenceValue()) {
      final ResourcePath resourceName =
          decodeResourceName(proto.referenceValue);
      final DatabaseId id =
          DatabaseId.fromDatabase(resourceName[1], resourceName[3]);
      final DocumentKey key =
          DocumentKey.fromPath(extractLocalPathFromResourceName(resourceName));
      return ReferenceValue.valueOf(id, key);
    } else if (proto.hasStringValue()) {
      return StringValue.valueOf(proto.stringValue);
    } else if (proto.hasArrayValue()) {
      return decodeArrayValue(proto.arrayValue);
    } else if (proto.hasMapValue()) {
      return decodeMapValue(proto.mapValue);
    } else {
      throw Assert.fail("Unknown value $proto");
    }
  }

/*private*/
  proto.ArrayValue encodeArrayValue(ArrayValue value) {
    final List<FieldValue> internalValue = value.internalValue;

    proto.ArrayValue arrayBuilder = proto.ArrayValue.create();
    for (FieldValue subValue in internalValue) {
      arrayBuilder.values.add(encodeValue(subValue));
    }

    return arrayBuilder.freeze();
  }

  /*private*/
  ArrayValue decodeArrayValue(proto.ArrayValue protoArray) {
    final int count = protoArray.values.length;
    List<FieldValue> wrappedList = List<FieldValue>(count);
    for (int i = 0; i < count; i++) {
      wrappedList.add(decodeValue(protoArray.values[i]));
    }
    return ArrayValue.fromList(wrappedList);
  }

/*private*/
  proto.MapValue encodeMapValue(ObjectValue value) {
    final proto.MapValue builder = proto.MapValue.create();
    for (MapEntry<String, FieldValue> entry in value.internalValue) {
      final proto.MapValue_FieldsEntry value =
          proto.MapValue_FieldsEntry.create()
            ..key = entry.key
            ..value = encodeValue(entry.value);

      builder.fields.add(value);
    }
    return builder.freeze();
  }

  /*private*/
  ObjectValue decodeMapValue(proto.MapValue value) {
    return decodeMapFields(value.fields);
  }

  // PORTING NOTE: There's no encodeFields here because there's no way to write
  // it that doesn't involve creating a temporary map.
  ObjectValue decodeMapFields(List<proto.MapValue_FieldsEntry> fields) {
    ObjectValue result = ObjectValue.empty;
    for (proto.MapValue_FieldsEntry entry in fields) {
      FieldPath path = FieldPath.fromSingleSegment(entry.key);
      FieldValue value = decodeValue(entry.value);
      result = result.set(path, value);
    }
    return result;
  }

  ObjectValue decodeDocumentFields(List<proto.Document_FieldsEntry> fields) {
    ObjectValue result = ObjectValue.empty;
    for (proto.Document_FieldsEntry entry in fields) {
      FieldPath path = FieldPath.fromSingleSegment(entry.key);
      FieldValue value = decodeValue(entry.value);
      result = result.set(path, value);
    }
    return result;
  }

  // Documents

  proto.Document encodeDocument(DocumentKey key, ObjectValue value) {
    proto.Document builder = proto.Document.create();
    builder.name = encodeKey(key);

    for (MapEntry<String, FieldValue> entry in value.internalValue) {
      final proto.Document_FieldsEntry fieldsEntry =
          proto.Document_FieldsEntry.create()
            ..key = entry.key
            ..value = encodeValue(entry.value);

      builder.fields.add(fieldsEntry);
    }
    return builder.freeze();
  }

  MaybeDocument decodeMaybeDocument(proto.BatchGetDocumentsResponse response) {
    if (response.hasFound()) {
      return decodeFoundDocument(response);
    } else if (response.hasMissing()) {
      return decodeMissingDocument(response);
    } else {
      throw new ArgumentError('Unknown result case: ${response}');
    }
  }

  /*private*/
  Document decodeFoundDocument(proto.BatchGetDocumentsResponse response) {
    Assert.hardAssert(response.hasFound(),
        'Tried to deserialize a found document from a missing document.');
    final DocumentKey key = decodeKey(response.found.name);
    final ObjectValue value = decodeDocumentFields(response.found.fields);
    final SnapshotVersion version = decodeVersion(response.found.updateTime);
    Assert.hardAssert(version != SnapshotVersion.none,
        'Got a document response with no snapshot version');
    return new Document(key, version, value, false);
  }

  /*private*/
  NoDocument decodeMissingDocument(proto.BatchGetDocumentsResponse response) {
    Assert.hardAssert(response.hasMissing(),
        'Tried to deserialize a missing document from a found document.');
    final DocumentKey key = decodeKey(response.missing);
    final SnapshotVersion version = decodeVersion(response.readTime);
    Assert.hardAssert(version != SnapshotVersion.none,
        'Got a no document response with no snapshot version');
    return new NoDocument(key, version);
  }

  // Mutations

  /** Converts a Mutation model to a Write proto */
  proto.Write encodeMutation(Mutation mutation) {
    proto.Write builder = proto.Write.create();
    if (mutation is SetMutation) {
      builder.update = encodeDocument(mutation.key, mutation.value);
    } else if (mutation is PatchMutation) {
      builder.update = encodeDocument(mutation.key, mutation.value);
      builder.updateMask = encodeDocumentMask(mutation.mask);
    } else if (mutation is TransformMutation) {
      proto.DocumentTransform transformBuilder =
          proto.DocumentTransform.create();
      transformBuilder.document = encodeKey(mutation.key);

      for (var fieldTransform in mutation.fieldTransforms) {
        transformBuilder.fieldTransforms
            .add(encodeFieldTransform(fieldTransform));
      }

      builder.transform = transformBuilder;
    } else if (mutation is DeleteMutation) {
      builder.delete = encodeKey(mutation.key);
    } else {
      throw Assert.fail('unknown mutation type ${mutation.runtimeType}');
    }

    if (!mutation.precondition.isNone) {
      builder.currentDocument = encodePrecondition(mutation.precondition);
    }
    return builder.freeze();
  }

  Mutation decodeMutation(proto.Write mutation) {
    Precondition precondition = mutation.hasCurrentDocument()
        ? decodePrecondition(mutation.currentDocument)
        : Precondition.none;

    if (mutation.hasUpdate()) {
      if (mutation.hasUpdateMask()) {
        return new PatchMutation(
            decodeKey(mutation.update.name),
            decodeDocumentFields(mutation.update.fields),
            decodeDocumentMask(mutation.updateMask),
            precondition);
      } else {
        return new SetMutation(decodeKey(mutation.update.name),
            decodeDocumentFields(mutation.update.fields), precondition);
      }
    } else if (mutation.hasDelete()) {
      return new DeleteMutation(decodeKey(mutation.delete), precondition);
    } else if (mutation.hasTransform()) {
      List<FieldTransform> fieldTransforms = new List();
      for (proto.DocumentTransform_FieldTransform fieldTransform
          in mutation.transform.fieldTransforms) {
        fieldTransforms.add(decodeFieldTransform(fieldTransform));
      }
      final bool exists = precondition.exists;
      Assert.hardAssert(exists != null && exists,
          'Transforms only support precondition "exists == true"');
      return new TransformMutation(
          decodeKey(mutation.transform.document), fieldTransforms);
    } else {
      throw Assert.fail('Unknown mutation operation: ${mutation}');
    }
  }

  /*private*/
  proto.Precondition encodePrecondition(Precondition precondition) {
    Assert.hardAssert(
        !precondition.isNone, 'Can\'t serialize an empty precondition');
    proto.Precondition builder = proto.Precondition.create();
    if (precondition.updateTime != null) {
      return builder
        ..updateTime = encodeVersion(precondition.updateTime)
        ..freeze();
    } else if (precondition.exists != null) {
      return builder
        ..exists = precondition.exists
        ..freeze();
    } else {
      throw Assert.fail("Unknown Precondition");
    }
  }

  /*private*/
  Precondition decodePrecondition(proto.Precondition precondition) {
    if (precondition.hasUpdateTime()) {
      return Precondition.fromUpdateTime(
          decodeVersion(precondition.updateTime));
    } else if (precondition.hasExists()) {
      return Precondition.fromExists(precondition.exists);
    } else {
      return Precondition.none;
    }
  }

  /*private*/
  proto.DocumentMask encodeDocumentMask(FieldMask mask) {
    proto.DocumentMask builder = proto.DocumentMask.create();
    for (FieldPath path in mask.mask) {
      builder.fieldPaths.add(path.canonicalString);
    }
    return builder.freeze();
  }

  /*private*/
  FieldMask decodeDocumentMask(proto.DocumentMask mask) {
    final int count = mask.fieldPaths.length;
    List<FieldPath> paths = new List(count);
    for (int i = 0; i < count; i++) {
      paths.add(FieldPath.fromServerFormat(mask.fieldPaths[i]));
    }
    return FieldMask(paths);
  }

  /*private*/
  proto.DocumentTransform_FieldTransform encodeFieldTransform(
      FieldTransform fieldTransform) {
    TransformOperation transform = fieldTransform.operation;
    if (transform is ServerTimestampOperation) {
      return proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = fieldTransform.fieldPath.canonicalString
        ..setToServerValue =
            proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME
        ..freeze();
    } else if (transform is ArrayTransformOperationUnion) {
      return proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = fieldTransform.fieldPath.canonicalString
        ..appendMissingElements =
            encodeArrayTransformElements(transform.elements)
        ..freeze();
    } else if (transform is ArrayTransformOperationRemove) {
      return proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = fieldTransform.fieldPath.canonicalString
        ..removeAllFromArray = encodeArrayTransformElements(transform.elements)
        ..freeze();
    } else {
      throw Assert.fail('Unknown transform: $transform');
    }
  }

  /*private*/
  proto.ArrayValue encodeArrayTransformElements(List<FieldValue> elements) {
    proto.ArrayValue arrayBuilder = proto.ArrayValue.create();
    for (FieldValue subValue in elements) {
      arrayBuilder.values.add(encodeValue(subValue));
    }
    return arrayBuilder.freeze();
  }

  /*private*/
  FieldTransform decodeFieldTransform(
      proto.DocumentTransform_FieldTransform fieldTransform) {
    if (fieldTransform.hasSetToServerValue()) {
      Assert.hardAssert(
          fieldTransform.setToServerValue ==
              proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME,
          'Unknown transform setToServerValue: ${fieldTransform.setToServerValue}');
      return new FieldTransform(
          FieldPath.fromServerFormat(fieldTransform.fieldPath),
          ServerTimestampOperation.sharedInstance);
    } else if (fieldTransform.hasAppendMissingElements()) {
      return new FieldTransform(
          FieldPath.fromServerFormat(fieldTransform.fieldPath),
          new ArrayTransformOperationUnion(decodeArrayTransformElements(
              fieldTransform.appendMissingElements)));
    } else if (fieldTransform.hasRemoveAllFromArray()) {
      return new FieldTransform(
          FieldPath.fromServerFormat(fieldTransform.fieldPath),
          new ArrayTransformOperationRemove(
              decodeArrayTransformElements(fieldTransform.removeAllFromArray)));
    } else {
      throw Assert.fail(
        'Unknown FieldTransform proto: $fieldTransform',
      );
    }
  }

  /*private*/
  List<FieldValue> decodeArrayTransformElements(
      proto.ArrayValue elementsProto) {
    final int count = elementsProto.values.length;
    List<FieldValue> result = new List(count);
    for (int i = 0; i < count; i++) {
      result.add(decodeValue(elementsProto.values[i]));
    }
    return result;
  }

  MutationResult decodeMutationResult(
      proto.WriteResult proto, SnapshotVersion commitVersion) {
    // NOTE: Deletes don't have an [updateTime] but the commit timestamp from
    // the containing [CommitResponse] or [WriteResponse] indicates essentially
    // that the delete happened no later than that. For our purposes we don't
    // care exactly when the delete happened so long as we can tell when an
    // update on the watch stream is at or later than that change.
    SnapshotVersion version = decodeVersion(proto.updateTime);
    if (version == SnapshotVersion.none) {
      version = commitVersion;
    }

    List<FieldValue> transformResults = null;
    final int transformResultsCount = proto.transformResults.length;
    if (transformResultsCount > 0) {
      transformResults = new List(transformResultsCount);
      for (int i = 0; i < transformResultsCount; i++) {
        transformResults.add(decodeValue(proto.transformResults[i]));
      }
    }
    return new MutationResult(version, transformResults);
  }

  // Queries

  MapEntry<String, String> encodeListenRequestLabels(QueryData queryData) {
    String value = encodeLabel(queryData.purpose);
    if (value == null) {
      return null;
    }

    return MapEntry<String, String>('goog-listen-tags', value);
  }

  /*private*/
  String encodeLabel(QueryPurpose purpose) {
    switch (purpose) {
      case QueryPurpose.listen:
        return null;
      case QueryPurpose.existenceFilterMismatch:
        return "existence-filter-mismatch";
      case QueryPurpose.limboResolution:
        return "limbo-document";
      default:
        throw Assert.fail("Unrecognized query purpose: $purpose");
    }
  }

  proto.Target encodeTarget(QueryData queryData) {
    proto.Target builder = proto.Target.create();
    Query query = queryData.query;

    if (query.isDocumentQuery) {
      builder.documents = encodeDocumentsTarget(query);
    } else {
      builder.query = encodeQueryTarget(query);
    }

    builder.targetId = queryData.targetId;
    builder.resumeToken = queryData.resumeToken;

    return builder.freeze();
  }

  proto.Target_DocumentsTarget encodeDocumentsTarget(Query query) {
    return proto.Target_DocumentsTarget.create()
      ..documents.add(encodeQueryPath(query.path))
      ..freeze();
  }

  Query decodeDocumentsTarget(proto.Target_DocumentsTarget target) {
    final int count = target.documents.length;
    Assert.hardAssert(
      count == 1,
      'DocumentsTarget contained other than 1 document $count',
    );

    final String name = target.documents[0];
    return Query.atPath(decodeQueryPath(name));
  }

  proto.Target_QueryTarget encodeQueryTarget(Query query) {
    // Dissect the path into [parent], [collectionId], and optional [key] filter.
    final proto.Target_QueryTarget builder = proto.Target_QueryTarget.create();
    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create();
    if (query.path.isEmpty) {
      builder.parent = encodeQueryPath(ResourcePath.empty);
    } else {
      final ResourcePath path = query.path;
      Assert.hardAssert(path.length % 2 != 0,
          'Document queries with filters are not supported.');
      builder.parent = encodeQueryPath(path.popLast());

      final proto.StructuredQuery_CollectionSelector from =
          proto.StructuredQuery_CollectionSelector.create();
      from.collectionId = path.last;
      structuredQueryBuilder.from.add(from);
    }

    // Encode the filters.
    if (query.filters.isNotEmpty) {
      structuredQueryBuilder.where = encodeFilters(query.filters);
    }

    // Encode the orders.
    for (OrderBy orderBy in query.getOrderBy()) {
      structuredQueryBuilder.orderBy.add(encodeOrderBy(orderBy));
    }

    // Encode the limit.
    if (query.hasLimit) {
      final proto.Int32Value limit = proto.Int32Value.create()
        ..value = query.getLimit();
      structuredQueryBuilder.limit = limit;
    }

    if (query.getStartAt() != null) {
      structuredQueryBuilder.startAt = encodeBound(query.getStartAt());
    }

    if (query.getEndAt() != null) {
      structuredQueryBuilder.endAt = encodeBound(query.getEndAt());
    }

    builder.structuredQuery = structuredQueryBuilder;
    return builder.freeze();
  }

  Query decodeQueryTarget(proto.Target_QueryTarget target) {
    ResourcePath path = decodeQueryPath(target.parent);

    final proto.StructuredQuery query = target.structuredQuery;
    final int fromCount = query.from.length;
    if (fromCount > 0) {
      Assert.hardAssert(fromCount == 1,
          'StructuredQuery.from with more than one collection is not supported.');

      proto.StructuredQuery_CollectionSelector from = query.from[0];
      path = path.appendSegment(from.collectionId);
    }

    List<Filter> filterBy;
    if (query.hasWhere()) {
      filterBy = decodeFilters(query.where);
    } else {
      filterBy = <Filter>[];
    }

    List<OrderBy> orderBy;
    final int orderByCount = query.orderBy.length;
    if (orderByCount > 0) {
      orderBy = new List(orderByCount);
      for (int i = 0; i < orderByCount; i++) {
        orderBy.add(decodeOrderBy(query.orderBy[i]));
      }
    } else {
      orderBy = <OrderBy>[];
    }

    int limit = Query.noLimit;
    if (query.hasLimit()) {
      limit = query.limit.value;
    }

    Bound startAt = null;
    if (query.hasStartAt()) {
      startAt = decodeBound(query.startAt);
    }

    Bound endAt = null;
    if (query.hasEndAt()) {
      endAt = decodeBound(query.endAt);
    }

    return new Query(path, filterBy, orderBy, limit, startAt, endAt);
  }

  // Filters

  /*private*/
  proto.StructuredQuery_Filter encodeFilters(List<Filter> filters) {
    final List<proto.StructuredQuery_Filter> protos = new List(filters.length);
    for (Filter filter in filters) {
      if (filter is RelationFilter) {
        protos.add(encodeRelationFilter(filter));
      } else {
        protos.add(encodeUnaryFilter(filter));
      }
    }
    if (filters.length == 1) {
      return protos[0];
    } else {
      proto.StructuredQuery_CompositeFilter composite =
          proto.StructuredQuery_CompositeFilter.create()
            ..op = proto.StructuredQuery_CompositeFilter_Operator.AND
            ..filters.addAll(protos);

      return proto.StructuredQuery_Filter.create()
        ..compositeFilter = composite
        ..freeze();
    }
  }

  /*private*/
  List<Filter> decodeFilters(proto.StructuredQuery_Filter value) {
    List<proto.StructuredQuery_Filter> filters;
    if (value.hasCompositeFilter()) {
      Assert.hardAssert(
          value.compositeFilter.op ==
              proto.StructuredQuery_CompositeFilter_Operator.AND,
          'Only AND-type composite filters are supported, got ${value.compositeFilter.op}');
      filters = value.compositeFilter.filters;
    } else {
      filters = [value];
    }

    List<Filter> result = new List(filters.length);
    for (proto.StructuredQuery_Filter filter in filters) {
      if (filter.hasCompositeFilter()) {
        throw Assert.fail('Nested composite filters are not supported.');
      } else if (filter.hasFieldFilter()) {
        result.add(decodeRelationFilter(filter.fieldFilter));
      } else if (filter.hasUnaryFilter()) {
        result.add(decodeUnaryFilter(filter.unaryFilter));
      } else {
        throw Assert.fail('Unrecognized Filter.filterType ${filter}');
      }
    }

    return result;
  }

  /*private*/
  proto.StructuredQuery_Filter encodeRelationFilter(RelationFilter filter) {
    final proto.StructuredQuery_FieldFilter builder =
        proto.StructuredQuery_FieldFilter.create();
    builder.field_1 = encodeFieldPath(filter.field);
    builder.op = encodeRelationFilterOperator(filter.operator);
    builder.value = encodeValue(filter.value);

    return proto.StructuredQuery_Filter.create()
      ..fieldFilter = builder
      ..freeze();
  }

  /*private*/
  Filter decodeRelationFilter(proto.StructuredQuery_FieldFilter builder) {
    final FieldPath fieldPath =
        FieldPath.fromServerFormat(builder.field_1.fieldPath);

    final FilterOperator filterOperator =
        decodeRelationFilterOperator(builder.op);
    FieldValue value = decodeValue(builder.value);
    return Filter.create(fieldPath, filterOperator, value);
  }

  /*private*/
  proto.StructuredQuery_Filter encodeUnaryFilter(Filter filter) {
    proto.StructuredQuery_UnaryFilter builder =
        proto.StructuredQuery_UnaryFilter.create();

    builder.field_2 = encodeFieldPath(filter.field);

    if (filter is NaNFilter) {
      builder.op = proto.StructuredQuery_UnaryFilter_Operator.IS_NAN;
    } else if (filter is NullFilter) {
      builder.op = proto.StructuredQuery_UnaryFilter_Operator.IS_NULL;
    } else {
      throw Assert.fail('Unrecognized filter: ${filter.canonicalId}');
    }
    return proto.StructuredQuery_Filter.create()
      ..unaryFilter = builder
      ..freeze();
  }

  /*private*/
  Filter decodeUnaryFilter(proto.StructuredQuery_UnaryFilter value) {
    final FieldPath fieldPath =
        FieldPath.fromServerFormat(value.field_2.fieldPath);
    switch (value.op) {
      case proto.StructuredQuery_UnaryFilter_Operator.IS_NAN:
        return new NaNFilter(fieldPath);

      case proto.StructuredQuery_UnaryFilter_Operator.IS_NULL:
        return new NullFilter(fieldPath);

      default:
        throw Assert.fail('Unrecognized UnaryFilter.operator ${value.op}');
    }
  }

  /*private*/
  proto.StructuredQuery_FieldReference encodeFieldPath(FieldPath field) {
    return proto.StructuredQuery_FieldReference.create()
      ..fieldPath = field.canonicalString
      ..freeze();
  }

  /*private*/
  proto.StructuredQuery_FieldFilter_Operator encodeRelationFilterOperator(
      FilterOperator operator) {
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
        throw Assert.fail(
          'Unknown operator $operator',
        );
    }
  }

  /*private*/
  FilterOperator decodeRelationFilterOperator(
      proto.StructuredQuery_FieldFilter_Operator operator) {
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
        throw Assert.fail('Unhandled FieldFilter.operator $operator');
    }
  }

  // Property orders

  /*private*/
  proto.StructuredQuery_Order encodeOrderBy(OrderBy orderBy) {
    final proto.StructuredQuery_Order builder =
        proto.StructuredQuery_Order.create();
    if (orderBy.direction == OrderByDirection.ascending) {
      builder.direction = proto.StructuredQuery_Direction.ASCENDING;
    } else {
      builder.direction = proto.StructuredQuery_Direction.DESCENDING;
    }

    builder.field_1 = encodeFieldPath(orderBy.field);

    return builder.freeze();
  }

  /*private*/
  OrderBy decodeOrderBy(proto.StructuredQuery_Order value) {
    final FieldPath fieldPath =
        FieldPath.fromServerFormat(value.field_1.fieldPath);
    OrderByDirection direction;

    switch (value.direction) {
      case proto.StructuredQuery_Direction.ASCENDING:
        direction = OrderByDirection.ascending;
        break;
      case proto.StructuredQuery_Direction.DESCENDING:
        direction = OrderByDirection.descending;
        break;
      default:
        throw Assert.fail('Unrecognized direction ${value.direction}');
    }
    return OrderBy.getInstance(direction, fieldPath);
  }

  // Bounds

  /*private*/
  proto.Cursor encodeBound(Bound bound) {
    final proto.Cursor builder = proto.Cursor.create();
    builder.before = bound.before;
    for (FieldValue component in bound.position) {
      builder.values.add(encodeValue(component));
    }
    return builder.freeze();
  }

  /*private*/
  Bound decodeBound(proto.Cursor value) {
    final int valuesCount = value.values.length;
    final List<FieldValue> indexComponents = new List(valuesCount);

    for (int i = 0; i < valuesCount; i++) {
      proto.Value valueProto = value.values[i];
      indexComponents.add(decodeValue(valueProto));
    }
    return new Bound(indexComponents, value.before);
  }

  // Watch changes

  WatchChange decodeWatchChange(proto.ListenResponse protoChange) {
    WatchChange watchChange;

    if (protoChange.hasTargetChange()) {
      final proto.TargetChange targetChange = protoChange.targetChange;
      WatchTargetChangeType changeType;
      GrpcError cause = null;
      switch (targetChange.targetChangeType) {
        case proto.TargetChange_TargetChangeType.NO_CHANGE:
          changeType = WatchTargetChangeType.NoChange;
          break;
        case proto.TargetChange_TargetChangeType.ADD:
          changeType = WatchTargetChangeType.Added;
          break;
        case proto.TargetChange_TargetChangeType.REMOVE:
          changeType = WatchTargetChangeType.Removed;
          cause = fromStatus(targetChange.cause);
          break;
        case proto.TargetChange_TargetChangeType.CURRENT:
          changeType = WatchTargetChangeType.Current;
          break;
        case proto.TargetChange_TargetChangeType.RESET:
          changeType = WatchTargetChangeType.Reset;
          break;
        default:
          throw new ArgumentError('Unknown target change type');
      }
      watchChange = new WatchChangeWatchTargetChange(
          changeType, targetChange.targetIds, targetChange.resumeToken, cause);
    } else if (protoChange.hasDocumentChange()) {
      final proto.DocumentChange docChange = protoChange.documentChange;
      final List<int> added = docChange.targetIds;
      final List<int> removed = docChange.removedTargetIds;
      final DocumentKey key = decodeKey(docChange.document.name);
      final SnapshotVersion version =
          decodeVersion(docChange.document.updateTime);
      Assert.hardAssert(version != SnapshotVersion.none,
          'Got a document change without an update time');
      final ObjectValue data = decodeDocumentFields(docChange.document.fields);
      final Document document =
          new Document(key, version, data, /*hasLocalMutations=*/ false);
      watchChange =
          new WatchChangeDocumentChange(added, removed, document.key, document);
    } else if (protoChange.hasDocumentDelete()) {
      final proto.DocumentDelete docDelete = protoChange.documentDelete;
      final List<int> removed = docDelete.removedTargetIds;
      final DocumentKey key = decodeKey(docDelete.document);
      // Note that version might be unset in which case we use SnapshotVersion.none
      final SnapshotVersion version = decodeVersion(docDelete.readTime);
      NoDocument doc = new NoDocument(key, version);
      watchChange = new WatchChangeDocumentChange([], removed, doc.key, doc);
    } else if (protoChange.hasDocumentRemove()) {
      final proto.DocumentRemove docRemove = protoChange.documentRemove;
      final List<int> removed = docRemove.removedTargetIds;
      final DocumentKey key = decodeKey(docRemove.document);
      watchChange = new WatchChangeDocumentChange([], removed, key, null);
    } else if (protoChange.hasFilter()) {
      proto.ExistenceFilter protoFilter = protoChange.filter;
      // TODO: implement existence filter parsing (see b/33076578)
      final ExistenceFilter filter = new ExistenceFilter(protoFilter.count);
      final int targetId = protoFilter.targetId;
      watchChange = new WatchChangeExistenceFilterWatchChange(targetId, filter);
    } else {
      throw new ArgumentError('Unknown change type set');
    }

    return watchChange;
  }

  SnapshotVersion decodeVersionFromListenResponse(
      proto.ListenResponse watchChange) {
    // We have only reached a consistent snapshot for the entire stream if there
    // is a [read_time] set and it applies to all targets (i.e. the list of
    // targets is empty). The backend is guaranteed to send such responses.
    if (watchChange.hasTargetChange()) {
      return SnapshotVersion.none;
    }
    if (watchChange.targetChange.targetIds.isNotEmpty) {
      return SnapshotVersion.none;
    }
    return decodeVersion(watchChange.targetChange.readTime);
  }

  /*private*/
  GrpcError fromStatus(proto.Status status) {
    // TODO: Use details?
    return GrpcError.custom(status.code, status.message);
  }
}
