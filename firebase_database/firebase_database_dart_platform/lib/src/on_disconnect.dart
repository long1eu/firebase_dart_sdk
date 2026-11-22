/// [DartOnDisconnect], the [OnDisconnectPlatform] of this package.
library;

import 'package:firebase_database_dart_platform/src/errors.dart';
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:firebase_database_dart_platform/src/reference.dart';
import 'package:firebase_database_dart_platform/src/values.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart';

/// The implementation of [OnDisconnectPlatform] over the client
/// `DatabaseReference.onDisconnect` of [ref]. Making it creates no
/// client; each operation does (through [DartReference.clientRef]).
///
/// `remove()` is inherited: `set(null)`.
class DartOnDisconnect extends OnDisconnectPlatform {
  /// The on-disconnect operations of [ref] in [database].
  DartOnDisconnect(DartFirebaseDatabase database, DartReference ref)
    : super(database: database, ref: ref);

  /// `OnDisconnectPlatform.ref`, typed: the reference the operations apply
  /// to.
  @override
  DartReference get ref => throw UnimplementedError();

  /// `OnDisconnectPlatform.set`: client `onDisconnect.set` of the
  /// [transformValue] of [value], through [guard].
  @override
  Future<void> set(Object? value) => throw UnimplementedError();

  /// `OnDisconnectPlatform.setWithPriority`: client
  /// `onDisconnect.set(transformValue(value), priority: priority)` through
  /// [guard].
  @override
  Future<void> setWithPriority(Object? value, Object? priority) =>
      throw UnimplementedError();

  /// `OnDisconnectPlatform.update`: client
  /// `onDisconnect.update(transformValue(value) as Map<String, Object?>)`
  /// through [guard].
  @override
  Future<void> update(Map<String, Object?> value) => throw UnimplementedError();

  /// `OnDisconnectPlatform.cancel`: client `onDisconnect.cancel()` through
  /// [guard].
  @override
  Future<void> cancel() => throw UnimplementedError();
}
