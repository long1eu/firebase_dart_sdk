/// Reading the REST transport's response bodies (spec 5.5 rules 5 and 6, 5.9 extensions rule).
///
/// Plain Dart: the unit tests run it on the VM against the same table as the gRPC decoder.
library;

import 'dart:typed_data';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_data_connect_dart/src/errors.dart';
import 'package:firebase_data_connect_dart/src/transport/transport.dart';
import 'package:firebase_data_connect_dart/src/value/json_values.dart';

/// The JSON depth a success body may have: data depth 100 plus the envelope.
const int _successDepth = maxDataDepth + 1;

/// The JSON depth read from an error body.
const int _errorDepth = maxJsonDepth;

/// The six known keys of `GraphqlErrorExtensions` whose default values are removed.
const Set<String> _extensionKeys = <String>{
  'file',
  'code',
  'debugDetails',
  'resource',
  'warningLevel',
  'workarounds',
};

const WireFailure _invalid = WireFailure(
  RpcStatus.internal,
  invalidResponse: true,
);

/// The result of a 2xx [body]: a [WireResponse], or an invalid-response [WireFailure] when the body
/// is not strict JSON within the depth limit, is not an object, has a `data` that is not an object
/// or null, an `errors` that is not a list or null, or an error without a string `message`.
WireResult decodeSuccessBody(Uint8List body) {
  try {
    final Object? decoded = decodeGuardedBytes(body, maxDepth: _successDepth);
    if (decoded is! Map<String, Object?>) {
      return _invalid;
    }
    return WireResponse(
      data: _dataOf(decoded['data']),
      errors: _errorsOf(decoded['errors']),
    );
  } on FormatException {
    return _invalid;
  }
}

Map<String, Object?>? _dataOf(Object? data) {
  return switch (data) {
    null => null,
    Map<String, Object?>() => normalizedResult(data),
    _ => throw const FormatException('data is not an object'),
  };
}

List<GraphqlError> _errorsOf(Object? errors) {
  return switch (errors) {
    null => const <GraphqlError>[],
    List<Object?>() => <GraphqlError>[
      for (final Object? error in errors) _errorOf(error),
    ],
    _ => throw const FormatException('errors is not a list'),
  };
}

GraphqlError _errorOf(Object? error) {
  if (error is! Map<String, Object?>) {
    throw const FormatException('an error is not an object');
  }
  final Object? message = error['message'];
  if (message is! String) {
    throw const FormatException('an error has no message');
  }
  return GraphqlError(
    message: message,
    path: errorPathOf(error['path']),
    locations: _locationsOf(error['locations']),
    extensions: restExtensions(error['extensions']),
  );
}

/// The source locations of [raw]: `[]` unless it is a list of objects, each with an integer `line`
/// and `column`.
List<SourceLocation> _locationsOf(Object? raw) {
  if (raw is! List<Object?>) {
    return const <SourceLocation>[];
  }
  final List<SourceLocation> locations = <SourceLocation>[];
  for (final Object? entry in raw) {
    if (entry is! Map<String, Object?>) {
      return const <SourceLocation>[];
    }
    final Object? line = entry['line'];
    final Object? column = entry['column'];
    if (line is! int || column is! int) {
      return const <SourceLocation>[];
    }
    locations.add(SourceLocation(line, column));
  }
  return locations;
}

/// The extensions of an error from the decoded [raw]: every key kept with its value, except that
/// the six known keys are dropped when they hold a default value (`""`, `[]`, `null`, `0`, `false`,
/// `WARNING_LEVEL_UNKNOWN`, `OK`). Anything but an object gives `{}`.
Map<String, Object?> restExtensions(Object? raw) {
  if (raw is! Map<String, Object?>) {
    return const <String, Object?>{};
  }
  final Map<String, Object?> extensions = <String, Object?>{};
  for (final MapEntry<String, Object?> entry in raw.entries) {
    if (_extensionKeys.contains(entry.key) && _isDefault(entry.value)) {
      continue;
    }
    extensions[entry.key] = copyJson(entry.value);
  }
  return extensions;
}

bool _isDefault(Object? value) {
  return switch (value) {
    null || '' || 0 || false || 'WARNING_LEVEL_UNKNOWN' || 'OK' => true,
    List<Object?>() => value.isEmpty,
    _ => false,
  };
}

/// The failure of a non-2xx answer with [statusCode] and [body], in this order: a Google error body
/// with a known `error.status`; a grpc-gateway body (an object with an integer `code` from 1 to 16
/// and no `error` key); else the HTTP status. The server's message is `error.message`, else
/// `message`, through `sanitizeServerText`.
WireFailure decodeErrorBody(int statusCode, Uint8List body) {
  final RpcErrorBody? errorBody = parseRpcErrorBody(
    body,
    maxDepth: _errorDepth,
  );
  final RpcStatus? status = errorBody?.status;
  if (status != null) {
    return WireFailure(status, serverMessage: errorBody?.message);
  }
  final Map<String, Object?>? gateway = _objectOf(body);
  final Object? code = gateway?['code'];
  final Object? message = gateway?['message'];
  final String? serverMessage =
      errorBody?.message ??
      (message is String ? sanitizeServerText(message) : null);
  if (gateway != null &&
      !gateway.containsKey('error') &&
      code is int &&
      code >= 1 &&
      code <= 16) {
    return WireFailure(RpcStatus.fromCode(code), serverMessage: serverMessage);
  }
  return WireFailure(
    RpcStatus.fromHttpStatus(statusCode),
    serverMessage: serverMessage,
  );
}

Map<String, Object?>? _objectOf(Uint8List body) {
  try {
    final Object? decoded = decodeGuardedBytes(body, maxDepth: _errorDepth);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}
