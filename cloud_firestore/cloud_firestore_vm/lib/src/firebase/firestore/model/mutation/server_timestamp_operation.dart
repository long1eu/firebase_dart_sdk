// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/server_timestamps.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart';

/// Transforms a value into a server-generated timestamp.
class ServerTimestampOperation implements TransformOperation {
  factory ServerTimestampOperation() => sharedInstance;

  const ServerTimestampOperation._();

  static const ServerTimestampOperation sharedInstance = ServerTimestampOperation._();

  @override
  Value applyToLocalView(Value previousValue, Timestamp localWriteTime) {
    return ServerTimestamps.valueOf(localWriteTime, previousValue);
  }

  @override
  Value applyToRemoteDocument(Value previousValue, Value transformResult) {
    return transformResult;
  }

  @override
  Value computeBaseValue(Value currentValue) {
    // Server timestamps are idempotent and don't require a base value.
    return null;
  }

// NOTE: Since we've guaranteed a singleton instance, we can rely on Object's
// default implementation of equals() / hashCode().
}
