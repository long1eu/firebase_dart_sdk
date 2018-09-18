// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_common/firebase_common.dart';

@publicApi
enum FirebaseFirestoreErrorCode {
  ok,
  canceled,
  unknown,
  invalidArgument,
  deadlineExceeded,
  notFound,
  alreadyExists,
  permissionDenied,
  resourcesExhausted,
  failedPrecondition,
  aborted,
  outOfRange,
  unimplemented,
  internal,
  unavailable,
  dataLoss,
  unauthenticated
}

@publicApi
class FirebaseFirestoreError extends FirebaseError {
  FirebaseFirestoreErrorCode code;

  FirebaseFirestoreError(String message, FirebaseFirestoreErrorCode code,
      [StackTrace stackTrance])
      : super(message, stackTrance) {
    Preconditions.checkNotNull(message);
    Preconditions.checkNotNull(code);
  }
}
