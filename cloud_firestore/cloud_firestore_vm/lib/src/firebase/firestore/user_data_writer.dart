// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:typed_data';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/server_timestamps.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/values.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart' show Value;
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart' as pb;
import 'package:cloud_firestore_vm/src/proto/google/protobuf/index.dart' as pb;
import 'package:cloud_firestore_vm/src/proto/google/type/index.dart' as pb;

/// Helper for parsing raw user input (provided via the API) into internal model classes.
class UserDataWriter {
  const UserDataWriter(this.firestore, this.serverTimestampBehavior);

  final Firestore firestore;
  final ServerTimestampBehavior serverTimestampBehavior;

  Object convertValue(Value value) {
    switch (typeOrder(value)) {
      case TYPE_ORDER_MAP:
        return convertObject(value.mapValue.fields);
      case TYPE_ORDER_ARRAY:
        return _convertArray(value.arrayValue);
      case TYPE_ORDER_REFERENCE:
        return _convertReference(value);
      case TYPE_ORDER_TIMESTAMP:
        return _convertTimestamp(value.timestampValue);
      case TYPE_ORDER_SERVER_TIMESTAMP:
        return _convertServerTimestamp(value);
      case TYPE_ORDER_NULL:
        return null;
      case TYPE_ORDER_BOOL:
        return value.booleanValue;
      case TYPE_ORDER_NUMBER:
        return value.whichValueType() == pb.Value_ValueType.integerValue
            ? value.integerValue.toInt()
            : value.doubleValue;
      case TYPE_ORDER_STRING:
        return value.stringValue;
      case TYPE_ORDER_BLOB:
        return Uint8List.fromList(value.bytesValue);
      case TYPE_ORDER_GEOPOINT:
        return GeoPoint(
          value.geoPointValue.latitude,
          value.geoPointValue.longitude,
        );
      default:
        throw fail('Unknown value type: ${value.whichValueType()}');
    }
  }

  Map<String, Object> convertObject(Map<String, Value> mapValue) {
    return mapValue.map((String key, Value value) => MapEntry<String, Object>(key, convertValue(value)));
  }

  Object _convertServerTimestamp(Value serverTimestampValue) {
    switch (serverTimestampBehavior) {
      case ServerTimestampBehavior.previous:
        final Value previousValue = ServerTimestamps.getPreviousValue(serverTimestampValue);
        if (previousValue == null) {
          return null;
        }
        return convertValue(previousValue);
      case ServerTimestampBehavior.estimate:
        return _convertTimestamp(ServerTimestamps.getLocalWriteTime(serverTimestampValue));
      default:
        return null;
    }
  }

  Object _convertTimestamp(pb.Timestamp value) {
    return Timestamp(value.seconds.toInt(), value.nanos);
  }

  List<Object> _convertArray(pb.ArrayValue arrayValue) {
    return arrayValue.values.map(convertValue).toList();
  }

  Object _convertReference(Value value) {
    final DatabaseId refDatabase = DatabaseId.fromName(value.referenceValue);
    final DocumentKey key = DocumentKey.fromName(value.referenceValue);
    final DatabaseId database = firestore.databaseId;
    if (refDatabase != database) {
      // TODO: Somehow support foreign references.
      Log.w(
        'DocumentSnapshot',
        'Document ${key.path} contains a document reference within a different database '
            '(${refDatabase.projectId}/${refDatabase.databaseId}) which is not supported. '
            'It will be treated as a reference in the current database '
            '(${database.projectId}/${database.databaseId}) instead.',
      );
    }
    return DocumentReference(key, firestore);
  }
}
