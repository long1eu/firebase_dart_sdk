// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/firebase_client_grpc_metadata_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/firestore_channel.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/watch_stream.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/write_stream.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/async_task.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart';
import 'package:grpc/grpc.dart';
import 'package:meta/meta.dart';
import 'package:protobuf/protobuf.dart';

/// Datastore represents a proxy for the remote server, hiding details of the RPC layer. It:
///   * Manages connections to the server
///   * Authenticates to the server
///   * Manages threading and keeps higher-level code running on the worker queue
///   * Serializes internal model objects to and from protocol buffers
///
/// The Datastore is generally not responsible for understanding the higher-level protocol involved
/// in actually making changes or reading data, and is otherwise stateless.
class Datastore {
  factory Datastore({
    @required DatabaseInfo databaseInfo,
    @required AsyncQueue workerQueue,
    @required CredentialsProvider credentialsProvider,
    ClientChannel clientChannel,
    GrpcMetadataProvider metadataProvider,
  }) {
    clientChannel ??= ClientChannel(
      databaseInfo.host,
      options: ChannelOptions(
        credentials: databaseInfo.sslEnabled //
            ? const ChannelCredentials.secure()
            : const ChannelCredentials.insecure(),
      ),
    );

    final FirestoreChannel channel = FirestoreChannel(
      asyncQueue: workerQueue,
      credentialsProvider: credentialsProvider,
      channel: clientChannel,
      databaseId: databaseInfo.databaseId,
      metadataProvider: metadataProvider,
    );

    final RemoteSerializer serializer = RemoteSerializer(databaseInfo.databaseId);

    return Datastore.init(databaseInfo, workerQueue, serializer, channel);
  }

  @visibleForTesting
  Datastore.init(this.databaseInfo, this.workerQueue, this.serializer, this.channel);

  /// Set of lowercase, white-listed headers for logging purposes.
  static final Set<String> whiteListedHeaders = <String>{
    'date',
    'x-google-backends',
    'x-google-netmon-label',
    'x-google-service',
    'x-google-gfe-request-trace'
  };

  final DatabaseInfo databaseInfo;
  final AsyncQueue workerQueue;
  final RemoteSerializer serializer;
  final FirestoreChannel channel;

  Future<void> shutdown() => channel.shutdown();

  /// Creates a new [WatchStream] that is still unstarted but uses a common shared channel
  WatchStream createWatchStream(WatchStreamCallback listener) {
    return WatchStream(channel, workerQueue, serializer, listener);
  }

  /// Creates a new [WriteStream] that is still unstarted but uses a common shared channel
  WriteStream createWriteStream(WriteStreamCallback listener) {
    return WriteStream(channel, workerQueue, serializer, listener);
  }

  Future<List<MutationResult>> commit(List<Mutation> mutations) async {
    final CommitRequest builder = CommitRequest.create()..database = serializer.databaseName;

    for (Mutation mutation in mutations) {
      builder.writes.add(serializer.encodeMutation(mutation));
    }

    try {
      final CommitResponse response = await channel.runRpc(
        ClientMethod<CommitRequest, CommitResponse>(
          'firestore.googleapis.com/google.firestore.v1.Firestore/Commit',
          (GeneratedMessage req) => req.writeToBuffer(),
          (List<int> req) => CommitResponse.fromBuffer(req),
        ),
        builder.freeze(),
      );

      final SnapshotVersion commitVersion = serializer.decodeVersion(response.commitTime);

      final int count = response.writeResults.length;
      final List<MutationResult> results = List<MutationResult>(count);
      for (int i = 0; i < count; i++) {
        final WriteResult result = response.writeResults[i];
        results[i] = serializer.decodeMutationResult(result, commitVersion);
      }
      return results;
    } catch (e) {
      if (e is FirestoreError && e.code == FirestoreErrorCode.unauthenticated) {
        channel.invalidateToken();
      }

      rethrow;
    }
  }

  Future<List<MaybeDocument>> lookup(List<DocumentKey> keys) async {
    final BatchGetDocumentsRequest builder = BatchGetDocumentsRequest.create()..database = serializer.databaseName;
    for (DocumentKey key in keys) {
      builder.documents.add(serializer.encodeKey(key));
    }

    try {
      BatchGetDocumentsRequest();

      final List<BatchGetDocumentsResponse> responses = await channel.runStreamingResponseRpc(
          ClientMethod<BatchGetDocumentsResponse, BatchGetDocumentsResponse>(
            'firestore.googleapis.com/google.firestore.v1.Firestore/BatchGetDocuments',
            (GeneratedMessage req) => req.writeToBuffer(),
            (List<int> res) => BatchGetDocumentsResponse.fromBuffer(res),
          ),
          builder.freeze());

      final Map<DocumentKey, MaybeDocument> resultMap = <DocumentKey, MaybeDocument>{};
      for (BatchGetDocumentsResponse response in responses) {
        final MaybeDocument doc = serializer.decodeMaybeDocument(response);
        resultMap[doc.key] = doc;
      }
      final List<MaybeDocument> results = <MaybeDocument>[];
      for (DocumentKey key in keys) {
        results.add(resultMap[key]);
      }
      return results;
    } catch (e) {
      if (e is FirestoreError && e.code == FirestoreErrorCode.unauthenticated) {
        channel.invalidateToken();
      }
      rethrow;
    }
  }

  /// Determines whether the given status has an error code that represents a permanent error when received in response
  /// to a non-write operation.
  ///
  /// See [isPermanentWriteError] for classifying write errors.
  static bool isPermanentGrpcError(GrpcError status) {
    return isPermanentError(FirestoreErrorCode.fromValue(status));
  }

  /// Determines whether the given status has an error code that represents a permanent error when received in response
  /// to a non-write operation.
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
        // Unauthenticated means something went wrong with our token and we need to retry with new credentials which
        // will happen automatically.
        return false;
      case FirestoreErrorCode.invalidArgument:
      case FirestoreErrorCode.notFound:
      case FirestoreErrorCode.alreadyExists:
      case FirestoreErrorCode.permissionDenied:
      case FirestoreErrorCode.failedPrecondition:
      case FirestoreErrorCode.aborted:
      // Aborted might be retried in some scenarios, but that is dependant on the context and should handled
      // individually by the calling code. See https://cloud.google.com/apis/design/errors.
      case FirestoreErrorCode.outOfRange:
      case FirestoreErrorCode.unimplemented:
      case FirestoreErrorCode.dataLoss:
        return true;
      default:
        throw ArgumentError('Unknown gRPC status code: $code');
    }
  }

  /// Determines whether the given status has an error code that represents a permanent error when received in response
  /// to a write operation.
  ///
  /// Write operations must be handled specially because as of b/119437764, ABORTED errors on the write stream should be
  /// retried too (even though ABORTED errors are not generally retryable).
  ///
  /// Note that during the initial handshake on the write stream an ABORTED error signals that we should discard our
  /// stream token (i.e. it is permanent). This means a handshake error should be classified with [isPermanentError],
  /// above.
  static bool isPermanentWriteError(GrpcError status) {
    return isPermanentGrpcError(status) && status.code != StatusCode.aborted;
  }
}
