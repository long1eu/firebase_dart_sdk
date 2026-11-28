/// Reading a callable response body: the unary rules (§5.7) and the error envelope (§5.7 rule 3),
/// over one guarded decode per body (§5.6 rule 1).
library;

import 'dart:typed_data';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:cloud_functions_dart/src/exception.dart';
import 'package:cloud_functions_dart/src/serializer.dart';

/// The message of a body that is not JSON (§5.6 rule 2).
const String notJsonMessage =
    'Response is not valid JSON. A non-finite number such as NaN, which a Python function can '
    'send, is one cause.';

/// The message of a body nested deeper than [maxValueDepth] (§5.6 rule 5).
const String tooDeepMessage =
    'Response is nested more than $maxValueDepth levels deep.';

/// What one decode of a body gave.
sealed class DecodedBody {
  const DecodedBody();

  /// Decodes [bytes] once: the depth scan first, then strict UTF-8 JSON. A [truncated] body is
  /// never JSON.
  factory DecodedBody.of(Uint8List bytes, {bool truncated = false}) {
    if (truncated) {
      return const NotJson();
    }
    if (exceedsJsonDepth(bytes, maxDepth: maxValueDepth)) {
      return const TooDeep();
    }
    try {
      return Json(decodeGuardedBytes(bytes, maxDepth: maxValueDepth));
    } on FormatException {
      return const NotJson();
    }
  }
}

/// The body is not strict UTF-8 JSON, or was cut at its cap.
final class NotJson extends DecodedBody {
  /// Not JSON.
  const NotJson();
}

/// The body nests deeper than [maxValueDepth].
final class TooDeep extends DecodedBody {
  /// Too deep.
  const TooDeep();
}

/// The body is JSON.
final class Json extends DecodedBody {
  /// JSON [value].
  const Json(this.value);

  /// The decoded value.
  final Object? value;
}

/// The value of a unary response with [statusCode] and [body], before it becomes a
/// `HttpsCallableResult` (§5.7). [truncated] is true when a non-2xx body was cut at its cap.
///
/// Throws a [FirebaseFunctionsException] for an error the function threw, a response that is not
/// a callable response, or a value the decoder refuses.
Object? valueOfResponse(
  int statusCode,
  Uint8List body, {
  bool truncated = false,
}) {
  final DecodedBody decoded = DecodedBody.of(body, truncated: truncated);
  final bool success = statusCode >= 200 && statusCode < 300;
  return success
      ? _successValue(statusCode, decoded)
      : _failureValue(statusCode, decoded);
}

/// True when a response with [statusCode] and [body] is a 401 of the transport itself: no callable
/// error envelope (§5.4 rule 6).
bool isBareUnauthorized(
  int statusCode,
  Uint8List body, {
  bool truncated = false,
}) {
  if (statusCode != 401) {
    return false;
  }
  final DecodedBody decoded = DecodedBody.of(body, truncated: truncated);
  return decoded is! Json || rpcErrorBodyOf(decoded.value) == null;
}

/// §5.7 rule 1.
Object? _successValue(int statusCode, DecodedBody decoded) {
  final Map<Object?, Object?> object = switch (decoded) {
    NotJson() => throw internalError(notJsonMessage, httpStatus: statusCode),
    TooDeep() => throw internalError(tooDeepMessage, httpStatus: statusCode),
    Json(value: final Map<Object?, Object?> map) => map,
    Json() => throw internalError(
      'Response is not a JSON object.',
      httpStatus: statusCode,
    ),
  };
  final Object? error = object['error'];
  if (error is Map<Object?, Object?>) {
    final Object? status = error['status'];
    if (status is String && status != 'OK') {
      throw envelopeError(object, statusCode);
    }
  }
  return resultOf(object, statusCode);
}

/// §5.7 rule 2. The list form `[{"error": {...}}]` counts as an envelope, as `rpcErrorBodyOf`
/// reads it.
Object? _failureValue(int statusCode, DecodedBody decoded) {
  if (decoded is TooDeep) {
    throw internalError(tooDeepMessage, httpStatus: statusCode);
  }
  if (decoded is Json && rpcErrorBodyOf(decoded.value) != null) {
    final Map<Object?, Object?> holder = _holderOf(decoded.value);
    final Object? status =
        (holder['error']! as Map<Object?, Object?>)['status'];
    if (status == 'OK') {
      return resultOf(holder, statusCode);
    }
    throw envelopeError(holder, statusCode);
  }
  final RpcStatus status = RpcStatus.fromHttpStatus(statusCode);
  throw FirebaseFunctionsException(
    code: status.kebab,
    message:
        'The server answered HTTP $statusCode without a callable error body.',
    httpStatus: statusCode,
  );
}

/// The map that holds `error`: the value itself, or the first element of the list form.
Map<Object?, Object?> _holderOf(Object? value) {
  final Object? holder = value is List<Object?> ? value.first : value;
  return holder! as Map<Object?, Object?>;
}

/// The value of [object] (§5.7 rule 1c): `data` when the key is present, else `result`.
///
/// Throws `internal` when neither key is present or the value is refused by [decodeValue].
Object? resultOf(Map<Object?, Object?> object, int statusCode) {
  final String key;
  if (object.containsKey('data')) {
    key = 'data';
  } else if (object.containsKey('result')) {
    key = 'result';
  } else {
    throw internalError(
      'Response is missing data field.',
      httpStatus: statusCode,
    );
  }
  return decodeOrThrow(object[key], statusCode);
}

/// [decodeValue] of [value], with [InvalidValueException] as an `internal` exception.
Object? decodeOrThrow(Object? value, int statusCode) {
  try {
    return decodeValue(value);
  } on InvalidValueException {
    throw internalError(invalidValueMessage, httpStatus: statusCode);
  }
}

/// The exception of the error envelope in [holder] (§5.7 rule 3), whose `error` is a map with a
/// status other than `OK`.
///
/// The body decides the code, never [statusCode]: an exact known status name gives its code; an
/// unknown string gives `internal`, "Unknown backend error status."; an absent or non-string status
/// takes the code of [statusCode] (or `internal` when [inStream], §5.10 rule 4d). The server's
/// message (sanitized) and details are kept for every code.
FirebaseFunctionsException envelopeError(
  Map<Object?, Object?> holder,
  int statusCode, {
  bool inStream = false,
}) {
  final Object? error = holder['error'];
  final Map<Object?, Object?> fields = error is Map<Object?, Object?>
      ? error
      : const <Object?, Object?>{};
  final Object? rawStatus = fields['status'];
  final RpcStatus status;
  if (rawStatus is String) {
    final RpcStatus? known = RpcStatus.fromWireName(rawStatus);
    if (known == null) {
      return internalError(
        'Unknown backend error status.',
        httpStatus: statusCode,
      );
    }
    status = known;
  } else {
    status = inStream
        ? RpcStatus.internal
        : RpcStatus.fromHttpStatus(statusCode);
  }
  final Object? details = fields.containsKey('details')
      ? decodeOrThrow(fields['details'], statusCode)
      : null;
  final String fallback = rawStatus is String ? rawStatus : status.kebab;
  return FirebaseFunctionsException(
    code: status.kebab,
    message:
        rpcErrorBodyOf(holder)?.message ?? 'Backend error status: $fallback.',
    details: details,
    httpStatus: statusCode,
  );
}
