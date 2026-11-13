// Maps the errors of the REST and WebChannel endpoints to gRPC statuses.
// Ported from the JS SDK (packages/firestore/src/remote/rpc_error.ts).

import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';

const Map<String, int> _codeByStatusName = <String, int>{
  'OK': StatusCode.ok,
  'CANCELLED': StatusCode.cancelled,
  'UNKNOWN': StatusCode.unknown,
  'INVALID_ARGUMENT': StatusCode.invalidArgument,
  'DEADLINE_EXCEEDED': StatusCode.deadlineExceeded,
  'NOT_FOUND': StatusCode.notFound,
  'ALREADY_EXISTS': StatusCode.alreadyExists,
  'PERMISSION_DENIED': StatusCode.permissionDenied,
  'RESOURCE_EXHAUSTED': StatusCode.resourceExhausted,
  'FAILED_PRECONDITION': StatusCode.failedPrecondition,
  'ABORTED': StatusCode.aborted,
  'OUT_OF_RANGE': StatusCode.outOfRange,
  'UNIMPLEMENTED': StatusCode.unimplemented,
  'INTERNAL': StatusCode.internal,
  'UNAVAILABLE': StatusCode.unavailable,
  'DATA_LOSS': StatusCode.dataLoss,
  'UNAUTHENTICATED': StatusCode.unauthenticated,
};

/// The gRPC status code for a `google.rpc.Code` name such as `NOT_FOUND`, or
/// null if the name is unknown.
int? codeFromRpcStatusName(String? status) => _codeByStatusName[status];

/// The gRPC status code that corresponds to an HTTP status (the mapping of
/// `google.rpc.Code` to HTTP, reversed).
int codeFromHttpStatus(int status) {
  switch (status) {
    case 200:
      return StatusCode.ok;
    case 400:
      // As the JS SDK: FAILED_PRECONDITION, which a transaction retries. Could
      // also be INVALID_ARGUMENT or OUT_OF_RANGE. Only used when the body has
      // no status name.
      return StatusCode.failedPrecondition;
    case 401:
      return StatusCode.unauthenticated;
    case 403:
      return StatusCode.permissionDenied;
    case 404:
      return StatusCode.notFound;
    case 409:
      // Could also be ALREADY_EXISTS.
      return StatusCode.aborted;
    case 416:
      return StatusCode.outOfRange;
    case 429:
      return StatusCode.resourceExhausted;
    case 499:
      return StatusCode.cancelled;
    case 500:
      // Could also be INTERNAL or DATA_LOSS.
      return StatusCode.unknown;
    case 501:
      return StatusCode.unimplemented;
    case 503:
      return StatusCode.unavailable;
    case 504:
      return StatusCode.deadlineExceeded;
    default:
      if (status >= 200 && status < 300) {
        return StatusCode.ok;
      }
      if (status >= 400 && status < 500) {
        return StatusCode.failedPrecondition;
      }
      if (status >= 500 && status < 600) {
        return StatusCode.internal;
      }
      return StatusCode.unknown;
  }
}

/// Builds the [GrpcError] for an error object of the backend
/// (`{"code": 403, "status": "PERMISSION_DENIED", "message": "..."}`).
///
/// The status name wins; without one the numeric code is used, which is an
/// HTTP status ([httpCode] true, the REST and stream error envelopes) or
/// already a gRPC code.
GrpcError grpcErrorFromJson(
  Map<String, Object?> error, {
  bool httpCode = true,
}) {
  final Object? message = error['message'];
  final Object? status = error['status'];
  final Object? code = error['code'];
  int? grpcCode = status is String ? codeFromRpcStatusName(status) : null;
  if (grpcCode == null && code is int) {
    grpcCode = httpCode ? codeFromHttpStatus(code) : code;
  }
  if (grpcCode == null) {
    return GrpcError.internal(
      'Unknown error status: $status with message $message',
    );
  }
  return GrpcError.custom(grpcCode, message is String ? message : null);
}

/// Finds the error object in a decoded error body or stream message: either
/// `{"error": {...}}` or the same wrapped in a list.
Map<String, Object?>? findErrorJson(Object? json) {
  Object? value = json;
  if (value is List && value.isNotEmpty) {
    value = value.first;
  }
  if (value is Map) {
    final Object? error = value['error'];
    if (error is Map) {
      return error.cast<String, Object?>();
    }
  }
  return null;
}
