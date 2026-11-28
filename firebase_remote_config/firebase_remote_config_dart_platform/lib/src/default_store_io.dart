import 'dart:io';

import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/io.dart';
import 'package:path_provider/path_provider.dart';

/// The default store on the VM: a `FileKeyValueStore` in `firebase_dart`
/// under the application support directory.
KeyValueStore createDefaultStore() => ApplicationSupportStore();

/// A [KeyValueStore] that finds the application support directory on first
/// use, then forwards every call to a `FileKeyValueStore` in its
/// `firebase_dart` subdirectory.
///
/// `getApplicationSupportDirectory` is asynchronous and the store is needed
/// synchronously, when the per-app instance is created. A failure to find the
/// directory is thrown by the calls waiting for it, and the next call tries
/// again. The file store's own failures (the directory is in use by another
/// process, or not private to the user) are thrown by every call. After
/// [close], every call throws a [StateError] and no file store is opened
/// again, as `FileKeyValueStore` does.
final class ApplicationSupportStore implements KeyValueStore {
  Future<KeyValueStore>? _store;

  Future<void>? _closing;

  Future<KeyValueStore> get _opened {
    if (_closing != null) {
      return Future<KeyValueStore>.error(
        StateError('The ApplicationSupportStore was closed.'),
      );
    }
    final Future<KeyValueStore>? existing = _store;
    if (existing != null) {
      return existing;
    }
    final Future<KeyValueStore> opening = _open();
    _store = opening;
    opening.then<void>(
      (KeyValueStore _) {},
      onError: (Object _) {
        if (identical(_store, opening)) {
          _store = null;
        }
      },
    );
    return opening;
  }

  static Future<KeyValueStore> _open() async {
    final Directory support = await getApplicationSupportDirectory();
    return FileKeyValueStore(
      '${support.path}${Platform.pathSeparator}firebase_dart',
    );
  }

  @override
  Future<String?> read(String key) async => (await _opened).read(key);

  @override
  Future<void> write(String key, String? value) async =>
      (await _opened).write(key, value);

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) async => (await _opened).update(key, transform);

  /// Never emits: the file store cannot tell when another writer changed a
  /// key.
  @override
  Stream<String> get changes => const Stream<String>.empty();

  /// Closes the file store if it was opened, and refuses every later call.
  /// Every call of `close` completes when that is done. A failed attempt to
  /// find the directory is not thrown again here: the calls that waited for
  /// it reported it.
  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    final Future<KeyValueStore>? opening = _store;
    if (opening == null) {
      return;
    }
    final KeyValueStore store;
    try {
      store = await opening;
    } on Object {
      return;
    }
    await store.close();
  }
}
