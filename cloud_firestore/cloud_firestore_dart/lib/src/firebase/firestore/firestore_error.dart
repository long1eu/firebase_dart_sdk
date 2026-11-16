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
/// `Firestore.runTransaction`. An error you receive is usually one the client
/// gave up on, or one from a call that does not retry by itself, such as
/// `get(Source.server)` or an aggregation.
///
/// ```dart
/// try {
///   await firestore.doc('cities/SF').update(<String, Object?>{'visits': 1});
/// } on FirestoreError catch (e) {
///   if (e.code == FirestoreErrorCode.notFound) {
///     print('No such city');
///   } else if (e.code == FirestoreErrorCode.permissionDenied) {
///     print('Not allowed: ${e.message}');
///   } else {
///     rethrow;
///   }
/// }
/// ```
///
/// The names follow the Android SDK in lowerCamelCase. The JS SDK uses the
/// same codes as strings, for example `'permission-denied'`.
class FirestoreErrorCode {
  const FirestoreErrorCode._(this.value);

  /// The numeric gRPC status code, for example 7 for [permissionDenied].
  final int value;

  /// The operation completed successfully. Never the code of a thrown [FirestoreException].
  static const FirestoreErrorCode ok = FirestoreErrorCode._(0);

  /// The operation was cancelled, typically by the caller.
  ///
  /// The client produces it when the signed-in user changes while a
  /// `Firestore.waitForPendingWrites` future is waiting; the transport
  /// reports it for a call that was cancelled on the way. Retrying makes
  /// sense; for `waitForPendingWrites`, call it again for the new user.
  static const FirestoreErrorCode cancelled = FirestoreErrorCode._(1);

  /// An unknown error, or an error from a different error domain.
  ///
  /// The client produces it when an error that is not a [FirestoreException]
  /// occurs below a write of a `DocumentReference` or in a call to the
  /// backend, and when `Firestore.clearPersistence` cannot delete the files
  /// of the cache (on Windows, for example, while another isolate or process
  /// has them open). The message holds the original error. A retry can help
  /// if the cause was temporary.
  static const FirestoreErrorCode unknown = FirestoreErrorCode._(2);

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
  static const FirestoreErrorCode invalidArgument = FirestoreErrorCode._(3);

  /// The deadline expired before the operation could complete. The operation may still have
  /// succeeded on the server.
  ///
  /// Comes from the backend or the transport, never from the client itself.
  /// A retry makes sense, but a write may then be applied twice: make it
  /// idempotent or read before writing again.
  static const FirestoreErrorCode deadlineExceeded = FirestoreErrorCode._(4);

  /// A requested document was not found.
  ///
  /// The backend returns it for an `update` of a document that does not
  /// exist, in a single write, a batch or a transaction.
  /// A plain read of a missing document is not an error: its snapshot has
  /// `exists` false. Retrying does not help until the document exists; use
  /// `set` with a merge option to create or update it in one call.
  static const FirestoreErrorCode notFound = FirestoreErrorCode._(5);

  /// The document the operation tried to create already exists.
  ///
  /// The backend returns it when a write requires the document to be missing,
  /// for example in a transaction that read a document as missing and then
  /// wrote it while another client created it. Transactions retry on this
  /// code by themselves; elsewhere a retry of the same write fails again.
  static const FirestoreErrorCode alreadyExists = FirestoreErrorCode._(6);

  /// The caller does not have permission to run the operation, for example because the security
  /// rules reject it.
  ///
  /// The backend returns it. A rejected write is removed from the local cache
  /// again, and a rejected listen ends its stream with this error. Retrying
  /// does not help until the rules, the signed-in user or the data change.
  static const FirestoreErrorCode permissionDenied = FirestoreErrorCode._(7);

  /// A resource has been exhausted, such as a per-user quota or the storage of the project.
  ///
  /// The backend returns it. Retry later with a backoff; the client does so
  /// itself for listens and writes.
  static const FirestoreErrorCode resourceExhausted = FirestoreErrorCode._(8);

  /// The operation was rejected because the system is not in the state it requires, for example a
  /// query that needs an index that does not exist.
  ///
  /// The backend returns it for a query that needs a composite index (the
  /// message has a link that creates it), and a transaction fails with it
  /// when the documents it read kept changing until its attempts were used up.
  ///
  /// The client produces it for any call on a terminated `Firestore`
  /// instance; for `Firestore.clearPersistence` while the instance (or
  /// another one on the same cache) is running; for `toJson` of a snapshot
  /// with pending writes; and with a persistent cache, when the cache was
  /// opened by another version of the SDK or cleared by another client, when
  /// a client that shares the cache lost its primary role, or on the web when
  /// another tab already has the cache open. Retrying the same call does not
  /// help: change the state first (create a new instance, create the index,
  /// wait for the pending writes).
  static const FirestoreErrorCode failedPrecondition = FirestoreErrorCode._(9);

  /// The operation was aborted, typically because of a concurrency problem such as a transaction
  /// conflict.
  ///
  /// The backend returns it for a transaction that conflicts with another
  /// one; the client produces it when a transaction reads the same document
  /// twice and gets two versions. Transactions and writes retry on this code
  /// by themselves, so you see it only when the attempts were used up. A
  /// retry of the whole transaction can then succeed.
  static const FirestoreErrorCode aborted = FirestoreErrorCode._(10);

  /// The operation was attempted past the valid range.
  ///
  /// Comes from the backend only. Retrying the same call does not help.
  static const FirestoreErrorCode outOfRange = FirestoreErrorCode._(11);

  /// The operation is not implemented or not supported.
  ///
  /// The backend (or the emulator) returns it for a feature it does not
  /// support, for example one that needs the Enterprise edition. The client
  /// produces it when the backend answers an aggregation (also one in a
  /// transaction) without any response. Retrying does not help.
  static const FirestoreErrorCode unimplemented = FirestoreErrorCode._(12);

  /// An internal error: an invariant expected by the underlying system was broken.
  ///
  /// Comes from the backend. The client retries listens and writes; for other
  /// calls a retry with a backoff can help.
  static const FirestoreErrorCode internal = FirestoreErrorCode._(13);

  /// The service is currently unavailable. This is most likely transient and the operation can be
  /// retried with a backoff.
  ///
  /// The backend or the transport returns it when the server cannot be
  /// reached. The client produces it when a call needs the server while the
  /// client is offline: `get(Source.server)`, aggregations, vector queries
  /// and pipelines; for `get(Source.cache)` of a document that is not in the
  /// cache; and when the local cache cannot store a write or start a listen
  /// (for example a database that stays busy). Retry with a backoff, or read
  /// from the cache instead.
  static const FirestoreErrorCode unavailable = FirestoreErrorCode._(14);

  /// Unrecoverable data loss or corruption.
  ///
  /// Comes from the backend only. Retrying does not help.
  static const FirestoreErrorCode dataLoss = FirestoreErrorCode._(15);

  /// The request does not carry valid authentication credentials for the operation.
  ///
  /// The backend returns it for a missing, expired or invalid token. The
  /// client asks the token provider for a fresh token and retries listens and
  /// writes by itself. If you still see it, check how the app signs in (see
  /// `package:firebase_auth_providers_dart`).
  static const FirestoreErrorCode unauthenticated = FirestoreErrorCode._(16);

  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  static FirestoreErrorCode fromValue(GrpcError error) {
    // Unknown (e.g. forward-compatible or custom) codes map to `unknown`.
    return error.code >= 0 && error.code < values.length
        ? values[error.code]
        : unknown;
  }

  /// All codes, indexed by their numeric [value].
  static const List<FirestoreErrorCode> values = <FirestoreErrorCode>[
    ok,
    cancelled,
    unknown,
    invalidArgument,
    deadlineExceeded,
    notFound,
    alreadyExists,
    permissionDenied,
    resourceExhausted,
    failedPrecondition,
    aborted,
    outOfRange,
    unimplemented,
    internal,
    unavailable,
    dataLoss,
    unauthenticated,
  ];

  static const List<String> _names = <String>[
    'ok',
    'cancelled',
    'unknown',
    'invalidArgument',
    'deadlineExceeded',
    'notFound',
    'alreadyExists',
    'permissionDenied',
    'resourceExhausted',
    'failedPrecondition',
    'aborted',
    'outOfRange',
    'unimplemented',
    'internal',
    'unavailable',
    'dataLoss',
    'unauthenticated',
  ];

  @override
  String toString() => _names[value];
}

/// The error thrown by Firestore operations. [code] says what went wrong.
///
/// Futures fail with it, and streams (`snapshots`) deliver it to `onError`,
/// after which the stream is done. [FirestoreException.message] (from
/// `FirebaseError`) describes the cause in words; it is meant for logs, not
/// for program logic. Check [code] instead. Invalid arguments that the client
/// detects before sending anything are reported as an [ArgumentError], not as
/// a [FirestoreException].
///
/// Like `FirebaseError`, it implements [Error], not [Exception]: catch it with
/// `on FirestoreError`, not `on Exception`.
///
/// ```dart
/// firestore.collection('cities').snapshots.listen(
///   (QuerySnapshot<Map<String, Object?>> snapshot) => print(snapshot.length),
///   onError: (Object error) {
///     if (error is FirestoreError &&
///         error.code == FirestoreErrorCode.permissionDenied) {
///       print('Listen rejected by the security rules');
///     }
///   },
/// );
/// ```
class FirestoreException extends FirebaseException {
  /// Creates an error with a [message] and a [code], optionally keeping the [cause] and a stack
  /// trace.
  ///
  /// The SDK creates these errors; you need the constructor only for tests
  /// and fakes.
  FirestoreException(
    String message,
    this.code, [
    this.cause,
    StackTrace? stackTrance,
  ]) : super(message, stackTrance);

  /// The status code of this error, the part to check in code.
  final FirestoreErrorCode code;

  /// The lower-level error that caused this one, if any.
  final Object? cause;

  @override
  String toString() => '$runtimeType: [code=$code]: $message';
}
