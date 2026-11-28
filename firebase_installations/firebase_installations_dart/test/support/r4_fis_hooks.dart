/// Helpers of `installations_r4_test.dart`: a view of a shared [MemoryKeyValueStore] that runs a hook
/// after each update and can hold the next update until a gate opens, so a test can act between two
/// store calls of one operation (another instance writes, another operation of the same instance runs).
///
/// Create it inside `fakeAsync`, so its gates live in that zone.
library;

import 'dart:async';

import 'package:firebase_installations_dart/firebase_installations_dart.dart';

/// A view of [inner] with a hook after each update and a one-shot hold before the next update.
final class R4HookStore implements KeyValueStore {
  /// A view of [inner].
  R4HookStore(this.inner);

  /// The store shared with the other instances.
  final MemoryKeyValueStore inner;

  /// Called after each update with the value it left (null when the update removed the key).
  void Function(String key, String? value)? afterUpdate;

  /// When set, the next update waits for it before it runs; it is cleared when that update starts.
  Future<void>? holdNextUpdate;

  /// How many updates waited for [holdNextUpdate].
  int held = 0;

  @override
  Future<String?> read(String key) => inner.read(key);

  @override
  Future<void> write(String key, String? value) => inner.write(key, value);

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) async {
    final Future<void>? hold = holdNextUpdate;
    if (hold != null) {
      holdNextUpdate = null;
      held++;
      await hold;
    }
    final String? value = await inner.update(key, transform);
    afterUpdate?.call(key, value);
    return value;
  }

  @override
  Stream<String> get changes => const Stream<String>.empty();

  @override
  Future<void> close() => inner.close();
}
