/// Writes the server applies when the client disconnects. JS: `api/OnDisconnect.ts`; Android:
/// `OnDisconnect.java`.
library;

import 'package:firebase_database_dart/src/api/database_reference.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart';
import 'package:firebase_database_dart/src/api/user_value.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/validation.dart';
import 'package:meta/meta.dart';

/// Writes the server applies to one location when this client's connection ends, from
/// `DatabaseReference.onDisconnect`.
///
/// Each Future completes when the server has registered the write. Only registered writes count: when the
/// connection is lost, the client also applies them locally, raising events after the `.info/connected`
/// false event, and then forgets them. Applying them overrides running transactions at, above or below
/// each location as a `DatabaseReference.set` there would (see `DatabaseReference.runTransaction`); a
/// transaction whose value was sent before the drop has failed with `disconnected` by then. Registrations
/// are never persisted; after a restart, register them again when `FirebaseDatabase.onConnected` turns
/// true.
///
/// A Future fails with `permission-denied` when the rules refuse the write, and with `disconnected` when the
/// connection dropped after the request was sent and before the server answered: the registration may not
/// exist then, so register again at the next connect. A request made while offline waits for the
/// connection; it is not failed by a timeout.
///
/// ```dart
/// db.onConnected.listen((bool connected) async {
///   if (!connected) return;
///   final DatabaseReference status = db.ref('status/$uid');
///   await status.onDisconnect.set('offline');
///   await status.set('online');
/// });
/// ```
final class OnDisconnect {
  /// Creates the onDisconnect handle of [reference]. Use `DatabaseReference.onDisconnect` instead.
  @internal
  const OnDisconnect.internal(this.reference);

  /// The location the writes apply to.
  @internal
  final DatabaseReference reference;

  /// On disconnect, replaces the location's data with [value], and its priority with [priority] when
  /// given. Values are validated at the call as in `DatabaseReference.set`.
  Future<void> set(Object? value, {Object? priority}) =>
      _set('OnDisconnect.set', value, priority);

  Future<void> _set(String fnName, Object? value, Object? priority) {
    final Path path = reference.spec.path;
    validateWritablePath(fnName, path);
    validateUserValue(fnName, value, path);
    if (priority != null) {
      validateNotReadOnlyKey(fnName, path);
      validateUserPriority(fnName, priority);
    }
    final Node node = userValueNode(value, priority);
    return reference.database.write(
      (Repo repo, WriteCompletion done) =>
          repo.onDisconnectSetValue(path, node, onComplete: done),
    );
  }

  /// On disconnect, writes each entry of [values] below the location, leaving other children alone. Keys
  /// may be multi-segment paths (`'a/b'`). A key that names the location itself (`''`, `'/'` or any
  /// string of only slashes) throws an [ArgumentError] that names the key, and nothing is
  /// registered; use [set] to replace the location on disconnect, or [remove] to delete it.
  ///
  /// An empty [values] map registers nothing and completes the Future in a microtask, with no
  /// request.
  ///
  /// Keys that create a node and set its priority separately (`{'x/v': 1, 'x/.priority': 3}` with
  /// `x` missing) complete the Future, and the server writes nothing on disconnect (measured on
  /// production and the emulator). Write the node as one object instead,
  /// `{'x': {'v': 1, '.priority': 3}}`.
  Future<void> update(Map<String, Object?> values) {
    const String fnName = 'OnDisconnect.update';
    final Path path = reference.spec.path;
    validateWritablePath(fnName, path);
    validateUserMerge(fnName, values, path);
    final Map<String, Object?> normalized =
        normalizeUserValue(values)! as Map<String, Object?>;
    final Map<Path, Node> children = <Path, Node>{
      for (final MapEntry<String, Object?> entry in normalized.entries)
        Path(entry.key): nodeFromJson(entry.value),
    };
    return reference.database.write(
      (Repo repo, WriteCompletion done) =>
          repo.onDisconnectUpdate(path, children, normalized, onComplete: done),
    );
  }

  /// On disconnect, removes the location's data: the same as `set(null)`.
  Future<void> remove() => _set('OnDisconnect.remove', null, null);

  /// Cancels every onDisconnect write registered at this location and below it. Throws an
  /// [ArgumentError] under `.info`, as [set] does.
  Future<void> cancel() {
    final Path path = reference.spec.path;
    validateWritablePath('OnDisconnect.cancel', path);
    return reference.database.write(
      (Repo repo, WriteCompletion done) =>
          repo.onDisconnectCancel(path, onComplete: done),
    );
  }
}
