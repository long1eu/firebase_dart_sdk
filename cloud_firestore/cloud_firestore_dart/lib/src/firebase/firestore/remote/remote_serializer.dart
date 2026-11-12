// File created by
// Lung Razvan <long1eu>
// on 23/09/2018

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bson_object_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bson_timestamp.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
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
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
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
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/regex_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/existence_filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_v1;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:meta/meta.dart';

/// Serializer that converts to and from Firestore API protos.
class RemoteSerializer {
  RemoteSerializer(this.databaseId)
      : databaseName = _encodedDatabaseId(databaseId).canonicalString;

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
    hardAssert(resource[1] == databaseId.projectId,
        'Tried to deserialize key from different project.');
    hardAssert(resource[3] == databaseId.databaseId,
        'Tried to deserialize key from different database.');
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
    return _encodedDatabaseId(databaseId)
        .appendSegment('documents')
        .appendField(path)
        .canonicalString;
  }

  /// Decodes a fully qualified resource name into a resource path and validates that there is a project and database
  /// encoded in the path. There are no guarantees that a local path is also encoded in this resource name.
  ResourcePath _decodeResourceName(String encoded) {
    final ResourcePath resource = ResourcePath.fromString(encoded);
    hardAssertLazy(_isValidResourceName(resource),
        () => 'Tried to deserialize invalid key $resource');
    return resource;
  }

  /// Creates the prefix for a fully qualified resource path, without a local path on the end.
  static ResourcePath _encodedDatabaseId(DatabaseId databaseId) {
    return ResourcePath.fromSegments(<String>[
      'projects',
      databaseId.projectId,
      'databases',
      databaseId.databaseId
    ]);
  }

  /// Decodes a fully qualified resource name into a resource path and validates that there is a project and database
  /// encoded in the path along with a local path.
  static ResourcePath _extractLocalPathFromResourceName(
      ResourcePath resourceName) {
    hardAssertLazy(resourceName.length > 4 && resourceName[4] == 'documents',
        () => 'Tried to deserialize invalid key $resourceName');
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
  proto_v1.Value encodeValue(FieldValue value) {
    final proto_v1.Value builder = proto_v1.Value.create();

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
    } else if (value is VectorFieldValue) {
      builder.mapValue = _encodeVector(value);
    } else if (value is ObjectValue) {
      builder.mapValue = _encodeMapValue(value);
    } else if (value is TimestampValue) {
      builder.timestampValue = encodeTimestamp(value.value);
    } else if (value is GeoPointValue) {
      builder.geoPointValue = _encodeGeoPoint(value.value);
    } else if (value is BlobValue) {
      final Blob blob = value.value;
      if (blob.subtype == 0) {
        builder.bytesValue = blob.bytes;
      } else {
        // BSON binary data is a map with the subtype in front of the bytes.
        builder.mapValue = _encodeSingleFieldMap(
            BsonKeys.binary,
            proto_v1.Value.create()
              ..bytesValue = <int>[blob.subtype, ...blob.bytes]);
      }
    } else if (value is MinKeyValue) {
      builder.mapValue = _encodeSingleFieldMap(BsonKeys.minKey,
          proto_v1.Value.create()..nullValue = proto.NullValue.NULL_VALUE);
    } else if (value is MaxKeyValue) {
      builder.mapValue = _encodeSingleFieldMap(BsonKeys.maxKey,
          proto_v1.Value.create()..nullValue = proto.NullValue.NULL_VALUE);
    } else if (value is Int32FieldValue) {
      builder.mapValue = _encodeSingleFieldMap(BsonKeys.int32,
          proto_v1.Value.create()..integerValue = Int64(value.intValue));
    } else if (value is Decimal128FieldValue) {
      builder.mapValue = _encodeSingleFieldMap(BsonKeys.decimal128,
          proto_v1.Value.create()..stringValue = value.value.stringValue);
    } else if (value is BsonObjectIdValue) {
      builder.mapValue = _encodeSingleFieldMap(BsonKeys.objectId,
          proto_v1.Value.create()..stringValue = value.value.value);
    } else if (value is BsonTimestampValue) {
      final proto.MapValue inner = proto.MapValue.create();
      inner.fields[BsonKeys.timestampSeconds] = proto_v1.Value.create()
        ..integerValue = Int64(value.value.seconds);
      inner.fields[BsonKeys.timestampIncrement] = proto_v1.Value.create()
        ..integerValue = Int64(value.value.increment);
      builder.mapValue = _encodeSingleFieldMap(
          BsonKeys.timestamp, proto_v1.Value.create()..mapValue = inner);
    } else if (value is RegexFieldValue) {
      final proto.MapValue inner = proto.MapValue.create();
      inner.fields[BsonKeys.regexPattern] = proto_v1.Value.create()
        ..stringValue = value.value.pattern;
      inner.fields[BsonKeys.regexOptions] = proto_v1.Value.create()
        ..stringValue = value.value.options;
      builder.mapValue = _encodeSingleFieldMap(
          BsonKeys.regex, proto_v1.Value.create()..mapValue = inner);
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
  FieldValue decodeValue(proto_v1.Value proto) {
    switch (proto.whichValueType()) {
      case proto_v1.Value_ValueType.booleanValue:
        return BoolValue.valueOf(proto.booleanValue);
      case proto_v1.Value_ValueType.integerValue:
        return IntegerValue.valueOf(proto.integerValue.toInt());
      case proto_v1.Value_ValueType.doubleValue:
        return DoubleValue.valueOf(proto.doubleValue);
      case proto_v1.Value_ValueType.referenceValue:
        final ResourcePath resourceName =
            _decodeResourceName(proto.referenceValue);
        final DatabaseId id =
            DatabaseId.forDatabase(resourceName[1], resourceName[3]);
        final DocumentKey key = DocumentKey.fromPath(
            _extractLocalPathFromResourceName(resourceName));
        return ReferenceValue.valueOf(id, key);
      case proto_v1.Value_ValueType.mapValue:
        return _decodeMapValue(proto.mapValue);
      case proto_v1.Value_ValueType.geoPointValue:
        final dynamic /*proto.LatLng*/ latLng = proto.geoPointValue;
        return GeoPointValue.valueOf(_decodeGeoPoint(latLng));
      case proto_v1.Value_ValueType.arrayValue:
        return _decodeArrayValue(proto.arrayValue);
      case proto_v1.Value_ValueType.timestampValue:
        final Timestamp timestamp = decodeTimestamp(proto.timestampValue);
        return TimestampValue.valueOf(timestamp);
      case proto_v1.Value_ValueType.nullValue:
        return NullValue.nullValue();

      case proto_v1.Value_ValueType.stringValue:
        return StringValue.valueOf(proto.stringValue);
      case proto_v1.Value_ValueType.bytesValue:
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
    final List<FieldValue> wrappedList =
        protoArray.values.map(decodeValue).toList();
    return ArrayValue.fromList(wrappedList);
  }

  proto.MapValue _encodeMapValue(ObjectValue value) {
    final proto.MapValue builder = proto.MapValue.create();
    for (MapEntry<String, FieldValue> entry in value.internalValue) {
      builder.fields[entry.key] = encodeValue(entry.value);
    }
    return builder..freeze();
  }

  proto.MapValue _encodeVector(VectorFieldValue value) {
    final proto.MapValue builder = proto.MapValue.create();
    builder.fields[VectorFieldValue.typeKey] = proto_v1.Value.create()
      ..stringValue = VectorFieldValue.vectorTypeValue;
    final proto.ArrayValue array = proto.ArrayValue.create();
    for (final double d in value.internalValue) {
      array.values.add(proto_v1.Value.create()..doubleValue = d);
    }
    builder.fields[VectorFieldValue.vectorKey] =
        proto_v1.Value.create()..arrayValue = array;
    return builder..freeze();
  }

  /// Returns the vector encoded by [value] or null if it is not a vector map.
  VectorFieldValue? _tryDecodeVector(proto.MapValue value) {
    final proto_v1.Value? type = value.fields[VectorFieldValue.typeKey];
    if (type == null ||
        type.whichValueType() != proto_v1.Value_ValueType.stringValue ||
        type.stringValue != VectorFieldValue.vectorTypeValue) {
      return null;
    }
    final proto_v1.Value? array = value.fields[VectorFieldValue.vectorKey];
    if (array == null ||
        array.whichValueType() != proto_v1.Value_ValueType.arrayValue) {
      return null;
    }
    final List<double> doubles = <double>[];
    for (final proto_v1.Value element in array.arrayValue.values) {
      switch (element.whichValueType()) {
        case proto_v1.Value_ValueType.doubleValue:
          doubles.add(element.doubleValue);
          break;
        case proto_v1.Value_ValueType.integerValue:
          doubles.add(element.integerValue.toInt().toDouble());
          break;
        default:
          return null;
      }
    }
    return VectorFieldValue.fromList(doubles);
  }

  proto.MapValue _encodeSingleFieldMap(String key, proto_v1.Value value) {
    final proto.MapValue builder = proto.MapValue.create();
    builder.fields[key] = value;
    return builder..freeze();
  }

  /// Returns the BSON value encoded by [value], or null if it is a regular map.
  ///
  /// A BSON value is a map with a single reserved key whose value has the
  /// expected type. Any other shape is a regular map.
  FieldValue? _tryDecodeBson(proto.MapValue value) {
    if (value.fields.length != 1) {
      return null;
    }
    final String key = value.fields.keys.first;
    final proto_v1.Value field = value.fields.values.first;
    final proto_v1.Value_ValueType type = field.whichValueType();
    switch (key) {
      case BsonKeys.minKey:
        return type == proto_v1.Value_ValueType.nullValue
            ? MinKeyValue.instance()
            : null;
      case BsonKeys.maxKey:
        return type == proto_v1.Value_ValueType.nullValue
            ? MaxKeyValue.instance()
            : null;
      case BsonKeys.int32:
        if (type != proto_v1.Value_ValueType.integerValue) {
          return null;
        }
        final int int32 = field.integerValue.toInt();
        if (int32 < Int32Value.minValue || int32 > Int32Value.maxValue) {
          return null;
        }
        return Int32FieldValue.valueOf(Int32Value(int32));
      case BsonKeys.decimal128:
        if (type != proto_v1.Value_ValueType.stringValue) {
          return null;
        }
        try {
          return Decimal128FieldValue.valueOf(
              Decimal128Value(field.stringValue));
        } on FormatException {
          return null;
        }
      case BsonKeys.objectId:
        return type == proto_v1.Value_ValueType.stringValue
            ? BsonObjectIdValue.valueOf(BsonObjectId(field.stringValue))
            : null;
      case BsonKeys.binary:
        // A subtype of 0 is a regular blob, which is never encoded as a map.
        if (type != proto_v1.Value_ValueType.bytesValue ||
            field.bytesValue.isEmpty ||
            field.bytesValue[0] == 0) {
          return null;
        }
        return BlobValue.valueOf(Blob.bsonBinary(field.bytesValue[0] & 0xff,
            Uint8List.fromList(field.bytesValue.sublist(1))));
      case BsonKeys.timestamp:
        if (type != proto_v1.Value_ValueType.mapValue) {
          return null;
        }
        final Map<String, proto_v1.Value> inner = field.mapValue.fields;
        final proto_v1.Value? seconds = inner[BsonKeys.timestampSeconds];
        final proto_v1.Value? increment = inner[BsonKeys.timestampIncrement];
        if (inner.length != 2 ||
            seconds == null ||
            increment == null ||
            seconds.whichValueType() != proto_v1.Value_ValueType.integerValue ||
            increment.whichValueType() !=
                proto_v1.Value_ValueType.integerValue) {
          return null;
        }
        final int secondsValue = seconds.integerValue.toInt();
        final int incrementValue = increment.integerValue.toInt();
        if (secondsValue < 0 ||
            secondsValue > BsonTimestamp.maxValue ||
            incrementValue < 0 ||
            incrementValue > BsonTimestamp.maxValue) {
          return null;
        }
        return BsonTimestampValue.valueOf(
            BsonTimestamp(secondsValue, incrementValue));
      case BsonKeys.regex:
        if (type != proto_v1.Value_ValueType.mapValue) {
          return null;
        }
        final Map<String, proto_v1.Value> inner = field.mapValue.fields;
        final proto_v1.Value? pattern = inner[BsonKeys.regexPattern];
        final proto_v1.Value? options = inner[BsonKeys.regexOptions];
        if (inner.length != 2 ||
            pattern == null ||
            options == null ||
            pattern.whichValueType() != proto_v1.Value_ValueType.stringValue ||
            options.whichValueType() != proto_v1.Value_ValueType.stringValue) {
          return null;
        }
        return RegexFieldValue.valueOf(
            RegexValue(pattern.stringValue, options.stringValue));
      default:
        return null;
    }
  }

  FieldValue _decodeMapValue(proto.MapValue value) {
    final FieldValue? bson = _tryDecodeBson(value);
    if (bson != null) {
      return bson;
    }
    final VectorFieldValue? vector = _tryDecodeVector(value);
    if (vector != null) {
      return vector;
    }
    return decodeMapFields(value.fields);
  }

  // PORTING NOTE: There's no encodeFields here because there's no way to write  it that doesn't
  // involve creating a temporary map.
  ObjectValue decodeMapFields(Map<String, proto_v1.Value> fields) {
    ObjectValue result = ObjectValue.empty;
    for (MapEntry<String, proto_v1.Value> entry in fields.entries) {
      final FieldPath path = FieldPath.fromSingleSegment(entry.key);
      final FieldValue value = decodeValue(entry.value);
      result = result.set(path, value);
    }
    return result;
  }

  ObjectValue decodeDocumentFields(Map<String, proto_v1.Value> fields) {
    ObjectValue result = ObjectValue.empty;
    for (MapEntry<String, proto_v1.Value> entry in fields.entries) {
      final FieldPath path = FieldPath.fromSingleSegment(entry.key);
      final FieldValue value = decodeValue(entry.value);
      result = result.set(path, value);
    }
    return result;
  }

  // Documents

  proto.Document encodeDocument(DocumentKey key, ObjectValue value) {
    final proto.Document builder = proto.Document.create()
      ..name = encodeKey(key);

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
    hardAssert(response.hasFound(),
        'Tried to deserialize a found document from a missing document.');
    final DocumentKey key = decodeKey(response.found.name);
    final SnapshotVersion version = decodeVersion(response.found.updateTime);
    hardAssert(version != SnapshotVersion.none,
        'Got a document response with no snapshot version');
    return Document.fromProto(
        key, version, DocumentState.synced, response.found, decodeValue);
  }

  NoDocument _decodeMissingDocument(proto.BatchGetDocumentsResponse response) {
    hardAssert(response.hasMissing(),
        'Tried to deserialize a missing document from a found document.');
    final DocumentKey key = decodeKey(response.missing);
    final SnapshotVersion version = decodeVersion(response.readTime);
    hardAssert(version != SnapshotVersion.none,
        'Got a no document response with no snapshot version');
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

    for (FieldTransform fieldTransform in mutation.fieldTransforms) {
      builder.updateTransforms.add(_encodeFieldTransform(fieldTransform));
    }

    if (!mutation.precondition.isNone) {
      builder.currentDocument = _encodePrecondition(mutation.precondition);
    }
    return builder..freeze();
  }

  Mutation decodeMutation(proto.Write mutation) {
    final Precondition precondition = mutation.hasCurrentDocument()
        ? _decodePrecondition(mutation.currentDocument)
        : Precondition.none;

    if (mutation.hasUpdate()) {
      final List<FieldTransform> fieldTransforms =
          mutation.updateTransforms.map(_decodeFieldTransform).toList();
      if (mutation.hasUpdateMask()) {
        return PatchMutation(
            decodeKey(mutation.update.name),
            decodeDocumentFields(mutation.update.fields),
            _decodeDocumentMask(mutation.updateMask),
            precondition,
            fieldTransforms);
      } else {
        return SetMutation(decodeKey(mutation.update.name),
            decodeDocumentFields(mutation.update.fields), precondition,
            fieldTransforms);
      }
    } else if (mutation.hasDelete()) {
      return DeleteMutation(decodeKey(mutation.delete), precondition);
    } else if (mutation.hasVerify()) {
      return VerifyMutation(decodeKey(mutation.verify), precondition);
    } else {
      throw fail('Unknown mutation operation: $mutation');
    }
  }

  proto.Precondition _encodePrecondition(Precondition precondition) {
    hardAssert(!precondition.isNone, 'Can\'t serialize an empty precondition');
    final proto.Precondition builder = proto.Precondition.create();
    final SnapshotVersion? updateTime = precondition.updateTime;
    final bool? exists = precondition.exists;
    if (updateTime != null) {
      return builder
        ..updateTime = encodeVersion(updateTime)
        ..freeze();
    } else if (exists != null) {
      return builder
        ..exists = exists
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
    final Set<FieldPath> paths = mask.fieldPaths
        .map(FieldPath.fromServerFormat)
        .toSet();
    return FieldMask(paths);
  }

  proto.DocumentTransform_FieldTransform _encodeFieldTransform(
      FieldTransform fieldTransform) {
    final TransformOperation transform = fieldTransform.operation;
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
            _encodeArrayTransformElements(transform.elements)
        ..freeze();
    } else if (transform is ArrayTransformOperationRemove) {
      return proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = fieldTransform.fieldPath.canonicalString
        ..removeAllFromArray = _encodeArrayTransformElements(transform.elements)
        ..freeze();
    } else if (transform is NumericIncrementTransformOperation) {
      return proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = fieldTransform.fieldPath.canonicalString
        ..increment = encodeValue(transform.operand)
        ..freeze();
    } else if (transform is NumericMinimumTransformOperation) {
      return proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = fieldTransform.fieldPath.canonicalString
        ..minimum = encodeValue(transform.operand)
        ..freeze();
    } else if (transform is NumericMaximumTransformOperation) {
      return proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = fieldTransform.fieldPath.canonicalString
        ..maximum = encodeValue(transform.operand)
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

  FieldTransform _decodeFieldTransform(
      proto.DocumentTransform_FieldTransform fieldTransform) {
    if (fieldTransform.hasSetToServerValue()) {
      hardAssertLazy(
          fieldTransform.setToServerValue ==
              proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME,
          () =>
              'Unknown transform setToServerValue: ${fieldTransform.setToServerValue}');
      return FieldTransform(
          FieldPath.fromServerFormat(fieldTransform.fieldPath),
          ServerTimestampOperation.sharedInstance);
    } else if (fieldTransform.hasAppendMissingElements()) {
      return FieldTransform(
          FieldPath.fromServerFormat(fieldTransform.fieldPath),
          ArrayTransformOperationUnion(_decodeArrayTransformElements(
              fieldTransform.appendMissingElements)));
    } else if (fieldTransform.hasRemoveAllFromArray()) {
      return FieldTransform(
          FieldPath.fromServerFormat(fieldTransform.fieldPath),
          ArrayTransformOperationRemove(_decodeArrayTransformElements(
              fieldTransform.removeAllFromArray)));
    } else if (fieldTransform.hasIncrement()) {
      return FieldTransform(
          FieldPath.fromServerFormat(fieldTransform.fieldPath),
          NumericIncrementTransformOperation(
              decodeValue(fieldTransform.increment) as NumberValue));
    } else if (fieldTransform.hasMinimum()) {
      return FieldTransform(
          FieldPath.fromServerFormat(fieldTransform.fieldPath),
          NumericMinimumTransformOperation(
              decodeValue(fieldTransform.minimum) as NumberValue));
    } else if (fieldTransform.hasMaximum()) {
      return FieldTransform(
          FieldPath.fromServerFormat(fieldTransform.fieldPath),
          NumericMaximumTransformOperation(
              decodeValue(fieldTransform.maximum) as NumberValue));
    } else {
      throw fail(
        'Unknown FieldTransform proto: $fieldTransform',
      );
    }
  }

  List<FieldValue> _decodeArrayTransformElements(
      proto.ArrayValue elementsProto) {
    return elementsProto.values.map(decodeValue).toList();
  }

  MutationResult decodeMutationResult(
      proto.WriteResult proto, SnapshotVersion commitVersion) {
    // NOTE: Deletes don't have an [updateTime] but the commit timestamp from the containing [CommitResponse] or
    // [WriteResponse] indicates essentially that the delete happened no later than that. For our purposes we don't care
    // exactly when the delete happened so long as we can tell when an update on the watch stream is at or later than
    // that change.
    SnapshotVersion version = decodeVersion(proto.updateTime);
    if (version == SnapshotVersion.none) {
      version = commitVersion;
    }

    final List<FieldValue> transformResults =
        proto.transformResults.map(decodeValue).toList();
    return MutationResult(version, transformResults);
  }

  // Queries

  Map<String, String> encodeListenRequestLabels(QueryData queryData) {
    final String? value = _encodeLabel(queryData.purpose);
    if (value == null) {
      return <String, String>{};
    }

    return <String, String>{'goog-listen-tags': value};
  }

  String? _encodeLabel(QueryPurpose purpose) {
    switch (purpose) {
      case QueryPurpose.listen:
        return null;
      case QueryPurpose.existenceFilterMismatch:
        return 'existence-filter-mismatch';
      case QueryPurpose.existenceFilterMismatchBloom:
        return 'existence-filter-mismatch-bloom';
      case QueryPurpose.limboResolution:
        return 'limbo-document';
    }
  }

  proto_v1.Target encodeTarget(QueryData queryData) {
    final proto_v1.Target builder = proto_v1.Target.create();
    final Target target = queryData.target;

    if (target.isDocumentQuery) {
      builder.documents = encodeDocumentsTarget(target);
    } else {
      builder.query = encodeQueryTarget(target);
    }

    builder.targetId = queryData.targetId;

    if (queryData.resumeToken.isEmpty &&
        queryData.snapshotVersion.compareTo(SnapshotVersion.none) > 0) {
      // A target without a resume token but with a snapshot version (for example a named query loaded from a bundle)
      // is resumed from that read time.
      builder.readTime = encodeTimestamp(queryData.snapshotVersion.timestamp);
    } else {
      builder.resumeToken = queryData.resumeToken;
    }

    // The expected count only makes sense relative to a resume token: it is the
    // number of documents the client had when that token was handed out.
    // PORTING NOTE: upstream also sends it together with a read time; this port
    // only does so for resume tokens.
    if (queryData.expectedCount != null && queryData.resumeToken.isNotEmpty) {
      builder.expectedCount = proto.Int32Value(value: queryData.expectedCount);
    }

    return builder..freeze();
  }

  proto.Target_DocumentsTarget encodeDocumentsTarget(Target target) {
    return proto.Target_DocumentsTarget.create()
      ..documents.add(_encodeQueryPath(target.path))
      ..freeze();
  }

  Target decodeDocumentsTarget(proto.Target_DocumentsTarget target) {
    final int count = target.documents.length;
    hardAssertLazy(count == 1,
        () => 'DocumentsTarget contained other than 1 document $count');

    final String name = target.documents[0];
    return Query(_decodeQueryPath(name)).toTarget();
  }

  proto.Target_QueryTarget encodeQueryTarget(Target target) {
    // Dissect the path into [parent], [collectionId], and optional [key] filter.
    final proto.Target_QueryTarget builder = proto.Target_QueryTarget.create();
    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create();
    final ResourcePath path = target.path;
    final String? collectionGroup = target.collectionGroup;
    if (collectionGroup != null) {
      hardAssert(path.length % 2 == 0,
          'Collection Group queries should be within a document path or root.');
      builder.parent = _encodeQueryPath(path);

      structuredQueryBuilder.from.add(proto.StructuredQuery_CollectionSelector()
        ..collectionId = collectionGroup
        ..allDescendants = true);
    } else {
      hardAssert(path.length.remainder(2) != 0,
          'Document queries with filters are not supported.');
      builder.parent = _encodeQueryPath(path.popLast());

      final proto.StructuredQuery_CollectionSelector from =
          proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = path.last;
      structuredQueryBuilder.from.add(from);
    }

    // Encode the filters.
    if (target.filters.isNotEmpty) {
      structuredQueryBuilder.where = _encodeFilters(target.filters);
    }

    // Encode the orders.
    for (OrderBy orderBy in target.orderBy) {
      structuredQueryBuilder.orderBy.add(_encodeOrderBy(orderBy));
    }

    // Encode the limit.
    if (target.hasLimit) {
      final proto.Int32Value limit = proto.Int32Value.create()
        ..value = target.getLimit();
      structuredQueryBuilder.limit = limit;
    }

    final Bound? startAt = target.startAt;
    if (startAt != null) {
      structuredQueryBuilder.startAt = _encodeBound(startAt, isStart: true);
    }

    final Bound? endAt = target.endAt;
    if (endAt != null) {
      structuredQueryBuilder.endAt = _encodeBound(endAt, isStart: false);
    }

    builder.structuredQuery = structuredQueryBuilder;
    return builder..freeze();
  }

  Target decodeQueryTarget(proto.Target_QueryTarget target) {
    ResourcePath path = _decodeQueryPath(target.parent);

    final proto.StructuredQuery query = target.structuredQuery;
    String? collectionGroup;
    final int fromCount = query.from.length;
    if (fromCount > 0) {
      hardAssert(fromCount == 1,
          'StructuredQuery.from with more than one collection is not supported.');

      final proto.StructuredQuery_CollectionSelector from = query.from[0];
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

    final List<OrderBy> orderBy = query.orderBy.map(_decodeOrderBy).toList();

    int limit = Target.noLimit;
    if (query.hasLimit()) {
      limit = query.limit.value;
    }

    Bound? startAt;
    if (query.hasStartAt()) {
      startAt = _decodeBound(query.startAt, isStart: true);
    }

    Bound? endAt;
    if (query.hasEndAt()) {
      endAt = _decodeBound(query.endAt, isStart: false);
    }

    return Query(
      path,
      collectionGroup: collectionGroup,
      filters: filterBy,
      explicitSortOrder: orderBy,
      limit: limit,
      startAt: startAt,
      endAt: endAt,
    ).toTarget();
  }

  // Filters

  proto.StructuredQuery_Filter _encodeFilters(List<Filter> filters) {
    // A target's filter list is implicitly a composite AND filter.
    return encodeFilter(
        CompositeFilter(filters, CompositeFilterOperator.and));
  }

  List<Filter> _decodeFilters(proto.StructuredQuery_Filter value) {
    // Instead of a singleton list containing AND(F1, F2, ...), return a list
    // containing F1, F2, ... to stay consistent with the older SDK versions
    // (the filters of a target are an implicit AND, see
    // CompositeFilter.conjunctionTerms).
    return CompositeFilter.conjunctionTerms(decodeFilter(value));
  }

  @visibleForTesting
  proto.StructuredQuery_Filter encodeFilter(Filter filter) {
    if (filter is FieldFilter) {
      return encodeUnaryOrFieldFilter(filter);
    } else if (filter is CompositeFilter) {
      return encodeCompositeFilter(filter);
    } else {
      throw fail('Unrecognized filter type $filter');
    }
  }

  proto.StructuredQuery_CompositeFilter_Operator _encodeCompositeFilterOperator(
      CompositeFilterOperator operator) {
    switch (operator) {
      case CompositeFilterOperator.and:
        return proto.StructuredQuery_CompositeFilter_Operator.AND;
      case CompositeFilterOperator.or:
        return proto.StructuredQuery_CompositeFilter_Operator.OR;
    }
  }

  CompositeFilterOperator _decodeCompositeFilterOperator(
      proto.StructuredQuery_CompositeFilter_Operator operator) {
    switch (operator) {
      case proto.StructuredQuery_CompositeFilter_Operator.AND:
        return CompositeFilterOperator.and;
      case proto.StructuredQuery_CompositeFilter_Operator.OR:
        return CompositeFilterOperator.or;
      default:
        throw fail('Only AND and OR composite filter types are supported.');
    }
  }

  @visibleForTesting
  proto.StructuredQuery_Filter encodeCompositeFilter(CompositeFilter filter) {
    final List<proto.StructuredQuery_Filter> protos =
        filter.filters.map(encodeFilter).toList();

    // If there's only one filter in the composite filter, use it directly.
    if (protos.length == 1) {
      return protos[0];
    }

    final proto.StructuredQuery_CompositeFilter composite =
        proto.StructuredQuery_CompositeFilter.create()
          ..op = _encodeCompositeFilterOperator(filter.operator)
          ..filters.addAll(protos);

    return proto.StructuredQuery_Filter.create()
      ..compositeFilter = composite
      ..freeze();
  }

  @visibleForTesting
  Filter decodeFilter(proto.StructuredQuery_Filter value) {
    if (value.hasCompositeFilter()) {
      return decodeCompositeFilter(value.compositeFilter);
    } else if (value.hasFieldFilter()) {
      return decodeFieldFilter(value.fieldFilter);
    } else if (value.hasUnaryFilter()) {
      return _decodeUnaryFilter(value.unaryFilter);
    } else {
      throw fail('Unrecognized Filter.filterType $value');
    }
  }

  @visibleForTesting
  CompositeFilter decodeCompositeFilter(
      proto.StructuredQuery_CompositeFilter value) {
    return CompositeFilter(
      value.filters.map(decodeFilter).toList(),
      _decodeCompositeFilterOperator(value.op),
    );
  }

  @visibleForTesting
  proto.StructuredQuery_Filter encodeUnaryOrFieldFilter(FieldFilter filter) {
    if (filter.operator == FilterOperator.equal ||
        filter.operator == FilterOperator.notEqual) {
      final proto.StructuredQuery_UnaryFilter unaryProto =
          proto.StructuredQuery_UnaryFilter()
            ..field_2 = _encodeFieldPath(filter.field);

      if (filter.value == DoubleValue.nan) {
        unaryProto.op = filter.operator == FilterOperator.equal
            ? proto_v1.StructuredQuery_UnaryFilter_Operator.IS_NAN
            : proto_v1.StructuredQuery_UnaryFilter_Operator.IS_NOT_NAN;
        return proto.StructuredQuery_Filter()
          ..unaryFilter = unaryProto
          ..freeze();
      } else if (filter.value == NullValue.nullValue()) {
        unaryProto.op = filter.operator == FilterOperator.equal
            ? proto_v1.StructuredQuery_UnaryFilter_Operator.IS_NULL
            : proto_v1.StructuredQuery_UnaryFilter_Operator.IS_NOT_NULL;
        return proto.StructuredQuery_Filter()
          ..unaryFilter = unaryProto
          ..freeze();
      }
    }
    final proto.StructuredQuery_FieldFilter builder =
        proto.StructuredQuery_FieldFilter()
          ..field_1 = _encodeFieldPath(filter.field)
          ..op = _encodeFieldFilterOperator(filter.operator)
          ..value = encodeValue(filter.value);

    return proto.StructuredQuery_Filter.create()
      ..fieldFilter = builder
      ..freeze();
  }

  @visibleForTesting
  FieldFilter decodeFieldFilter(proto.StructuredQuery_FieldFilter builder) {
    final FieldPath fieldPath =
        FieldPath.fromServerFormat(builder.field_1.fieldPath);

    final FilterOperator filterOperator =
        _decodeFieldFilterOperator(builder.op);
    final FieldValue value = decodeValue(builder.value);
    return FieldFilter(fieldPath, filterOperator, value);
  }

  FieldFilter _decodeUnaryFilter(proto.StructuredQuery_UnaryFilter value) {
    final FieldPath fieldPath =
        FieldPath.fromServerFormat(value.field_2.fieldPath);
    switch (value.op) {
      case proto.StructuredQuery_UnaryFilter_Operator.IS_NAN:
        return FieldFilter(fieldPath, FilterOperator.equal, DoubleValue.nan);
      case proto.StructuredQuery_UnaryFilter_Operator.IS_NULL:
        return FieldFilter(
            fieldPath, FilterOperator.equal, NullValue.nullValue());
      case proto.StructuredQuery_UnaryFilter_Operator.IS_NOT_NAN:
        return FieldFilter(fieldPath, FilterOperator.notEqual, DoubleValue.nan);
      case proto.StructuredQuery_UnaryFilter_Operator.IS_NOT_NULL:
        return FieldFilter(
            fieldPath, FilterOperator.notEqual, NullValue.nullValue());
      default:
        throw fail('Unrecognized UnaryFilter.operator ${value.op}');
    }
  }

  proto.StructuredQuery_FieldReference _encodeFieldPath(FieldPath field) {
    return proto.StructuredQuery_FieldReference.create()
      ..fieldPath = field.canonicalString
      ..freeze();
  }

  proto.StructuredQuery_FieldFilter_Operator _encodeFieldFilterOperator(
      FilterOperator operator) {
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
      case FilterOperator.arrayContainsAny:
        return proto.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS_ANY;
      case FilterOperator.IN:
        return proto.StructuredQuery_FieldFilter_Operator.IN;
      case FilterOperator.NOT_IN:
        return proto.StructuredQuery_FieldFilter_Operator.NOT_IN;
      default:
        throw fail('Unknown operator $operator');
    }
  }

  FilterOperator _decodeFieldFilterOperator(
      proto.StructuredQuery_FieldFilter_Operator operator) {
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
      case proto.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS_ANY:
        return FilterOperator.arrayContainsAny;
      case proto.StructuredQuery_FieldFilter_Operator.IN:
        return FilterOperator.IN;
      case proto.StructuredQuery_FieldFilter_Operator.NOT_IN:
        return FilterOperator.NOT_IN;
      default:
        throw fail('Unhandled FieldFilter.operator $operator');
    }
  }

  // Property orders

  proto.StructuredQuery_Order _encodeOrderBy(OrderBy orderBy) {
    final proto.StructuredQuery_Order builder =
        proto.StructuredQuery_Order.create();
    if (orderBy.direction == OrderByDirection.ascending) {
      builder.direction = proto.StructuredQuery_Direction.ASCENDING;
    } else {
      builder.direction = proto.StructuredQuery_Direction.DESCENDING;
    }

    builder.field_1 = _encodeFieldPath(orderBy.field);

    return builder..freeze();
  }

  OrderBy _decodeOrderBy(proto.StructuredQuery_Order value) {
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
        throw fail('Unrecognized direction ${value.direction}');
    }
    return OrderBy.getInstance(direction, fieldPath);
  }

  // Bounds

  // A start cursor that is `before` its position includes it, an end cursor
  // that is `before` its position excludes it.

  proto.Cursor _encodeBound(Bound bound, {required bool isStart}) {
    final proto.Cursor builder = proto.Cursor.create()
      ..before = isStart ? bound.inclusive : !bound.inclusive;
    for (FieldValue component in bound.position) {
      builder.values.add(encodeValue(component));
    }
    return builder..freeze();
  }

  Bound _decodeBound(proto.Cursor value, {required bool isStart}) {
    final List<FieldValue> indexComponents =
        value.values.map(decodeValue).toList();
    return Bound(
        position: indexComponents,
        inclusive: isStart ? value.before : !value.before);
  }

  // Watch changes

  WatchChange decodeWatchChange(proto.ListenResponse protoChange) {
    final WatchChange watchChange;

    if (protoChange.hasTargetChange()) {
      final proto.TargetChange targetChange = protoChange.targetChange;
      WatchTargetChangeType changeType;
      GrpcError? cause;
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
      final SnapshotVersion version =
          decodeVersion(docChange.document.updateTime);
      hardAssert(version != SnapshotVersion.none,
          'Got a document change without an update time');
      final Document document = Document.fromProto(
          key, version, DocumentState.synced, docChange.document, decodeValue);
      watchChange =
          WatchChangeDocumentChange(added, removed, document.key, document);
    } else if (protoChange.hasDocumentDelete()) {
      final proto.DocumentDelete docDelete = protoChange.documentDelete;
      final List<int> removed = docDelete.removedTargetIds;
      final DocumentKey key = decodeKey(docDelete.document);
      // Note that version might be unset in which case we use SnapshotVersion.none
      final SnapshotVersion version = decodeVersion(docDelete.readTime);
      final NoDocument doc =
          NoDocument(key, version, hasCommittedMutations: false);
      watchChange = WatchChangeDocumentChange(<int>[], removed, doc.key, doc);
    } else if (protoChange.hasDocumentRemove()) {
      final proto.DocumentRemove docRemove = protoChange.documentRemove;
      final List<int> removed = docRemove.removedTargetIds;
      final DocumentKey key = decodeKey(docRemove.document);
      watchChange = WatchChangeDocumentChange(<int>[], removed, key, null);
    } else if (protoChange.hasFilter()) {
      final proto.ExistenceFilter protoFilter = protoChange.filter;
      final ExistenceFilter filter = ExistenceFilter(
        protoFilter.count,
        protoFilter.hasUnchangedNames() ? protoFilter.unchangedNames : null,
      );
      final int targetId = protoFilter.targetId;
      watchChange = WatchChangeExistenceFilterWatchChange(targetId, filter);
    } else {
      throw ArgumentError('Unknown change type set');
    }

    return watchChange;
  }

  SnapshotVersion decodeVersionFromListenResponse(
      proto.ListenResponse watchChange) {
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
    return GrpcError.custom(
        status.code, status.hasMessage() ? status.message : null);
  }
}
