// Ported from FlutterFire firebase_data_connect 0.4.2 (commit 6a80b1b),
// lib/src/common/dataconnect_error.dart. Apache License 2.0; see NOTICE. Changed: the errors
// extend firebase_app_dart's FirebaseException and keep the core DataConnectException as cause.

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_data_connect_dart/src/errors.dart' as core;
import 'package:meta/meta.dart';

/// The kinds of Data Connect errors.
enum DataConnectErrorCode {
  /// The service could not be reached, or did not answer in time.
  unavailable,

  /// The call was refused as unauthenticated.
  unauthorized,

  /// `QueryFetchPolicy.cacheOnly` found no cached result.
  cacheMiss,

  /// The response could not be read or decoded.
  codecFailed,

  /// Any other error.
  other,
}

/// An error of a Data Connect operation.
///
/// [code] is `dataConnectErrorCode.toString()`, as in FlutterFire. It extends the
/// `FirebaseException` of `firebase_app_dart`, not the one of `firebase_core`.
class DataConnectError extends FirebaseException {
  /// An error of kind [dataConnectErrorCode] with [message]; [cause] is the core exception.
  DataConnectError(this.dataConnectErrorCode, String? message, {this.cause})
    : super(
        plugin: 'Data Connect',
        code: dataConnectErrorCode.toString(),
        message: message,
      );

  /// The kind of error.
  final DataConnectErrorCode dataConnectErrorCode;

  /// The core `DataConnectException` this error was made from, if any.
  final Object? cause;
}

/// An operation that returned GraphQL errors, possibly with data.
class DataConnectOperationError<T> extends DataConnectError {
  /// An error of kind [code] with [message] and the server's [response].
  DataConnectOperationError(
    super.code,
    super.message,
    this.response, {
    super.cause,
  });

  /// The errors, the raw data and the decoded data.
  final DataConnectOperationFailureResponse<T> response;
}

/// The errors and data of a partly failed operation.
class DataConnectOperationFailureResponse<T> {
  /// The [errors], the [rawData] as the server returned it, and the decoded [data].
  DataConnectOperationFailureResponse(this.errors, this.rawData, this.data);

  /// The data as the server returned it.
  final Map<String, dynamic>? rawData;

  /// One entry per GraphQL error.
  final List<DataConnectOperationFailureResponseErrorInfo> errors;

  /// The decoded data, or null when there was none or it could not be decoded.
  final T? data;
}

/// One GraphQL error.
class DataConnectOperationFailureResponseErrorInfo {
  /// The error at [path] with [message].
  DataConnectOperationFailureResponseErrorInfo(this.path, this.message);

  /// The server's message.
  String message;

  /// Where in the data the error occurred.
  List<DataConnectPathSegment> path;
}

/// A segment of the path of a GraphQL error.
@immutable
sealed class DataConnectPathSegment {}

/// A field name in the path of a GraphQL error.
class DataConnectFieldPathSegment extends DataConnectPathSegment {
  /// The segment for [field].
  DataConnectFieldPathSegment(this.field);

  /// The field name.
  final String field;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataConnectFieldPathSegment &&
          runtimeType == other.runtimeType &&
          field == other.field;

  @override
  int get hashCode => field.hashCode;

  /// The field name.
  @override
  String toString() => field;
}

/// A list index in the path of a GraphQL error.
class DataConnectListIndexPathSegment extends DataConnectPathSegment {
  /// The segment for [index].
  DataConnectListIndexPathSegment(this.index);

  /// The list index.
  final int index;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataConnectListIndexPathSegment &&
          runtimeType == other.runtimeType &&
          index == other.index;

  @override
  int get hashCode => index.hashCode;

  /// The index.
  @override
  String toString() => index.toString();
}

/// Turns variables into JSON text.
typedef Serializer<Variables> = String Function(Variables vars);

/// Turns a value into JSON.
typedef DynamicSerializer<Variables> = dynamic Function(Variables vars);

/// Turns JSON text into data.
typedef Deserializer<Data> = Data Function(String data);

/// Turns JSON into a value.
typedef DynamicDeserializer<Data> = Data Function(dynamic data);

/// The compat error of the core exception [error] (5.13.2 note 5).
///
/// `unauthenticated` is [DataConnectErrorCode.unauthorized]; `unavailable` and
/// `deadline-exceeded` are [DataConnectErrorCode.unavailable]; `codec-failed` and
/// `invalid-response` are [DataConnectErrorCode.codecFailed]; `cache-miss` is
/// [DataConnectErrorCode.cacheMiss]; `partial-error` is a [DataConnectOperationError] of kind
/// [DataConnectErrorCode.other] with the errors, the raw data and the decoded data; every other
/// code is [DataConnectErrorCode.other].
DataConnectError compatErrorOf<Data>(core.DataConnectException error) {
  if (error is core.DataConnectOperationException) {
    final Object? data = error.data;
    return DataConnectOperationError<Data>(
      DataConnectErrorCode.other,
      error.message,
      DataConnectOperationFailureResponse<Data>(
        <DataConnectOperationFailureResponseErrorInfo>[
          for (final core.GraphqlError graphqlError in error.errors)
            DataConnectOperationFailureResponseErrorInfo(
              _pathOf(graphqlError.path),
              graphqlError.message,
            ),
        ],
        error.rawData,
        data is Data ? data : null,
      ),
      cause: error,
    );
  }
  return DataConnectError(_codeOf(error.code), error.message, cause: error);
}

DataConnectErrorCode _codeOf(String code) {
  switch (code) {
    case 'unauthenticated':
      return DataConnectErrorCode.unauthorized;
    case 'unavailable':
    case 'deadline-exceeded':
      return DataConnectErrorCode.unavailable;
    case 'codec-failed':
    case 'invalid-response':
      return DataConnectErrorCode.codecFailed;
    case 'cache-miss':
      return DataConnectErrorCode.cacheMiss;
    default:
      return DataConnectErrorCode.other;
  }
}

List<DataConnectPathSegment> _pathOf(List<Object> path) {
  return <DataConnectPathSegment>[
    for (final Object segment in path)
      if (segment is int)
        DataConnectListIndexPathSegment(segment)
      else
        DataConnectFieldPathSegment(segment.toString()),
  ];
}
