// What the test files share: the fake backend, the store, the registration
// and new apps.

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart'
    show FirebaseInstallationsException;
import 'package:firebase_remote_config_dart_platform/firebase_remote_config_dart_platform.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';

/// An API key of the shape Installations accepts (`A` and 38 more).
const String apiKey = 'AIzaSyDart00000000000000000000000000000';

const String projectId = 'demo-unit';

/// The language the harness passes to `use`.
const String languageCode = 'ro-RO';

const FirebaseOptions options = FirebaseOptions(
  apiKey: apiKey,
  appId: '1:1:web:1',
  messagingSenderId: '1',
  projectId: projectId,
);

final FakeBackend backend = FakeBackend();

/// The store of every app: a [MemoryKeyValueStore], new for each test, that
/// a test can make fail.
final FailingStore store = FailingStore(MemoryKeyValueStore());

/// Gives [store] a new [MemoryKeyValueStore] created in the current zone.
///
/// `setUp` does it for every test. A `testWidgets` body calls it again
/// first: the memory store chains its calls on a future, and a future that
/// completed in another zone hands its listeners to that zone's microtask
/// queue, which the fake clock of `testWidgets` never runs; the store would
/// stall there, and every later test with it.
void freshStore() {
  store.inner = MemoryKeyValueStore();
}

int _apps = 0;

/// A new app, so that every test starts with fresh instances and settings.
Future<FirebaseApp> newApp({FirebaseOptions appOptions = options}) =>
    Firebase.initializeApp(name: 'app${_apps++}', options: appOptions);

/// Registers the package against [backend] and [store], with the Dart core.
void registerForTests() {
  setUpAll(() {
    FirebaseRemoteConfigDart.use(
      store: store,
      httpClient: backend.client,
      languageCode: languageCode,
      useDartCore: true,
    );
  });
  setUp(() {
    backend.reset();
    freshStore();
    store.failure = null;
  });
}

/// Throws a [FirebaseException] of `firebase_core` (not the client's) with
/// the plugin `firebase_remote_config` and [code].
Matcher throwsRemoteConfigCode(String code) =>
    throwsA(isRemoteConfigCode(code));

TypeMatcher<FirebaseException> isRemoteConfigCode(String code) =>
    isA<FirebaseException>()
        .having(
          (FirebaseException e) => e.plugin,
          'plugin',
          'firebase_remote_config',
        )
        .having((FirebaseException e) => e.code, 'code', code)
        .having(
          (FirebaseException e) => e,
          'not the client exception',
          isNot(isA<dart_app.FirebaseException>()),
        );

/// A [KeyValueStore] over [inner] whose calls throw [failure] while it is
/// set.
class FailingStore implements KeyValueStore {
  FailingStore(this.inner);

  /// The store the calls go to.
  KeyValueStore inner;

  /// What every call throws; null lets them through.
  Exception? failure;

  /// The failure the file store reports when another process holds its
  /// directory.
  static const FirebaseInstallationsException inUse =
      FirebaseInstallationsException(
        code: 'storage-error',
        message: 'the store directory is in use by another process',
      );

  void _check() {
    final Exception? error = failure;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<String?> read(String key) async {
    _check();
    return inner.read(key);
  }

  @override
  Future<void> write(String key, String? value) async {
    _check();
    return inner.write(key, value);
  }

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) async {
    _check();
    return inner.update(key, transform);
  }

  @override
  Stream<String> get changes => inner.changes;

  @override
  Future<void> close() => inner.close();
}
