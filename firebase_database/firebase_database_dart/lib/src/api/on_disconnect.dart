/// Writes the server applies when the client disconnects. JS: `api/OnDisconnect.ts`; Android:
/// `OnDisconnect.java`.
library;

import 'package:firebase_database_dart/src/api/database_reference.dart';
import 'package:meta/meta.dart';

/// Writes the server applies to one location when this client's connection ends, from
/// `DatabaseReference.onDisconnect`.
///
/// Each Future completes when the server has registered the write. Only registered writes count: when the
/// connection is lost, the client also applies them locally, raising events after the `.info/connected`
/// false event, and then forgets them. Registrations are never persisted; after a restart, register them
/// again when `FirebaseDatabase.onConnected` turns true.
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
  Future<void> set(Object? value, {Object? priority}) {
    // TODO(repo): normalise numbers with normalizeUserNumber (core/util/numbers.dart) before the write
    // leaves the API, so a -0.0 written by the user is sent as 0.
    throw UnimplementedError();
  }

  /// On disconnect, writes each entry of [values] below the location, leaving other children alone. Keys
  /// may be multi-segment paths (`'a/b'`).
  Future<void> update(Map<String, Object?> values) {
    // TODO(repo): normalise numbers with normalizeUserNumber (core/util/numbers.dart) before the write
    // leaves the API, so a -0.0 written by the user is sent as 0.
    throw UnimplementedError();
  }

  /// On disconnect, removes the location's data: the same as `set(null)`.
  Future<void> remove() => throw UnimplementedError();

  /// Cancels every onDisconnect write registered at this location and below it.
  Future<void> cancel() => throw UnimplementedError();
}
