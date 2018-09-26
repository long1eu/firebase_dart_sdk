// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/server_timestamp_value.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';

/// Transforms a value into a server-generated timestamp.
class ServerTimestampOperation implements TransformOperation {
  factory ServerTimestampOperation() => sharedInstance;

  const ServerTimestampOperation._();

  static const ServerTimestampOperation sharedInstance =
      ServerTimestampOperation._();

  @override
  FieldValue applyToLocalView(
      FieldValue previousValue, Timestamp localWriteTime) {
    return ServerTimestampValue(localWriteTime, previousValue);
  }

  @override
  FieldValue applyToRemoteDocument(
      FieldValue previousValue, FieldValue transformResult) {
    return transformResult;
  }

// NOTE: Since we've guaranteed a singleton instance, we can rely on Object's
// default implementation of equals() / hashCode().
}
