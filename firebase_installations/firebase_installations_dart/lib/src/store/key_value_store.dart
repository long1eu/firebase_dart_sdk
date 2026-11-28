import 'dart:async';

/// The persistent key-value storage that `FirebaseInstallations` (and Remote Config, through
/// `FirebaseInstallations.store`) writes its records to.
///
/// Create one per process (VM) or per page (web) and give it to every `FirebaseInstallations`: records
/// are keyed by app, so several apps can share it. The package has three: [MemoryKeyValueStore] (all
/// platforms, nothing survives the process), `FileKeyValueStore` (`package:firebase_installations_dart/io.dart`)
/// and `IndexedDbKeyValueStore` (`package:firebase_installations_dart/web.dart`).
///
/// Implementations must make [write] all-or-nothing and [update] atomic with respect to every other
/// update of the same key through the store.
abstract interface class KeyValueStore {
  /// The value stored under [key], or null when there is none.
  Future<String?> read(String key);

  /// Stores [value] under [key], all or nothing; a null [value] removes the key.
  Future<void> write(String key, String? value);

  /// Reads [key], calls [transform] synchronously, writes its result (null removes), returns it.
  ///
  /// Atomic with respect to every other update of [key] through this store, and, for IndexedDB,
  /// through every store over the same database. [transform] must not await and treats a value it
  /// cannot decode as absent. When [transform] throws, nothing is written and the error is rethrown.
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  );

  /// Keys changed by another writer where the storage can tell: IndexedDB emits; memory and file stores
  /// never emit. A hint to read again; it carries no value.
  Stream<String> get changes;

  /// Releases the store. Later calls fail.
  Future<void> close();
}

/// A [KeyValueStore] in memory: nothing survives the process.
///
/// A new installation is created at every process start, which the Firebase console counts as a new
/// installation each time. Use it for tests and short-lived tools; `FirebaseInstallations` logs one
/// warning when it registers an installation in it.
final class MemoryKeyValueStore implements KeyValueStore {
  /// An empty store.
  MemoryKeyValueStore();

  final Map<String, String> _values = <String, String>{};
  Future<void> _last = Future<void>.value();
  bool _closed = false;

  @override
  Future<String?> read(String key) => _run(() => _values[key]);

  @override
  Future<void> write(String key, String? value) => _run(() => _put(key, value));

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) => _run(() {
    final String? next = transform(_values[key]);
    _put(key, next);
    return next;
  });

  @override
  Stream<String> get changes => const Stream<String>.empty();

  @override
  Future<void> close() async {
    _closed = true;
  }

  void _put(String key, String? value) {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  /// Runs [action] after every earlier call, in order.
  Future<T> _run<T>(T Function() action) {
    final Future<T> next = _last.then((_) {
      if (_closed) {
        throw StateError('The MemoryKeyValueStore was closed.');
      }
      return action();
    });
    _last = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }
}
