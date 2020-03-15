// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';

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

  @override
  bool get isIdempotent => true;

// NOTE: Since we've guaranteed a singleton instance, we can rely on Object's
// default implementation of equals() / hashCode().
}
