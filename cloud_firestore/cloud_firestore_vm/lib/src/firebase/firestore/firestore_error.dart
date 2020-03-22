// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart';

class FirestoreErrorCode {
  const FirestoreErrorCode._(this.value);

  final int value;

  static const FirestoreErrorCode ok = FirestoreErrorCode._(0);
  static const FirestoreErrorCode canceled = FirestoreErrorCode._(1);
  static const FirestoreErrorCode unknown = FirestoreErrorCode._(2);
  static const FirestoreErrorCode invalidArgument = FirestoreErrorCode._(3);
  static const FirestoreErrorCode deadlineExceeded = FirestoreErrorCode._(4);
  static const FirestoreErrorCode notFound = FirestoreErrorCode._(5);
  static const FirestoreErrorCode alreadyExists = FirestoreErrorCode._(6);
  static const FirestoreErrorCode permissionDenied = FirestoreErrorCode._(7);
  static const FirestoreErrorCode resourcesExhausted = FirestoreErrorCode._(8);
  static const FirestoreErrorCode failedPrecondition = FirestoreErrorCode._(9);
  static const FirestoreErrorCode aborted = FirestoreErrorCode._(10);
  static const FirestoreErrorCode outOfRange = FirestoreErrorCode._(11);
  static const FirestoreErrorCode unimplemented = FirestoreErrorCode._(12);
  static const FirestoreErrorCode internal = FirestoreErrorCode._(13);
  static const FirestoreErrorCode unavailable = FirestoreErrorCode._(14);
  static const FirestoreErrorCode dataLoss = FirestoreErrorCode._(15);
  static const FirestoreErrorCode unauthenticated = FirestoreErrorCode._(16);

  static const List<FirestoreErrorCode> values = <FirestoreErrorCode>[
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

  static const List<String> _names = <String>[
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
  ];

  @override
  String toString() => _names[value];
}

class FirestoreError extends FirebaseError {
  FirestoreError(
    String message,
    this.code, [
    this.cause,
    StackTrace stackTrance,
  ]) : super(message, stackTrance) {
    Preconditions.checkNotNull(message);
    Preconditions.checkNotNull(code);
  }

  final FirestoreErrorCode code;
  final dynamic cause;

  @override
  String toString() => '$runtimeType:$code $message $cause $stackTrace';
}
