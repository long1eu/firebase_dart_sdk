/// A location in the database, to read and write. JS: `api/Reference_impl.ts` (`ReferenceImpl`, `set`,
/// `update`, `push`, `runTransaction`); Android: `DatabaseReference.java`.
library;

import 'package:firebase_database_dart/src/api/on_disconnect.dart';
import 'package:firebase_database_dart/src/api/query.dart';
import 'package:firebase_database_dart/src/api/transaction_handler.dart';
import 'package:firebase_database_dart/src/api/transaction_result.dart';
import 'package:meta/meta.dart';

// Imported for the references in the documentation below.
import 'package:firebase_database_dart/src/api/firebase_database.dart';

/// A location in the database. Creating one makes no request.
///
/// Get one from [FirebaseDatabase.ref], and walk with [child], [parent] and [root]. As a [Query] it reads and
/// listens; it also writes.
///
/// Writes. A write's local events are queued before its Future completes, so listeners see it at once,
/// offline too. The Future completes when the server answers; while offline it stays pending, not failed. A
/// refused write rolls back with events, then fails (for example `permission-denied`). Writes are at least
/// once: a write whose acknowledgement was lost is sent again after reconnecting.
///
/// Values. A value is null, a `bool`, a `num`, a `String`, a `List` or a `Map` with `String` keys, at any
/// depth, or a `ServerValue`. The client checks it at the call, with the JS SDK's rules, and throws an
/// [ArgumentError] for a key with forbidden characters (`.`, `#`, `$`, `[`, `]`, `/` or control characters),
/// a path deeper than 32 segments or longer than 768 bytes, NaN or Infinity, a priority that is not null, a
/// `num` or a `String`, a leaf over 10 MB, a map key that is not a `String`, or a lone surrogate in a string
/// or key. A `List` is written as a map with index keys. A `-0.0` is sent as 0. Writes under `.info` throw
/// an [ArgumentError].
///
/// ```dart
/// final DatabaseReference post = db.ref('posts').push();
/// await post.set(<String, Object?>{'title': 'Hello', 'at': ServerValue.timestamp});
/// await post.update(<String, Object?>{'stats/views': 0});
/// ```
final class DatabaseReference extends Query {
  /// Creates the reference for the default query [spec] of [database]. Use [FirebaseDatabase.ref] instead.
  @internal
  const DatabaseReference.internal(super.database, super.spec)
    : super.internal();

  /// The last segment of the path, or null at the root.
  String? get key => throw UnimplementedError();

  /// The reference one level up, or null at the root.
  DatabaseReference? get parent => throw UnimplementedError();

  /// The root of the database.
  DatabaseReference get root => throw UnimplementedError();

  /// The reference at [path] below this one. [path] may have several segments; empty segments are dropped,
  /// so `child('a//b')` is `child('a/b')`. Throws an [ArgumentError] for an invalid key.
  DatabaseReference child(String path) => throw UnimplementedError();

  /// A new child with a unique key made on this device, ordered by creation time. It only makes the
  /// reference: nothing is written until you call [set] on it.
  ///
  /// ```dart
  /// await db.ref('messages').push().set(<String, Object?>{'text': 'hi'});
  /// ```
  DatabaseReference push() => throw UnimplementedError();

  /// Replaces the data at this location with [value], and its priority with [priority] when given. A
  /// `null` [value] removes the data. Fires local events before the Future completes; see the class
  /// documentation for completion, rollback and value rules.
  Future<void> set(Object? value, {Object? priority}) {
    // TODO(repo): normalise numbers with normalizeUserNumber (core/util/numbers.dart) before the write
    // leaves the API, so a -0.0 written by the user is sent as 0.
    throw UnimplementedError();
  }

  /// Writes each entry of [values] below this location, leaving other children alone. Keys may be
  /// multi-segment paths (`'a/b'`), which makes one atomic write to several places; a `null` value removes
  /// that child. Two keys where one is a prefix of the other throw an [ArgumentError].
  Future<void> update(Map<String, Object?> values) {
    // TODO(repo): normalise numbers with normalizeUserNumber (core/util/numbers.dart) before the write
    // leaves the API, so a -0.0 written by the user is sent as 0.
    throw UnimplementedError();
  }

  /// Sets the priority of this location: null, a `num` or a `String`.
  Future<void> setPriority(Object? priority) {
    // TODO(repo): normalise numbers with normalizeUserNumber (core/util/numbers.dart) before the write
    // leaves the API, so a -0.0 written by the user is sent as 0.
    throw UnimplementedError();
  }

  /// Removes the data at this location: the same as `set(null)`.
  Future<void> remove() => throw UnimplementedError();

  /// Atomically changes the data at this location with [handler].
  ///
  /// The handler's first run happens in a microtask after this call returns, never inside it; it may run
  /// again when the server's value differs (see [TransactionHandler]). With [applyLocally] each run raises
  /// local events, which a later run or an abort may revert; with [applyLocally] false there are no local
  /// events before the server answers.
  ///
  /// Completes with `committed` true when the server took the value, or false when the handler aborted.
  /// Fails with the handler's own error when it throws, `max-retries` after more than 25 runs,
  /// `disconnected` when the connection drops after the value was sent, `overridden-by-set` when a later
  /// [set] replaces it, and `write-canceled` after [FirebaseDatabase.purgeOutstandingWrites]. Transactions
  /// are kept in memory only, also with persistence.
  ///
  /// ```dart
  /// final TransactionResult r = await db.ref('seats/left').runTransaction((Object? v) {
  ///   final int left = (v as int?) ?? 0;
  ///   return left == 0 ? Transaction.abort() : Transaction.success(left - 1);
  /// });
  /// ```
  Future<TransactionResult> runTransaction(
    TransactionHandler handler, {
    bool applyLocally = true,
  }) {
    // TODO(repo): normalise numbers with normalizeUserNumber (core/util/numbers.dart) on each value the
    // handler returns, before the write leaves the API, so a -0.0 written by the user is sent as 0.
    throw UnimplementedError();
  }

  /// The writes the server applies at this location when this client disconnects.
  OnDisconnect get onDisconnect => throw UnimplementedError();
}
