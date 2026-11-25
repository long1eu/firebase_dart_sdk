/// A location in the database, to read and write. JS: `api/Reference_impl.ts` (`ReferenceImpl`, `set`,
/// `update`, `push`, `runTransaction`); Android: `DatabaseReference.java`.
library;

import 'package:firebase_database_dart/src/api/data_snapshot.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart';
import 'package:firebase_database_dart/src/api/on_disconnect.dart';
import 'package:firebase_database_dart/src/api/query.dart';
import 'package:firebase_database_dart/src/api/transaction.dart';
import 'package:firebase_database_dart/src/api/transaction_handler.dart';
import 'package:firebase_database_dart/src/api/transaction_result.dart';
import 'package:firebase_database_dart/src/api/user_value.dart';
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/transaction_data.dart';
import 'package:firebase_database_dart/src/core/util/validation.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:meta/meta.dart';

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
  String? get key => spec.path.back?.name;

  /// The reference one level up, or null at the root.
  DatabaseReference? get parent {
    final Path? parentPath = spec.path.parent;
    return parentPath == null
        ? null
        : DatabaseReference.internal(database, QuerySpec.defaultAt(parentPath));
  }

  /// The root of the database.
  DatabaseReference get root => database.ref();

  /// The reference at [path] below this one. [path] may have several segments; empty segments are dropped,
  /// so `child('a//b')` is `child('a/b')`. Throws an [ArgumentError] for an invalid key.
  DatabaseReference child(String path) {
    if (spec.path.isEmpty) {
      validateRootPathString('child', 'path', path);
    } else {
      validatePathString('child', 'path', path);
    }
    return DatabaseReference.internal(
      database,
      QuerySpec.defaultAt(spec.path.childPath(Path(path))),
    );
  }

  /// A new child with a unique key made on this device, ordered by creation time. It only makes the
  /// reference: nothing is written until you call [set] on it. Throws an [ArgumentError] under
  /// `.info`.
  ///
  /// ```dart
  /// await db.ref('messages').push().set(<String, Object?>{'text': 'hi'});
  /// ```
  DatabaseReference push() {
    validateWritablePath('push', spec.path);
    return DatabaseReference.internal(
      database,
      QuerySpec.defaultAt(spec.path.child(ChildKey(database.nextPushId()))),
    );
  }

  /// Replaces the data at this location with [value], and its priority with [priority] when given.
  /// A `null` [value] removes the data. Fires local events before the Future completes; see the
  /// class documentation for completion, rollback and value rules. With `persistence` the write is
  /// stored on disk and sent again after a restart; the Future of the run that made it is gone
  /// then. The Database emulator refuses, with `unknown`, a [value] whose longest chain of keys
  /// together with this path is longer than 768 bytes; the production server accepted the same
  /// write (measured once on each). A flat multi-path [update] is checked path by path.
  Future<void> set(Object? value, {Object? priority}) =>
      _set('set', value, priority);

  Future<void> _set(String fnName, Object? value, Object? priority) {
    final Path path = spec.path;
    validateWritablePath(fnName, path);
    validateUserValue(fnName, value, path);
    if (priority != null) {
      validateNotReadOnlyKey(fnName, path);
      validateUserPriority(fnName, priority);
    }
    final Node node = userValueNode(value, priority);
    return database.write(
      (Repo repo, WriteCompletion done) =>
          repo.setValue(path, node, onComplete: done),
    );
  }

  /// Writes each entry of [values] below this location, leaving other children alone. Keys may be
  /// multi-segment paths (`'a/b'`), which makes one atomic write to several places; a `null` value removes
  /// that child. Two keys where one is a prefix of the other throw an [ArgumentError].
  ///
  /// An empty [values] map writes nothing and completes the Future in a microtask, with no request.
  Future<void> update(Map<String, Object?> values) {
    final Path path = spec.path;
    validateWritablePath('update', path);
    validateUserMerge('update', values, path);
    final Map<String, Object?> normalized =
        normalizeUserValue(values)! as Map<String, Object?>;
    final CompoundWrite write = CompoundWrite.fromValue(normalized);
    return database.write(
      (Repo repo, WriteCompletion done) =>
          repo.updateChildren(path, write, normalized, onComplete: done),
    );
  }

  /// Sets the priority of this location: null, a `num` or a `String`. With `persistence` the write
  /// is stored on disk and sent again after a restart; the Future of the run that made it is gone
  /// then.
  Future<void> setPriority(Object? priority) {
    final Path path = spec.path;
    validateWritablePath('setPriority', path);
    validateUserPriority('setPriority', priority);
    final Path priorityPath = path.child(ChildKey.priority);
    final Node node = userValueNode(priority);
    return database.write(
      (Repo repo, WriteCompletion done) =>
          repo.setValue(priorityPath, node, onComplete: done),
    );
  }

  /// Removes the data at this location: the same as `set(null)`.
  Future<void> remove() => _set('remove', null, null);

  /// Atomically changes the data at this location with [handler].
  ///
  /// The handler's first run happens inside this call, on the value the client holds, as in the JS and
  /// Android SDKs, so a [set] made right after this call comes after the transaction. Events and the Future
  /// still wait for a later microtask. While the database is still opening its persistence, the first run
  /// happens once it has opened. The handler returns a [Transaction], never a `Future`: it cannot wait. It
  /// may run again when the server's value differs (see [TransactionHandler]). A write the handler makes to
  /// this location, above or below it aborts this transaction with `overridden-by-set`. With
  /// [applyLocally] each run raises local events, which a later run or an abort may revert; with
  /// [applyLocally] false there are no local events before the server answers.
  ///
  /// Completes with `committed` true when the server took the value, or false when the handler
  /// aborted. Fails with the handler's own error when it throws, `max-retries` when the handler has
  /// run 25 times and the server still refuses the value, `disconnected` when the connection drops
  /// after the value was sent, `overridden-by-set` when a later [set] replaces it, and
  /// `write-canceled` after [FirebaseDatabase.purgeOutstandingWrites]. While offline the handler
  /// runs on the local value (with [applyLocally] its result raises local events) and the Future
  /// stays pending until the connection returns; there is no timeout. Transactions are kept in
  /// memory only, also with persistence.
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
    const String fnName = 'runTransaction';
    final Path path = spec.path;
    validateWritablePath(fnName, path);
    validateNotReadOnlyKey(fnName, path);

    // The handler's own error (or an invalid value it returned) fails the Future as it is; the
    // transaction aborts.
    Object? thrown;
    StackTrace? thrownStackTrace;

    TransactionOutcome update(Object? currentValue) {
      try {
        final Transaction result = handler(currentValue);
        if (result.aborted) {
          return TransactionOutcome.abort;
        }
        validateUserValue(fnName, result.value, path);
        final Object? priority = result.priority;
        if (priority != null) {
          validateUserPriority(fnName, priority);
        }
        final Object? value = normalizeUserValue(result.value);
        return TransactionSuccess(
          priority == null
              ? value
              : <String, Object?>{
                  '.value': value,
                  '.priority': normalizeUserValue(priority),
                },
        );
      } on Object catch (error, stackTrace) {
        thrown = error;
        thrownStackTrace = stackTrace;
        return TransactionOutcome.abort;
      }
    }

    return database.request<TransactionResult>((
      Repo repo,
      void Function(TransactionResult) complete,
      void Function(Object, [StackTrace?]) fail,
    ) {
      repo.startTransaction(
        path,
        update,
        applyLocally: applyLocally,
        onComplete: (DatabaseError? error, bool committed, Node? node) {
          final Object? handlerError = thrown;
          if (handlerError != null) {
            fail(handlerError, thrownStackTrace);
          } else if (error != null) {
            fail(toApiError(error));
          } else {
            complete(
              TransactionResult.internal(
                committed: committed,
                snapshot: DataSnapshot.internal(
                  this,
                  node ?? ChildrenNode.empty,
                  priorityIndex,
                ),
              ),
            );
          }
        },
      );
    });
  }

  /// The writes the server applies at this location when this client disconnects.
  OnDisconnect get onDisconnect => OnDisconnect.internal(this);
}
