import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_data_connect_dart/src/transport/transport.dart';
import 'package:meta/meta.dart';

/// The exception a Data Connect call throws.
///
/// [code] is kebab case: a gRPC status (`not-found`, `permission-denied`, `unauthenticated`, ...),
/// or `partial-error` ([DataConnectOperationException]), `invalid-response` (the response could not
/// be read), `codec-failed` (the `decode` function threw), `cache-miss` (`cacheOnly`, which has no
/// cache to answer from) or `client-closed` (the instance was closed).
///
/// The message never contains a token, the API key, a URL with its query, variables or result data.
/// Text the server sent is only in [serverMessage].
class DataConnectException extends FirebaseException {
  /// An exception with [code]; [message] describes it for people.
  const DataConnectException(
    String code, {
    super.message,
    this.serverMessage,
    this.cause,
  }) : super(plugin: 'data_connect', code: code);

  /// The message the server sent with its error, with control characters removed and cut to 1 KiB;
  /// null when it sent none.
  final String? serverMessage;

  /// What the application's own `decode` function threw, for `codec-failed`; null otherwise. A
  /// transport or token failure never sets it.
  final Object? cause;
}

/// The server answered with GraphQL errors (code `partial-error`), for queries and mutations alike.
///
/// A mutation that reports errors may have written: [rawData] and [data] carry what the server
/// returned.
class DataConnectOperationException<Data> extends DataConnectException {
  /// An exception for [errors], with the data the server returned alongside them.
  DataConnectOperationException({
    required List<GraphqlError> errors,
    this.rawData,
    this.data,
  }) : errors = List<GraphqlError>.unmodifiable(errors),
       super(
         'partial-error',
         message: errors.length == 1
             ? 'The operation returned 1 GraphQL error.'
             : 'The operation returned ${errors.length} GraphQL errors.',
       );

  /// The GraphQL errors, never empty.
  final List<GraphqlError> errors;

  /// The `data` object of the response; null when the server sent none.
  final Map<String, Object?>? rawData;

  /// [rawData] as the reference's `decode` function read it; null when there was no data or
  /// `decode` threw.
  final Data? data;
}

/// One GraphQL error of a response.
@immutable
final class GraphqlError {
  /// An error with [message] at [path] and [locations], with [extensions].
  GraphqlError({
    required this.message,
    List<Object> path = const <Object>[],
    List<SourceLocation> locations = const <SourceLocation>[],
    Map<String, Object?> extensions = const <String, Object?>{},
  }) : path = List<Object>.unmodifiable(path),
       locations = List<SourceLocation>.unmodifiable(locations),
       extensions = Map<String, Object?>.unmodifiable(extensions);

  /// What went wrong, as the server wrote it.
  final String message;

  /// Where in the result the error belongs: `String` field names and `int` list indexes. Empty when
  /// the server sent none, or sent one that was not of that shape.
  final List<Object> path;

  /// Where in the operation's source the error belongs.
  final List<SourceLocation> locations;

  /// The error's extensions with their proto3-JSON names (`file`, `code`, `debugDetails`,
  /// `resource`, `warningLevel`, `workarounds`), without default values; for example `{'code':
  /// 'INVALID_ARGUMENT'}`.
  final Map<String, Object?> extensions;

  /// The kebab-case status of `extensions['code']` (`invalid-argument`, `not-found`, ...);
  /// `internal` when it is absent, `OK` or not a status name.
  String get code {
    final RpcStatus? status = RpcStatus.fromWireName(extensions['code']);
    if (status == null || status == RpcStatus.ok) {
      return RpcStatus.internal.kebab;
    }
    return status.kebab;
  }

  @override
  String toString() => 'GraphqlError($code)';
}

/// A line and column in the source of an operation.
@immutable
final class SourceLocation {
  /// The position [line], [column].
  const SourceLocation(this.line, this.column);

  /// The line, from 1.
  final int line;

  /// The column, from 1.
  final int column;

  @override
  bool operator ==(Object other) =>
      other is SourceLocation && other.line == line && other.column == column;

  @override
  int get hashCode => Object.hash(line, column);

  @override
  String toString() => 'SourceLocation($line, $column)';
}

/// The exception for [failure]: `invalid-response` when the response could not be read, else the
/// status's kebab code with the server's message in [DataConnectException.serverMessage].
@internal
DataConnectException exceptionOfFailure(WireFailure failure) {
  if (failure.invalidResponse) {
    return const DataConnectException(
      'invalid-response',
      message: 'The response could not be read.',
    );
  }
  final RpcStatus status = failure.status == RpcStatus.ok
      ? RpcStatus.unknown
      : failure.status;
  return DataConnectException(
    status.kebab,
    message: 'The call failed with status ${status.kebab}.',
    serverMessage: failure.serverMessage,
  );
}

/// The exception for [error]: the code of `rpcStatusOfFailure`, a null cause, and a message that
/// names the failure and, when the provider threw, the type of its error.
@internal
DataConnectException exceptionOfTokenFailure(TokenFetchException error) {
  final String? causeType = error.causeType;
  final String thrown = causeType == null
      ? ''
      : ' (the provider threw $causeType)';
  return DataConnectException(
    rpcStatusOfFailure(error).kebab,
    message:
        'The tokens of the call could not be fetched: ${error.failure.name}$thrown.',
  );
}

/// The exception of a call made during or after `close()`.
@internal
DataConnectException clientClosedException() => const DataConnectException(
  'client-closed',
  message: 'The DataConnect instance was closed.',
);
