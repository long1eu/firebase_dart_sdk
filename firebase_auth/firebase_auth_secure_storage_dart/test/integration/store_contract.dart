import 'dart:io';
import 'dart:math';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_auth_secure_storage_dart/firebase_auth_secure_storage_dart.dart';
import 'package:test/test.dart';

/// The variable that turns on the integration tests, which use the real
/// secret store of the system.
const String integrationVariable = 'FIREBASE_AUTH_SECURE_STORAGE_INTEGRATION';

/// Why the integration tests are skipped, or null when they run.
String? integrationSkip() => Platform.environment[integrationVariable] == '1'
    ? null
    : 'uses the real secret store; set $integrationVariable=1 to run';

/// A service name of its own for one run, so that nothing of the user's is
/// touched: `firebase_auth_secure_storage_test_<16 random hex digits>`.
String randomService() {
  final Random random = Random.secure();
  final String hex = List<String>.generate(
    8,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'firebase_auth_secure_storage_test_$hex';
}

/// The tests every platform store passes against the real system.
///
/// [open] makes the store for a service; [cleanUp] removes what is left of
/// a service after its accounts were deleted (a directory on Windows).
/// [inspect], when given, checks with a tool of the system that the secret
/// of an account is stored where the README says.
void defineStoreContract({
  required SecretStore Function(String service) open,
  Future<void> Function(String service)? cleanUp,
  Future<void> Function(String service, String account, String secret)? inspect,
}) {
  late String service;
  late SecretStore store;
  final Set<String> written = <String>{};

  setUp(() {
    service = randomService();
    store = open(service);
    written.clear();
    // Registered before anything is written, so it runs even when a test
    // fails half way.
    addTearDown(() async {
      for (final String account in written) {
        try {
          await store.delete(account);
        } on Exception catch (e) {
          printOnFailure('could not delete $account of $service: $e');
        }
      }
      await cleanUp?.call(service);
    });
  });

  Future<void> write(String account, String secret) {
    written.add(account);
    return store.write(account, secret);
  }

  test('read of a missing account is null', () async {
    expect(await store.read('missing/account'), isNull);
  });

  test('write, read back, overwrite, delete', () async {
    const String account =
        'firebase_auth_secure_storage:test/firebase_auth_providers_dart:key';
    const String first = '{"version":2,"refreshToken":"first"}';
    await write(account, first);
    expect(await store.read(account), first);
    await inspect?.call(service, account, first);

    final String large = '{"refreshToken":"${'x' * 6000}","name":"ünïcode ✓"}';
    await write(account, large);
    expect(await store.read(account), large);

    await store.delete(account);
    expect(await store.read(account), isNull);
    await store.delete(account);
  });

  test('accounts and services are kept apart', () async {
    await write('a', 'secret a');
    await write('b', 'secret b');
    expect(await store.read('a'), 'secret a');
    expect(await store.read('b'), 'secret b');
    expect(await open(randomService()).read('a'), isNull);
  });

  test(
    'SecureAuthStorage on top: available, and moves a file session',
    () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'ssd_integration',
      );
      addTearDown(() => dir.delete(recursive: true));
      final FileAuthStorage file = FileAuthStorage('${dir.path}/session.json');
      const String key = 'firebase_auth_providers_dart:api-key';
      await file.write(key, '{"version":2}');

      final _RecordingStore recording = _RecordingStore(store, written);
      final SecureAuthStorage storage = SecureAuthStorage(
        namespace: 'integration',
        store: recording,
        migrateFrom: file,
      );
      expect(await storage.isAvailable(), isTrue);
      final List<String> probes = written
          .where((String a) => a.startsWith('integration/.probe-'))
          .toList();
      expect(probes, hasLength(1));
      expect(await store.read(probes.single), isNull);
      expect(await storage.read(key), '{"version":2}');
      expect(await file.read(key), isNull);
      await storage.write(key, null);
      expect(await storage.read(key), isNull);
    },
  );
}

/// A [SecretStore] that adds every account written to [written] (so the
/// teardown deletes it) and passes the calls on to [inner].
class _RecordingStore implements SecretStore {
  _RecordingStore(this.inner, this.written);

  final SecretStore inner;
  final Set<String> written;

  @override
  Future<String?> read(String account) => inner.read(account);

  @override
  Future<void> write(String account, String secret) {
    written.add(account);
    return inner.write(account, secret);
  }

  @override
  Future<void> delete(String account) => inner.delete(account);
}
