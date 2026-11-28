// The reference and result types of FlutterFire firebase_data_connect 0.4.2 (commit 6a80b1b),
// lib/src/core/ref.dart, over the core references of this package. Apache License 2.0; see
// NOTICE.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_data_connect_dart/src/api/refs.dart' as core;
import 'package:firebase_data_connect_dart/src/compat/cache_types.dart';
import 'package:firebase_data_connect_dart/src/compat/errors.dart';
import 'package:firebase_data_connect_dart/src/compat/firebase_data_connect.dart';
import 'package:firebase_data_connect_dart/src/errors.dart' as core;

/// Where a result came from.
enum DataSource {
  /// The cache (never in 0.1.0).
  cache,

  /// The server.
  server,
}

/// The result of a query or mutation.
class OperationResult<Data, Variables> {
  /// The [data] of [ref] on [dataConnect], from [source].
  OperationResult(this.dataConnect, this.data, this.source, this.ref);

  /// The decoded data.
  Data data;

  /// Where the data came from.
  DataSource source;

  /// The reference that was executed.
  OperationRef<Data, Variables> ref;

  /// The client that executed it.
  FirebaseDataConnect dataConnect;
}

/// The result of a query.
class QueryResult<Data, Variables> extends OperationResult<Data, Variables> {
  /// The [data] of [ref] on [dataConnect], from [source].
  QueryResult(super.dataConnect, super.data, super.source, super.ref);
}

/// A reference to one operation with its variables. Each execution builds a core reference on the
/// client's current core client.
abstract class OperationRef<Data, Variables> {
  /// The operation [operationName] on [dataConnect], with [variables] that [serializer] writes and
  /// data that [deserializer] reads.
  OperationRef(
    this.dataConnect,
    this.operationName,
    this.deserializer,
    this.serializer,
    this.variables,
  );

  /// The client.
  final FirebaseDataConnect dataConnect;

  /// The name of the operation.
  final String operationName;

  /// Reads the data from JSON text.
  final Deserializer<Data> deserializer;

  /// Writes the variables as JSON text.
  final Serializer<Variables> serializer;

  /// The variables, or null for none.
  final Variables? variables;

  /// The operation name and the canonical JSON of the variables: equal ids are the same query for
  /// `subscribe()`.
  late final String operationId = _coreRef().operationId;

  /// Executes the operation.
  ///
  /// Throws a [DataConnectError] for a failure of the call.
  Future<OperationResult<Data, Variables>> execute();

  core.OperationRef<Data, Map<String, Object?>> _coreRef();

  Data _decode(Map<String, Object?> data) => deserializer(jsonEncode(data));

  /// The variables as a JSON object: `jsonDecode(serializer(variables))`, or null for none.
  ///
  /// Throws an [ArgumentError] when the serializer does not write a JSON object.
  Map<String, Object?>? _encodedVariables() {
    final Variables? current = variables;
    if (current == null) {
      return null;
    }
    final Object? decoded = jsonDecode(serializer(current));
    if (decoded is! Map<String, Object?>) {
      throw ArgumentError('the serialized variables are not a JSON object');
    }
    return decoded;
  }
}

Map<String, Object?> _identity(Map<String, Object?> variables) => variables;

/// A reference to a query.
class QueryRef<Data, Variables> extends OperationRef<Data, Variables> {
  /// The query [operationName] on [dataConnect], with [variables] that [serializer] writes and data
  /// that [deserializer] reads.
  QueryRef(
    super.dataConnect,
    super.operationName,
    super.deserializer,
    super.serializer,
    super.variables,
  );

  /// Executes the query. With no cache in 0.1.0, [QueryFetchPolicy.preferCache] and
  /// [QueryFetchPolicy.serverOnly] go to the server, and [QueryFetchPolicy.cacheOnly] throws a
  /// [DataConnectError] of kind [DataConnectErrorCode.cacheMiss].
  @override
  Future<QueryResult<Data, Variables>> execute({
    QueryFetchPolicy fetchPolicy = QueryFetchPolicy.preferCache,
  }) async {
    try {
      final core.QueryResult<Data, Map<String, Object?>> result =
          await _coreRef().execute(fetchPolicy: _corePolicy(fetchPolicy));
      return _resultOf(result);
    } on core.DataConnectException catch (error) {
      throw compatErrorOf<Data>(error);
    }
  }

  /// The results of this query that this client fetches: the first from a call on the first
  /// listen, then every successful execution of a reference with the same [operationId]. 0.1.0
  /// has no server push; the first call logs that once per client.
  Stream<QueryResult<Data, Variables>> subscribe() {
    return Stream<QueryResult<Data, Variables>>.multi(_listen);
  }

  void _listen(MultiStreamController<QueryResult<Data, Variables>> controller) {
    final Stream<core.QueryResult<Data, Map<String, Object?>>> source;
    try {
      source = _coreRef().subscribe();
    } on Object catch (error, stackTrace) {
      controller
        ..addError(error, stackTrace)
        ..close();
      return;
    }
    addQueryListener(dataConnect, this);
    bool listening = true;
    void stop() {
      if (listening) {
        listening = false;
        removeQueryListener(dataConnect, this);
      }
    }

    final StreamSubscription<core.QueryResult<Data, Map<String, Object?>>>
    subscription = source.listen(
      (core.QueryResult<Data, Map<String, Object?>> result) =>
          controller.add(_resultOf(result)),
      onError: (Object error, StackTrace stackTrace) => controller.addError(
        error is core.DataConnectException ? compatErrorOf<Data>(error) : error,
        stackTrace,
      ),
      onDone: () {
        stop();
        controller.close();
      },
    );
    controller
      ..onPause = subscription.pause
      ..onResume = subscription.resume
      ..onCancel = () {
        stop();
        return subscription.cancel();
      };
  }

  QueryResult<Data, Variables> _resultOf(
    core.QueryResult<Data, Map<String, Object?>> result,
  ) {
    final DataSource source = switch (result.source) {
      core.DataSource.cache => DataSource.cache,
      core.DataSource.server => DataSource.server,
    };
    return QueryResult<Data, Variables>(dataConnect, result.data, source, this);
  }

  @override
  core.QueryRef<Data, Map<String, Object?>> _coreRef() {
    return coreClientOf(dataConnect).query<Data, Map<String, Object?>>(
      operationName,
      decode: _decode,
      variables: _encodedVariables(),
      encodeVariables: _identity,
    );
  }

  static core.QueryFetchPolicy _corePolicy(QueryFetchPolicy policy) {
    switch (policy) {
      case QueryFetchPolicy.preferCache:
        return core.QueryFetchPolicy.preferCache;
      case QueryFetchPolicy.cacheOnly:
        return core.QueryFetchPolicy.cacheOnly;
      case QueryFetchPolicy.serverOnly:
        return core.QueryFetchPolicy.serverOnly;
    }
  }
}

/// A reference to a mutation.
class MutationRef<Data, Variables> extends OperationRef<Data, Variables> {
  /// The mutation [operationName] on [dataConnect], with [variables] that [serializer] writes and
  /// data that [deserializer] reads.
  MutationRef(
    super.dataConnect,
    super.operationName,
    super.deserializer,
    super.serializer,
    super.variables,
  );

  /// Executes the mutation.
  @override
  Future<OperationResult<Data, Variables>> execute() async {
    try {
      final core.MutationResult<Data, Map<String, Object?>> result =
          await _coreRef().execute();
      return OperationResult<Data, Variables>(
        dataConnect,
        result.data,
        DataSource.server,
        this,
      );
    } on core.DataConnectException catch (error) {
      throw compatErrorOf<Data>(error);
    }
  }

  @override
  core.MutationRef<Data, Map<String, Object?>> _coreRef() {
    return coreClientOf(dataConnect).mutation<Data, Map<String, Object?>>(
      operationName,
      decode: _decode,
      variables: _encodedVariables(),
      encodeVariables: _identity,
    );
  }
}
