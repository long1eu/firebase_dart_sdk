// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/database_info.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart';
import 'package:grpc/grpc.dart';
import 'package:meta/meta.dart';

/**
 * Datastore represents a proxy for the remote server, hiding details of the RPC layer. It:
 *
 * <ul>
 *   <li>Manages connections to the server
 *   <li>Authenticates to the server
 *   <li>Manages threading and keeps higher-level code running on the worker queue
 *   <li>Serializes internal model objects to and from protocol buffers
 * </ul>
 *
 * <p>The Datastore is generally not responsible for understanding the higher-level protocol
 * involved in actually making changes or reading data, and is otherwise stateless.
 */
class Datastore {
  /** Set of lowercase, white-listed headers for logging purposes. */
  static final Set<String> WHITE_LISTED_HEADERS = new Set<String>.from([
    "date",
    "x-google-backends",
    "x-google-netmon-label",
    "x-google-service",
    "x-google-gfe-request-trace"
  ]);

  final DatabaseInfo databaseInfo;
  final AsyncQueue workerQueue;
  final RemoteSerializer serializer;
  final FirestoreChannel channel;

  static Supplier<ManagedChannelBuilder<dynamic>>
      overrideChannelBuilderSupplier;

  /**
   * Helper function to globally override the channel that RPCs use. Useful for testing when you
   * want to bypass SSL certificate checking.
   *
   * @param channelBuilderSupplier The supplier for a channel builder that is used to create gRPC
   *     channels.
   */
  @visibleForTesting
  static void overrideChannelBuilder(
      Supplier<ManagedChannelBuilder<dynamic>> channelBuilderSupplier) {
    Datastore.overrideChannelBuilderSupplier = channelBuilderSupplier;
  }

  Datastore(DatabaseInfo databaseInfo, AsyncQueue workerQueue,
      CredentialsProvider credentialsProvider) {
    this.databaseInfo = databaseInfo;
    this.workerQueue = workerQueue;
    this.serializer = new RemoteSerializer(databaseInfo.databaseId);

    ManagedChannelBuilder<dynamic> channelBuilder;
    if (overrideChannelBuilderSupplier != null) {
      channelBuilder = overrideChannelBuilderSupplier();
    } else {
      channelBuilder = ManagedChannelBuilder.forTarget(databaseInfo.host);
      if (!databaseInfo.isSslEnabled()) {
        // Note that the boolean flag does *NOT* indicate whether or not plaintext should be used
        channelBuilder.usePlaintext();
      }
    }

    // This ensures all callbacks are issued on the worker queue. If this call is removed,
    // all calls need to be audited to make sure they are executed on the right thread.
    channelBuilder.executor(workerQueue.getExecutor());

    channel = new FirestoreChannel(workerQueue, credentialsProvider,
        channelBuilder.build(), databaseInfo.databaseId);
  }

  /** Creates a new WatchStream that is still unstarted but uses a common shared channel */
  WatchStream createWatchStream(WatchStream.Callback listener) {
    return new WatchStream(channel, workerQueue, serializer, listener);
  }

  /** Creates a new WriteStream that is still unstarted but uses a common shared channel */
  WriteStream createWriteStream(WriteStream.Callback listener) {
    return new WriteStream(channel, workerQueue, serializer, listener);
  }

  Future<List<MutationResult>> commit(List<Mutation> mutations) {
    CommitRequest.Builder builder = CommitRequest.newBuilder();
    builder.setDatabase(serializer.databaseName());
    for (Mutation mutation in mutations) {
      builder.addWrites(serializer.encodeMutation(mutation));
    }
    /*
    return channel
        .runRpc(FirestoreGrpc.getCommitMethod(), builder.build())
        .continueWith(
            workerQueue.getExecutor(),
            task -> {
              if (!task.isSuccessful()) {
                if (task.getException() instanceof FirebaseFirestoreException
                    && ((FirebaseFirestoreException) task.getException()).getCode()
                        == FirebaseFirestoreException.Code.UNAUTHENTICATED) {
                  channel.invalidateToken();
                }
                throw task.getException();
              }
              CommitResponse response = task.getResult();
              SnapshotVersion commitVersion = serializer.decodeVersion(response.getCommitTime());

              int count = response.getWriteResultsCount();
              ArrayList<MutationResult> results = new ArrayList<>(count);
              for (int i = 0; i < count; i++) {
                com.google.firestore.v1beta1.WriteResult result = response.getWriteResults(i);
                results.add(serializer.decodeMutationResult(result, commitVersion));
              }
              return results;
            });*/
  }

  Future<List<MaybeDocument>> lookup(List<DocumentKey> keys) {
    BatchGetDocumentsRequest.Builder builder =
        BatchGetDocumentsRequest.newBuilder();
    builder.setDatabase(serializer.databaseName());
    for (DocumentKey key in keys) {
      builder.addDocuments(serializer.encodeKey(key));
    }
    /*
    return channel
        .runStreamingResponseRpc(FirestoreGrpc.getBatchGetDocumentsMethod(), builder.build())
        .continueWith(
            workerQueue.getExecutor(),
            task -> {
              if (!task.isSuccessful()) {
                if (task.getException() instanceof FirebaseFirestoreException
                    && ((FirebaseFirestoreException) task.getException()).getCode()
                        == FirebaseFirestoreException.Code.UNAUTHENTICATED) {
                  channel.invalidateToken();
                }
              }

              Map<DocumentKey, MaybeDocument> resultMap = new HashMap<>();
              List<BatchGetDocumentsResponse> responses = task.getResult();
              for (BatchGetDocumentsResponse response : responses) {
                MaybeDocument doc = serializer.decodeMaybeDocument(response);
                resultMap.put(doc.getKey(), doc);
              }
              List<MaybeDocument> results = new ArrayList<>();
              for (DocumentKey key : keys) {
                results.add(resultMap.get(key));
              }
              return results;
            });*/
  }

  static bool isPermanentWriteError(GrpcError status) {
    // See go/firestore-client-errors
    switch (status.code) {
      case StatusCode.ok:
        throw new ArgumentError("Treated status OK as error");
      case StatusCode.cancelled:
      case StatusCode.unknown:
      case StatusCode.deadlineExceeded:
      case StatusCode.resourceExhausted:
      case StatusCode.internal:
      case StatusCode.unavailable:
      case StatusCode.unauthenticated:
        // Unauthenticated means something went wrong with our token and we need
        // to retry with new credentials which will happen automatically.
        return false;
      case StatusCode.invalidArgument:
      case StatusCode.notFound:
      case StatusCode.alreadyExists:
      case StatusCode.permissionDenied:
      case StatusCode.failedPrecondition:
      case StatusCode.aborted:
      // Aborted might be retried in some scenarios, but that is dependant on
      // the context and should handled individually by the calling code.
      // See https://cloud.google.com/apis/design/errors.
      case StatusCode.outOfRange:
      case StatusCode.unimplemented:
      case StatusCode.dataLoss:
        return true;
      default:
        throw new ArgumentError('Unknown gRPC status code: ${status}');
    }
  }
}
