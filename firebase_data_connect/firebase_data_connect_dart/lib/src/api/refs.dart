import 'package:firebase_data_connect_dart/src/api/data_connect.dart';
import 'package:firebase_data_connect_dart/src/errors.dart';
import 'package:firebase_data_connect_dart/src/transport/transport.dart';
import 'package:firebase_data_connect_dart/src/value/canonical_json.dart';
import 'package:firebase_data_connect_dart/src/value/json_values.dart';
import 'package:meta/meta.dart';

/// Where a query result should come from.
///
/// This version has no cache: [preferCache] and [serverOnly] both ask the server, and [cacheOnly]
/// throws a `DataConnectException` with the code `cache-miss` without a network call.
enum QueryFetchPolicy {
  /// The cache when it has a fresh result, else the server; with no cache, the server.
  preferCache,

  /// Only the cache; with no cache, always `cache-miss`.
  cacheOnly,

  /// Always the server.
  serverOnly,
}

/// Where a result came from.
enum DataSource {
  /// The local cache.
  cache,

  /// The server.
  server,
}

/// A query or mutation of a connector, with its variables and the function that reads its data.
///
/// Created by `DataConnect.query` and `DataConnect.mutation`.
sealed class OperationRef<Data, Variables> {
  OperationRef._(
    this.dataConnect,
    this.operationName, {
    required Data Function(Map<String, Object?> data) decode,
    this.variables,
    Map<String, Object?> Function(Variables variables)? encodeVariables,
  }) : _decode = decode,
       _encodeVariables = encodeVariables {
    if (operationName.isEmpty) {
      throw ArgumentError('must not be empty', 'operationName');
    }
    if (variables != null &&
        encodeVariables == null &&
        variables is! Map<String, Object?>) {
      throw ArgumentError(
        'needs encodeVariables when it is not a Map<String, Object?>',
        'variables',
      );
    }
  }

  /// The instance the operation runs on.
  final DataConnect dataConnect;

  /// The name of the operation in the connector.
  final String operationName;

  /// The variables; null when the operation takes none.
  final Variables? variables;

  final Data Function(Map<String, Object?> data) _decode;
  final Map<String, Object?> Function(Variables variables)? _encodeVariables;

  /// [operationName], `|`, and the JSON of the encoded variables with the keys of every map sorted
  /// (`null` when there are none). Equal ids on one instance are the same query for
  /// `QueryRef.subscribe`.
  ///
  /// Throws the [ArgumentError] of variables that break the value rules.
  String get operationId => operationIdOf(operationName, _checkedVariables());

  /// The encoded variables, checked by the value rules (a fresh map); null when there are none.
  Map<String, Object?>? _checkedVariables() {
    final Variables? value = variables;
    if (value == null) {
      return null;
    }
    final Map<String, Object?> Function(Variables variables)? encode =
        _encodeVariables;
    final Map<Object?, Object?> encoded = encode == null
        ? value as Map<String, Object?>
        : encode(value);
    return checkVariables(encoded);
  }

  /// Sends the operation and returns its data: a fresh map the caller owns.
  ///
  /// Throws a [DataConnectOperationException] when the response has GraphQL errors (with `decode`
  /// applied to its data, null when that throws), and `invalid-response` when it has neither errors
  /// nor data.
  Future<Map<String, Object?>> _fetch(
    OperationKind kind,
    Map<String, Object?>? variables,
  ) async {
    final WireResponse response = await dataConnect.send(
      kind,
      operationName,
      variables,
    );
    final Map<String, Object?>? data = response.data;
    if (response.errors.isNotEmpty) {
      throw DataConnectOperationException<Data>(
        errors: response.errors,
        rawData: data,
        data: data == null ? null : _decodeOrNull(data),
      );
    }
    if (data == null) {
      throw const DataConnectException(
        'invalid-response',
        message: 'The response has neither data nor errors.',
      );
    }
    return data;
  }

  Data? _decodeOrNull(Map<String, Object?> data) {
    try {
      return _decode(copyJsonObject(data));
    } on Object {
      // The response's own errors are what the caller is told about; a decode that also fails on
      // the partial data leaves `data` null, as the exception's documentation says.
      return null;
    }
  }

  /// [data] read by `decode`, which receives its own copy. Throws `codec-failed`, with what
  /// `decode` threw as the cause, when it throws.
  Data _decodeData(Map<String, Object?> data) {
    try {
      return _decode(copyJsonObject(data));
    } on Object catch (error) {
      throw DataConnectException(
        'codec-failed',
        message: 'The decode function of the operation $operationName threw.',
        cause: error,
      );
    }
  }
}

/// A query of a connector.
final class QueryRef<Data, Variables> extends OperationRef<Data, Variables> {
  /// Created by `DataConnect.query`; throws an [ArgumentError] for an empty [operationName], or for
  /// [variables] that are not a `Map<String, Object?>` when [encodeVariables] is null.
  @internal
  QueryRef.internal(
    super.dataConnect,
    super.operationName, {
    required super.decode,
    super.variables,
    super.encodeVariables,
  }) : super._();

  /// Runs the query on the server and returns its result.
  ///
  /// [fetchPolicy] [QueryFetchPolicy.cacheOnly] throws `cache-miss`; the other policies ask the
  /// server (this version has no cache). A successful result also reaches the streams of
  /// [subscribe] for this [operationId].
  Future<QueryResult<Data, Variables>> execute({
    QueryFetchPolicy fetchPolicy = QueryFetchPolicy.preferCache,
  }) async {
    if (fetchPolicy == QueryFetchPolicy.cacheOnly) {
      throw const DataConnectException(
        'cache-miss',
        message: 'This version has no cache, so cacheOnly never has a result.',
      );
    }
    return resultOf(await fetchForSubscription());
  }

  /// A stream of this query's results: on the first listener of this [operationId] on the instance,
  /// the query runs once; after that every successful [execute] of a reference with the same id
  /// reaches it, read by this reference's `decode`. See `DataConnect` for the full rules.
  Stream<QueryResult<Data, Variables>> subscribe() =>
      dataConnect.subscriptions.subscribe(this);

  /// Runs the query on the server, hands its data to the subscription streams of its id, and
  /// returns it (a fresh map) without decoding it.
  @internal
  Future<Map<String, Object?>> fetchForSubscription() async {
    final Map<String, Object?>? variables = _checkedVariables();
    final Map<String, Object?> data = await _fetch(
      OperationKind.query,
      variables,
    );
    dataConnect.subscriptions.publish(
      operationIdOf(operationName, variables),
      data,
    );
    return data;
  }

  /// The result of [data], a fresh map, read by `decode`; throws `codec-failed` when it throws.
  @internal
  QueryResult<Data, Variables> resultOf(Map<String, Object?> data) =>
      QueryResult<Data, Variables>(
        data: _decodeData(data),
        source: DataSource.server,
        ref: this,
      );
}

/// A mutation of a connector.
final class MutationRef<Data, Variables> extends OperationRef<Data, Variables> {
  /// Created by `DataConnect.mutation`; throws an [ArgumentError] for an empty [operationName], or
  /// for [variables] that are not a `Map<String, Object?>` when [encodeVariables] is null.
  @internal
  MutationRef.internal(
    super.dataConnect,
    super.operationName, {
    required super.decode,
    super.variables,
    super.encodeVariables,
  }) : super._();

  /// Runs the mutation and returns its result.
  ///
  /// A mutation that ends with GraphQL errors may still have written: the
  /// [DataConnectOperationException] carries what the server returned.
  Future<MutationResult<Data, Variables>> execute() async {
    final Map<String, Object?> data = await _fetch(
      OperationKind.mutation,
      _checkedVariables(),
    );
    return MutationResult<Data, Variables>(data: _decodeData(data), ref: this);
  }
}

/// The result of a query.
@immutable
final class QueryResult<Data, Variables> {
  /// A result with [data] from [source] for [ref].
  const QueryResult({
    required this.data,
    required this.source,
    required this.ref,
  });

  /// The data, as the reference's `decode` read it.
  final Data data;

  /// Where the data came from; always [DataSource.server] in this version.
  final DataSource source;

  /// The query that produced it.
  final QueryRef<Data, Variables> ref;
}

/// The result of a mutation.
@immutable
final class MutationResult<Data, Variables> {
  /// A result with [data] for [ref].
  const MutationResult({required this.data, required this.ref});

  /// The data, as the reference's `decode` read it.
  final Data data;

  /// The mutation that produced it.
  final MutationRef<Data, Variables> ref;
}
