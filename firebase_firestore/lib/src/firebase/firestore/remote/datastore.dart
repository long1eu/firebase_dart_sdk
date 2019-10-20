// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/database_info.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/write_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/firestore_channel.dart';
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/firestore.pb.dart';
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/write.pb.dart';
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
  factory Datastore(
      DatabaseInfo databaseInfo, AsyncQueue workerQueue, CredentialsProvider credentialsProvider,
      {ClientChannel clientChannel}) {
    clientChannel ??= ClientChannel(databaseInfo.host,
        options: ChannelOptions(
            credentials: databaseInfo.sslEnabled
                ? const ChannelCredentials.secure()
                : const ChannelCredentials.insecure()));

    final FirestoreChannel channel = FirestoreChannel(
      workerQueue,
      credentialsProvider,
      clientChannel,
      databaseInfo.databaseId,
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
          'firestore.googleapis.com/google.firestore.v1beta1.Firestore/Commit',
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
      if (e is FirebaseFirestoreError && e.code == FirebaseFirestoreErrorCode.unauthenticated) {
        channel.invalidateToken();
      }

      rethrow;
    }
  }

  Future<List<MaybeDocument>> lookup(List<DocumentKey> keys) async {
    final BatchGetDocumentsRequest builder = BatchGetDocumentsRequest.create();
    builder.database = serializer.databaseName;
    for (DocumentKey key in keys) {
      builder.documents.add(serializer.encodeKey(key));
    }

    try {
      final List<BatchGetDocumentsResponse> responses = await channel.runStreamingResponseRpc(
          ClientMethod<BatchGetDocumentsResponse, BatchGetDocumentsResponse>(
            'firestore.googleapis.com/google.firestore.v1beta1.Firestore/BatchGetDocuments',
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
      if (e is FirebaseFirestoreError && e.code == FirebaseFirestoreErrorCode.unauthenticated) {
        channel.invalidateToken();
      }
      rethrow;
    }
  }

  static bool isPermanentWriteError(GrpcError status) {
    // See go/firestore-client-errors
    switch (status.code) {
      case StatusCode.ok:
        throw ArgumentError('Treated status OK as error');
      case StatusCode.cancelled:
      case StatusCode.unknown:
      case StatusCode.deadlineExceeded:
      case StatusCode.resourceExhausted:
      case StatusCode.internal:
      case StatusCode.unavailable:
      case StatusCode.unauthenticated:
        // Unauthenticated means something went wrong with our token and we need to retry with new
        // credentials which will happen automatically.
        return false;
      case StatusCode.invalidArgument:
      case StatusCode.notFound:
      case StatusCode.alreadyExists:
      case StatusCode.permissionDenied:
      case StatusCode.failedPrecondition:
      case StatusCode.aborted:
      // Aborted might be retried in some scenarios, but that is dependant on the context and should
      // handled individually by the calling code. See https://cloud.google.com/apis/design/errors.
      case StatusCode.outOfRange:
      case StatusCode.unimplemented:
      case StatusCode.dataLoss:
        return true;
      default:
        throw ArgumentError('Unknown gRPC status code: $status');
    }
  }
}
