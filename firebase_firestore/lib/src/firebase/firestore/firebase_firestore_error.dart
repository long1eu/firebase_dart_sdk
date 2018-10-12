// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_common/firebase_common.dart';

@publicApi
class FirebaseFirestoreErrorCode {
  final int value;

  const FirebaseFirestoreErrorCode._(this.value);

  static const FirebaseFirestoreErrorCode ok = FirebaseFirestoreErrorCode._(0);
  static const FirebaseFirestoreErrorCode canceled =
      FirebaseFirestoreErrorCode._(1);
  static const FirebaseFirestoreErrorCode unknown =
      FirebaseFirestoreErrorCode._(2);
  static const FirebaseFirestoreErrorCode invalidArgument =
      FirebaseFirestoreErrorCode._(3);
  static const FirebaseFirestoreErrorCode deadlineExceeded =
      FirebaseFirestoreErrorCode._(4);
  static const FirebaseFirestoreErrorCode notFound =
      FirebaseFirestoreErrorCode._(5);
  static const FirebaseFirestoreErrorCode alreadyExists =
      FirebaseFirestoreErrorCode._(6);
  static const FirebaseFirestoreErrorCode permissionDenied =
      FirebaseFirestoreErrorCode._(7);
  static const FirebaseFirestoreErrorCode resourcesExhausted =
      FirebaseFirestoreErrorCode._(8);
  static const FirebaseFirestoreErrorCode failedPrecondition =
      FirebaseFirestoreErrorCode._(9);
  static const FirebaseFirestoreErrorCode aborted =
      FirebaseFirestoreErrorCode._(10);
  static const FirebaseFirestoreErrorCode outOfRange =
      FirebaseFirestoreErrorCode._(11);
  static const FirebaseFirestoreErrorCode unimplemented =
      FirebaseFirestoreErrorCode._(12);
  static const FirebaseFirestoreErrorCode internal =
      FirebaseFirestoreErrorCode._(13);
  static const FirebaseFirestoreErrorCode unavailable =
      FirebaseFirestoreErrorCode._(14);
  static const FirebaseFirestoreErrorCode dataLoss =
      FirebaseFirestoreErrorCode._(15);
  static const FirebaseFirestoreErrorCode unauthenticated =
      FirebaseFirestoreErrorCode._(16);

  static const List<FirebaseFirestoreErrorCode> values =
      const <FirebaseFirestoreErrorCode>[
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
  ];

  @override
  String toString() {
    return <String>[
      'ok',
      'canceled',
      'unknown',
      'invalidArgument',
      'deadlineExceeded',
      'notFound',
      'alreadyExists',
      'permissionDenied',
      'resourcesExhausted',
      'failedPrecondition',
      'aborted',
      'outOfRange',
      'unimplemented',
      'internal',
      'unavailable',
      'dataLoss',
      'unauthenticated',
    ][value];
  }
}

@publicApi
class FirebaseFirestoreError extends FirebaseError {
  final FirebaseFirestoreErrorCode code;
  final dynamic cause;

  FirebaseFirestoreError(
    String message,
    this.code, [
    this.cause,
    StackTrace stackTrance,
  ]) : super(message, stackTrance) {
    Preconditions.checkNotNull(message);
    Preconditions.checkNotNull(code);
  }

  @override
  String toString() => '$runtimeType:$code $message $cause $stackTrace';
}
