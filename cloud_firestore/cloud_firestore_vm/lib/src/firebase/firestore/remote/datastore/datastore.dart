// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

library datastore;

import 'dart:async';
import 'dart:typed_data';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:async/async.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/exponential_backoff.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/on_error_resume.dart.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_vm/src/proto/index.dart' as proto;
import 'package:grpc/grpc.dart';
import 'package:meta/meta.dart';
import 'package:pedantic/pedantic.dart';
import 'package:protobuf/protobuf.dart';
import 'package:rxdart/rxdart.dart' hide OnErrorResumeStreamTransformer;

import 'channel_options_provider.dart';

part 'base_stream.dart';
part 'firestore_client.dart';
part 'transaction_client.dart';
part 'watch_stream.dart';
part 'write_stream.dart';

/// Datastore represents a proxy for the remote server, hiding details of the
/// RPC layer. It:
///   * Manages connections to the server
///   * Authenticates to the server
///   * Serializes internal model objects to and from protocol buffers
///
/// The Datastore is generally not responsible for understanding the
/// higher-level protocol involved in actually making changes or reading data,
/// and is otherwise stateless.
class Datastore {
  factory Datastore(
    TaskScheduler scheduler,
    DatabaseInfo databaseInfo,
    CredentialsProvider credentialsProvider, {
    ClientChannel clientChannel,
  }) {
    clientChannel ??= ClientChannel(
      databaseInfo.host,
      port: databaseInfo.port,
      options: ChannelOptions(
        credentials: databaseInfo.sslEnabled //
            ? const ChannelCredentials.secure()
            : const ChannelCredentials.insecure(),
      ),
    );

    final ChannelOptionsProvider optionsProvider = ChannelOptionsProvider(
      databaseId: databaseInfo.databaseId,
      credentialsProvider: credentialsProvider,
    );
    final FirestoreClient client =
        FirestoreClient(clientChannel, optionsProvider);
    final RemoteSerializer serializer =
        RemoteSerializer(databaseInfo.databaseId);
    clientChannel
        .getConnection() //
        .then<void>((dynamic connection) => connection.onStateChanged =
            (dynamic c) => client.onStateChanged(c.state));
    return Datastore.test(scheduler, databaseInfo, serializer, client);
  }

  @visibleForTesting
  Datastore.test(
    this._scheduler,
    this._databaseInfo,
    this._serializer,
    this._client,
  );

  /// Set of lowercase, white-listed headers for logging purposes.
  static final Set<String> whiteListedHeaders = <String>{
    'date',
    'x-google-backends',
    'x-google-netmon-label',
    'x-google-service',
    'x-google-gfe-request-trace'
  };

  final TaskScheduler _scheduler;
  final DatabaseInfo _databaseInfo;
  final RemoteSerializer _serializer;
  final FirestoreClient _client;

  /// Creates a new [WatchStream] that is still unstarted but uses a common
  /// shared channel
  WatchStream get watchStream {
    return WatchStream(
      client: _client,
      scheduler: _scheduler,
      serializer: _serializer,
    );
  }

  /// Creates a new [WriteStream] that is still unstarted but uses a common
  /// shared channel
  WriteStream get writeStream {
    return WriteStream(
      client: _client,
      scheduler: _scheduler,
      serializer: _serializer,
    );
  }

  /// Creates a new [TransactionClient] that uses a common shared channel
  TransactionClient get transactionClient =>
      TransactionClient(_client, _serializer);

  Future<void> shutdown() {
    return _client.shutdown();
  }

  /// Determines whether the given status has an error code that represents a
  /// permanent error when received in response to a non-write operation.
  ///
  /// See [isPermanentWriteError] for classifying write errors.
  static bool isPermanentGrpcError(GrpcError status) {
    return isPermanentError(FirestoreErrorCode.fromValue(status));
  }

  /// Determines whether the given error code represents a permanent error when
  /// received in response to a non-write operation.
  ///
  /// See [isPermanentWriteError] for classifying write errors.
  static bool isPermanentError(FirestoreErrorCode code) {
    // See go/firestore-client-errors
    switch (code) {
      case FirestoreErrorCode.ok:
        throw ArgumentError('Treated status OK as error');
      case FirestoreErrorCode.cancelled:
      case FirestoreErrorCode.unknown:
      case FirestoreErrorCode.deadlineExceeded:
      case FirestoreErrorCode.resourceExhausted:
      case FirestoreErrorCode.internal:
      case FirestoreErrorCode.unavailable:
      case FirestoreErrorCode.unauthenticated:
        // Unauthenticated means something went wrong with our token and we need
        // to retry with new credentials which will happen automatically.
        return false;
      case FirestoreErrorCode.invalidArgument:
      case FirestoreErrorCode.notFound:
      case FirestoreErrorCode.alreadyExists:
      case FirestoreErrorCode.permissionDenied:
      case FirestoreErrorCode.failedPrecondition:
      case FirestoreErrorCode.aborted:
      // Aborted might be retried in some scenarios, but that is dependant on
      // the context and should handled individually by the calling code.
      // See https://cloud.google.com/apis/design/errors.
      case FirestoreErrorCode.outOfRange:
      case FirestoreErrorCode.unimplemented:
      case FirestoreErrorCode.dataLoss:
        return true;
      default:
        throw ArgumentError('Unknown gRPC status code: $code');
    }
  }

  /// Determines whether the given status has an error code that represents a
  /// permanent error when received in response to a write operation.
  ///
  /// Write operations must be handled specially because as of b/119437764,
  /// ABORTED errors on the write stream should be retried too (even though
  /// ABORTED errors are not generally retryable).
  ///
  /// Note that during the initial handshake on the write stream an ABORTED
  /// error signals that we should discard our stream token (i.e. it is
  /// permanent). This means a handshake error should be classified with
  /// [isPermanentError], above.
  static bool isPermanentWriteError(GrpcError status) {
    return isPermanentGrpcError(status) && status.code != StatusCode.aborted;
  }

  @override
  String toString() {
    return (ToStringHelper(Datastore)
          ..add('databaseInfo', _databaseInfo)
          ..add('serializer', _serializer)
          ..add('client', _client))
        .toString();
  }
}
