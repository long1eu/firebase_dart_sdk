// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

/// The status code of a [FirestoreException]. The codes and their numeric [value]s are the canonical
/// gRPC status codes.
///
/// Most codes come from the backend and reach you unchanged. The client also
/// produces some of them itself; the documentation of each code says when,
/// and whether trying the same operation again can help.
///
/// The client already retries, with a backoff, what a retry can fix: listens
/// and writes that fail with [cancelled], [unknown], [deadlineExceeded],
/// [resourceExhausted], [internal], [unavailable] or [unauthenticated] are
/// sent again without an error reaching you (writes also on [aborted]), and
/// transactions are attempted again as described on
/// `FirebaseFirestore.runTransaction`. An error you receive is usually one the client
/// gave up on, or one from a call that does not retry by itself, such as
/// a `get` with `Source.server` or an aggregation.
///
/// ```dart
/// try {
///   await firestore.doc('cities/SF').update(<String, Object?>{'visits': 1});
/// } on FirestoreException catch (e) {
///   if (e.errorCode == FirestoreErrorCode.notFound) {
///     print('No such city');
///   } else if (e.errorCode == FirestoreErrorCode.permissionDenied) {
///     print('Not allowed: ${e.message}');
///   } else {
///     rethrow;
///   }
/// }
/// ```
///
/// The names follow the Android SDK in lowerCamelCase; [code] is the string of
/// FlutterFire and the JS SDK, for example `'permission-denied'`.
enum FirestoreErrorCode {
  /// The operation completed successfully. Never the code of a thrown [FirestoreException].
  ok(0, 'ok'),

  /// The operation was cancelled, typically by the caller.
  ///
  /// The client produces it when the signed-in user changes while a
  /// `FirebaseFirestore.waitForPendingWrites` future is waiting; the transport
  /// reports it for a call that was cancelled on the way. Retrying makes
  /// sense; for `waitForPendingWrites`, call it again for the new user.
  cancelled(1, 'cancelled'),

  /// An unknown error, or an error from a different error domain.
  ///
  /// The client produces it when an error that is not a [FirestoreException]
  /// occurs below a write of a `DocumentReference` or in a call to the
  /// backend, and when `FirebaseFirestore.clearPersistence` cannot delete the files
  /// of the cache (on Windows, for example, while another isolate or process
  /// has them open). The message holds the original error. A retry can help
  /// if the cause was temporary.
  unknown(2, 'unknown'),

  /// The client passed an invalid argument. Unlike [failedPrecondition], the argument is wrong
  /// regardless of the state of the system (for example a malformed field name).
  ///
  /// The backend returns it for a request it cannot accept, for example a
  /// document or a value that exceeds a limit. The client produces it in a
  /// transaction that reads after writing, that updates a document it read as
  /// missing, that writes in a read-only transaction, or that calls
  /// `Transaction.getQuery` or `Transaction.getAggregate` in a read-write
  /// transaction; for a bundle that cannot be loaded; and for snapshot JSON
  /// that `DocumentSnapshot.fromJson`, `QuerySnapshot.fromJson` and the
  /// `...SnapshotsFromJson` methods cannot read. Arguments that are wrong
  /// before anything is sent (invalid data, field paths or query
  /// combinations) are reported as an [ArgumentError] instead. Retrying the
  /// same call does not help; fix the call.
  invalidArgument(3, 'invalid-argument'),

  /// The deadline expired before the operation could complete. The operation may still have
  /// succeeded on the server.
  ///
  /// Comes from the backend or the transport, never from the client itself.
  /// A retry makes sense, but a write may then be applied twice: make it
  /// idempotent or read before writing again.
  deadlineExceeded(4, 'deadline-exceeded'),

  /// A requested document was not found.
  ///
  /// The backend returns it for an `update` of a document that does not
  /// exist, in a single write, a batch or a transaction.
  /// A plain read of a missing document is not an error: its snapshot has
  /// `exists` false. Retrying does not help until the document exists; use
  /// `set` with a merge option to create or update it in one call.
  notFound(5, 'not-found'),

  /// The document the operation tried to create already exists.
  ///
  /// The backend returns it when a write requires the document to be missing,
  /// for example in a transaction that read a document as missing and then
  /// wrote it while another client created it. Transactions retry on this
  /// code by themselves; elsewhere a retry of the same write fails again.
  alreadyExists(6, 'already-exists'),

  /// The caller does not have permission to run the operation, for example because the security
  /// rules reject it.
  ///
  /// The backend returns it. A rejected write is removed from the local cache
  /// again, and a rejected listen ends its stream with this error. Retrying
  /// does not help until the rules, the signed-in user or the data change.
  permissionDenied(7, 'permission-denied'),

  /// A resource has been exhausted, such as a per-user quota or the storage of the project.
  ///
  /// The backend returns it. Retry later with a backoff; the client does so
  /// itself for listens and writes.
  resourceExhausted(8, 'resource-exhausted'),

  /// The operation was rejected because the system is not in the state it requires, for example a
  /// query that needs an index that does not exist.
  ///
  /// The backend returns it for a query that needs a composite index (the
  /// message has a link that creates it), and a transaction fails with it
  /// when the documents it read kept changing until its attempts were used up.
  ///
  /// The client produces it for any call on a terminated `FirebaseFirestore`
  /// instance; for `FirebaseFirestore.clearPersistence` while the instance (or
  /// another one on the same cache) is running; for `toJson` of a snapshot
  /// with pending writes; and with a persistent cache, when the cache was
  /// opened by another version of the SDK or cleared by another client, when
  /// a client that shares the cache lost its primary role, or on the web when
  /// another tab already has the cache open. Retrying the same call does not
  /// help: change the state first (create a new instance, create the index,
  /// wait for the pending writes).
  failedPrecondition(9, 'failed-precondition'),

  /// The operation was aborted, typically because of a concurrency problem such as a transaction
  /// conflict.
  ///
  /// The backend returns it for a transaction that conflicts with another
  /// one; the client produces it when a transaction reads the same document
  /// twice and gets two versions. Transactions and writes retry on this code
  /// by themselves, so you see it only when the attempts were used up. A
  /// retry of the whole transaction can then succeed.
  aborted(10, 'aborted'),

  /// The operation was attempted past the valid range.
  ///
  /// Comes from the backend only. Retrying the same call does not help.
  outOfRange(11, 'out-of-range'),

  /// The operation is not implemented or not supported.
  ///
  /// The backend (or the emulator) returns it for a feature it does not
  /// support, for example one that needs the Enterprise edition. The client
  /// produces it when the backend answers an aggregation (also one in a
  /// transaction) without any response. Retrying does not help.
  unimplemented(12, 'unimplemented'),

  /// An internal error: an invariant expected by the underlying system was broken.
  ///
  /// Comes from the backend. The client retries listens and writes; for other
  /// calls a retry with a backoff can help.
  internal(13, 'internal'),

  /// The service is currently unavailable. This is most likely transient and the operation can be
  /// retried with a backoff.
  ///
  /// The backend or the transport returns it when the server cannot be
  /// reached. The client produces it when a call needs the server while the
  /// client is offline: a `get` with `Source.server`, aggregations, vector
  /// queries and pipelines; for a `get` with `Source.cache` of a document that is not in the
  /// cache; and when the local cache cannot store a write or start a listen
  /// (for example a database that stays busy). Retry with a backoff, or read
  /// from the cache instead.
  unavailable(14, 'unavailable'),

  /// Unrecoverable data loss or corruption.
  ///
  /// Comes from the backend only. Retrying does not help.
  dataLoss(15, 'data-loss'),

  /// The request does not carry valid authentication credentials for the operation.
  ///
  /// The backend returns it for a missing, expired or invalid token. The
  /// client asks the token provider for a fresh token and retries listens and
  /// writes by itself. If you still see it, check how the app signs in (see
  /// `package:firebase_auth_providers_dart`).
  unauthenticated(16, 'unauthenticated');

  const FirestoreErrorCode(this.value, this.code);

  /// The numeric gRPC status code, for example 7 for [permissionDenied]. [values] is in the order
  /// of these numbers.
  final int value;

  /// The code in the form of FlutterFire and the JS SDK, for example `'permission-denied'`: the
  /// [FirebaseException.code] of a [FirestoreException] with this code.
  final String code;

  @override
  String toString() => name;
}

/// Implementation details of [FirestoreErrorCode]; not part of the supported API.
extension FirestoreErrorCodeInternal on FirestoreErrorCode {
  /// The code of a gRPC error; codes this client does not know map to [FirestoreErrorCode.unknown].
  static FirestoreErrorCode fromValue(GrpcError error) {
    return error.code >= 0 && error.code < FirestoreErrorCode.values.length
        ? FirestoreErrorCode.values[error.code]
        : FirestoreErrorCode.unknown;
  }
}

/// The exception thrown by Firestore operations. [errorCode] says what went wrong.
///
/// Futures fail with it, and streams (`snapshots()`) deliver it to `onError`,
/// after which the stream is done. It extends [FirebaseException], like the
/// exceptions of FlutterFire: [plugin] is `cloud_firestore` and [code] is the
/// string form of [errorCode] (`'permission-denied'`). [message] describes the
/// cause in words; it is meant for logs, not for program logic. Check
/// [errorCode] (or [code]) instead. Invalid arguments that the client detects
/// before sending anything are reported as an [ArgumentError], not as a
/// [FirestoreException].
///
/// Note that [code] is a `String`: compare [errorCode] with the
/// [FirestoreErrorCode] values.
///
/// ```dart
/// firestore.collection('cities').snapshots().listen(
///   (QuerySnapshot<Map<String, Object?>> snapshot) => print(snapshot.size),
///   onError: (Object error) {
///     if (error is FirestoreException &&
///         error.errorCode == FirestoreErrorCode.permissionDenied) {
///       print('Listen rejected by the security rules');
///     }
///   },
/// );
/// ```
class FirestoreException extends FirebaseException {
  /// Creates an exception with an [errorCode] and a [message], optionally keeping the [cause] and
  /// a stack trace.
  ///
  /// The SDK creates these exceptions; you need the constructor only for tests
  /// and fakes.
  FirestoreException({
    required this.errorCode,
    required String message,
    this.cause,
    super.stackTrace,
  }) : super(plugin: 'cloud_firestore', code: errorCode.code, message: message);

  /// The status code of this exception, the part to check in code.
  final FirestoreErrorCode errorCode;

  /// The lower-level error that caused this one, if any.
  final Object? cause;

  /// A description of what went wrong, for logs.
  @override
  String get message => super.message!;

  /// `[cloud_firestore/<code>] <message>`, the format of FlutterFire, on one line: the stack trace is left out.
  @override
  String toString() => '[$plugin/$code] $message';
}
