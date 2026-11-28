import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_transport_dart/src/http_rules.dart';
import 'package:firebase_transport_dart/src/json_guard.dart';
import 'package:firebase_transport_dart/src/tokens.dart';
import 'package:http/http.dart' as http;

/// The gRPC status codes, in order: `RpcStatus.values[n]` is code n.
enum RpcStatus {
  /// Code 0.
  ok('ok', 'OK'),

  /// Code 1.
  cancelled('cancelled', 'CANCELLED'),

  /// Code 2.
  unknown('unknown', 'UNKNOWN'),

  /// Code 3.
  invalidArgument('invalid-argument', 'INVALID_ARGUMENT'),

  /// Code 4.
  deadlineExceeded('deadline-exceeded', 'DEADLINE_EXCEEDED'),

  /// Code 5.
  notFound('not-found', 'NOT_FOUND'),

  /// Code 6.
  alreadyExists('already-exists', 'ALREADY_EXISTS'),

  /// Code 7.
  permissionDenied('permission-denied', 'PERMISSION_DENIED'),

  /// Code 8.
  resourceExhausted('resource-exhausted', 'RESOURCE_EXHAUSTED'),

  /// Code 9.
  failedPrecondition('failed-precondition', 'FAILED_PRECONDITION'),

  /// Code 10.
  aborted('aborted', 'ABORTED'),

  /// Code 11.
  outOfRange('out-of-range', 'OUT_OF_RANGE'),

  /// Code 12.
  unimplemented('unimplemented', 'UNIMPLEMENTED'),

  /// Code 13.
  internal('internal', 'INTERNAL'),

  /// Code 14.
  unavailable('unavailable', 'UNAVAILABLE'),

  /// Code 15.
  dataLoss('data-loss', 'DATA_LOSS'),

  /// Code 16.
  unauthenticated('unauthenticated', 'UNAUTHENTICATED');

  const RpcStatus(this.kebab, this._wireName);

  /// The `FirebaseException` code: `ok`, `invalid-argument`, `deadline-exceeded` and so on.
  final String kebab;

  /// The name on the wire: `OK`, `INVALID_ARGUMENT`, `DEADLINE_EXCEEDED` and so on.
  final String _wireName;

  /// The status of gRPC code [code]; a code outside 0 to 16 is [unknown].
  static RpcStatus fromCode(int code) {
    if (code < 0 || code >= values.length) {
      return unknown;
    }
    return values[code];
  }

  /// The status whose wire name is exactly [name] (`INVALID_ARGUMENT`); null for anything else,
  /// including a lowercase name, null and a number.
  static RpcStatus? fromWireName(Object? name) {
    if (name is! String) {
      return null;
    }
    for (final RpcStatus status in values) {
      if (status._wireName == name) {
        return status;
      }
    }
    return null;
  }

  /// The status of HTTP status [status], by the table of the Functions SDKs plus 416.
  ///
  /// 200 to 299 [ok]; 400 [invalidArgument]; 401 [unauthenticated]; 403 [permissionDenied]; 404
  /// [notFound]; 409 [aborted]; 416 [outOfRange]; 429 [resourceExhausted]; 499 [cancelled]; 500
  /// [internal]; 501 [unimplemented]; 503 [unavailable]; 504 [deadlineExceeded]; every other status
  /// [unknown]. This is not Firestore's table.
  static RpcStatus fromHttpStatus(int status) {
    if (status >= 200 && status < 300) {
      return ok;
    }
    return _byHttpStatus[status] ?? unknown;
  }

  static const Map<int, RpcStatus> _byHttpStatus = <int, RpcStatus>{
    400: invalidArgument,
    401: unauthenticated,
    403: permissionDenied,
    404: notFound,
    409: aborted,
    416: outOfRange,
    429: resourceExhausted,
    499: cancelled,
    500: internal,
    501: unimplemented,
    503: unavailable,
    504: deadlineExceeded,
  };
}

/// The error object of a Google API error body, read without trusting it.
final class RpcErrorBody {
  /// An error body with the fields that were valid.
  const RpcErrorBody({this.status, this.httpCode, this.message, this.details});

  /// From `error.status` when it is a known wire name.
  final RpcStatus? status;

  /// `error.code` when it is an integer from 100 to 599.
  final int? httpCode;

  /// `error.message` through [sanitizeServerText], or null when it is not a string.
  final String? message;

  /// `error.details` as decoded, untouched and untrusted; the product validates it.
  final Object? details;
}

/// Decodes [body] with `decodeGuardedBytes(body, maxDepth: maxDepth)`, then [rpcErrorBodyOf].
///
/// Null when the bytes are not strict UTF-8 JSON within [maxDepth], or hold no error object.
RpcErrorBody? parseRpcErrorBody(Uint8List body, {int maxDepth = maxJsonDepth}) {
  final Object? decoded;
  try {
    decoded = decodeGuardedBytes(body, maxDepth: maxDepth);
  } on FormatException {
    return null;
  }
  return rpcErrorBodyOf(decoded);
}

/// Reads `{"error": {...}}` or `[{"error": {...}}]` from an already decoded value.
///
/// Null when it holds no error object.
RpcErrorBody? rpcErrorBodyOf(Object? decoded) {
  final Map<Object?, Object?>? error = _errorObjectOf(decoded);
  if (error == null) {
    return null;
  }
  final Object? message = error['message'];
  return RpcErrorBody(
    status: RpcStatus.fromWireName(error['status']),
    httpCode: _httpCodeOf(error['code']),
    message: message is String ? sanitizeServerText(message) : null,
    details: error['details'],
  );
}

Map<Object?, Object?>? _errorObjectOf(Object? decoded) {
  Object? value = decoded;
  if (value is List && value.isNotEmpty) {
    value = value.first;
  }
  if (value is! Map) {
    return null;
  }
  final Object? error = value['error'];
  return error is Map ? error.cast<Object?, Object?>() : null;
}

/// [code] when it is a whole number from 100 to 599, read by value so that `404` and `404.0` give
/// the same result on the VM and on the web.
int? _httpCodeOf(Object? code) {
  if (code is! num || !code.isFinite || code != code.truncateToDouble()) {
    return null;
  }
  if (code < 100 || code > 599) {
    return null;
  }
  return code.toInt();
}

/// The status a product reports for [error], a failure of this package or of a send.
///
/// [TokenFetchException] by its failure: `authProviderFailed` is [RpcStatus.unauthenticated],
/// `authTimedOut` is [RpcStatus.unavailable], `authTokenTooLong` and `destinationRefused` are
/// [RpcStatus.failedPrecondition]. [TimeoutException] is [RpcStatus.deadlineExceeded].
/// [TransportException] by its failure: `cancelled` is [RpcStatus.cancelled]; `network` and
/// `redirected` are [RpcStatus.unavailable]. A raw `http.ClientException` is
/// [RpcStatus.unavailable]. [CapExceededException] is [RpcStatus.internal]. Anything else is
/// [RpcStatus.unknown].
RpcStatus rpcStatusOfFailure(Object error) {
  return switch (error) {
    TokenFetchException(:final TokenFailure failure) => _ofTokenFailure(
      failure,
    ),
    TimeoutException() => RpcStatus.deadlineExceeded,
    TransportException(:final TransportFailure failure) => _ofTransportFailure(
      failure,
    ),
    http.ClientException() => RpcStatus.unavailable,
    CapExceededException() => RpcStatus.internal,
    _ => RpcStatus.unknown,
  };
}

RpcStatus _ofTokenFailure(TokenFailure failure) {
  return switch (failure) {
    TokenFailure.authProviderFailed => RpcStatus.unauthenticated,
    TokenFailure.authTimedOut => RpcStatus.unavailable,
    TokenFailure.authTokenTooLong => RpcStatus.failedPrecondition,
    TokenFailure.destinationRefused => RpcStatus.failedPrecondition,
  };
}

RpcStatus _ofTransportFailure(TransportFailure failure) {
  return switch (failure) {
    TransportFailure.cancelled => RpcStatus.cancelled,
    TransportFailure.network => RpcStatus.unavailable,
    TransportFailure.redirected => RpcStatus.unavailable,
  };
}
