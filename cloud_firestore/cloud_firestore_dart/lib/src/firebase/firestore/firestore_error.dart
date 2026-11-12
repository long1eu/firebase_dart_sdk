// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

/// The status code of a [FirestoreError]. The codes and their numeric [value]s are the canonical
/// gRPC status codes.
class FirestoreErrorCode {
  const FirestoreErrorCode._(this.value);

  /// The numeric gRPC status code.
  final int value;

  /// The operation completed successfully. Never the code of a thrown [FirestoreError].
  static const FirestoreErrorCode ok = FirestoreErrorCode._(0);

  /// The operation was cancelled, typically by the caller.
  static const FirestoreErrorCode cancelled = FirestoreErrorCode._(1);

  /// An unknown error, or an error from a different error domain.
  static const FirestoreErrorCode unknown = FirestoreErrorCode._(2);

  /// The client passed an invalid argument. Unlike [failedPrecondition], the argument is wrong
  /// regardless of the state of the system (for example a malformed field name).
  static const FirestoreErrorCode invalidArgument = FirestoreErrorCode._(3);

  /// The deadline expired before the operation could complete. The operation may still have
  /// succeeded on the server.
  static const FirestoreErrorCode deadlineExceeded = FirestoreErrorCode._(4);

  /// A requested document was not found.
  static const FirestoreErrorCode notFound = FirestoreErrorCode._(5);

  /// The document the operation tried to create already exists.
  static const FirestoreErrorCode alreadyExists = FirestoreErrorCode._(6);

  /// The caller does not have permission to run the operation, for example because the security
  /// rules reject it.
  static const FirestoreErrorCode permissionDenied = FirestoreErrorCode._(7);

  /// A resource has been exhausted, such as a per-user quota or the storage of the project.
  static const FirestoreErrorCode resourceExhausted = FirestoreErrorCode._(8);

  /// The operation was rejected because the system is not in the state it requires, for example a
  /// query that needs an index that does not exist.
  static const FirestoreErrorCode failedPrecondition = FirestoreErrorCode._(9);

  /// The operation was aborted, typically because of a concurrency problem such as a transaction
  /// conflict.
  static const FirestoreErrorCode aborted = FirestoreErrorCode._(10);

  /// The operation was attempted past the valid range.
  static const FirestoreErrorCode outOfRange = FirestoreErrorCode._(11);

  /// The operation is not implemented or not supported.
  static const FirestoreErrorCode unimplemented = FirestoreErrorCode._(12);

  /// An internal error: an invariant expected by the underlying system was broken.
  static const FirestoreErrorCode internal = FirestoreErrorCode._(13);

  /// The service is currently unavailable. This is most likely transient and the operation can be
  /// retried with a backoff.
  static const FirestoreErrorCode unavailable = FirestoreErrorCode._(14);

  /// Unrecoverable data loss or corruption.
  static const FirestoreErrorCode dataLoss = FirestoreErrorCode._(15);

  /// The request does not carry valid authentication credentials for the operation.
  static const FirestoreErrorCode unauthenticated = FirestoreErrorCode._(16);

  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  static FirestoreErrorCode fromValue(GrpcError error) {
    // Unknown (e.g. forward-compatible or custom) codes map to `unknown`.
    return error.code >= 0 && error.code < values.length
        ? values[error.code]
        : unknown;
  }

  /// All codes, indexed by their numeric [value].
  static const List<FirestoreErrorCode> values = <FirestoreErrorCode>[
    ok,
    cancelled,
    unknown,
    invalidArgument,
    deadlineExceeded,
    notFound,
    alreadyExists,
    permissionDenied,
    resourceExhausted,
    failedPrecondition,
    aborted,
    outOfRange,
    unimplemented,
    internal,
    unavailable,
    dataLoss,
    unauthenticated,
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

/// The error thrown by Firestore operations. [code] says what went wrong.
class FirestoreError extends FirebaseError {
  /// Creates an error with a [message] and a [code], optionally keeping the [cause] and a stack
  /// trace.
  FirestoreError(
    String message,
    this.code, [
    this.cause,
    StackTrace? stackTrance,
  ]) : super(message, stackTrance);

  /// The status code of this error.
  final FirestoreErrorCode code;

  /// The lower-level error that caused this one, if any.
  final Object? cause;

  @override
  String toString() => '$runtimeType:$code $message $cause $stackTrace';
}
