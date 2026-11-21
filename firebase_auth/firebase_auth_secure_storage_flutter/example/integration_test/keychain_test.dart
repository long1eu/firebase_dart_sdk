// SecureAuthStorage against the real data-protection keychain of macOS, in an
// app signed with a provisioning profile that grants keychain-access-groups.
//
//   flutter test integration_test -d macos
//
// Every key written here contains the id of the run, and the last test checks
// that none is left in the keychain.

import 'dart:io';
import 'dart:math';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_auth_secure_storage_flutter/firebase_auth_secure_storage_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final String run =
      'it-${DateTime.now().microsecondsSinceEpoch}-'
      '${Random.secure().nextInt(1 << 32).toRadixString(16)}';
  // The same keychain service as every SecureAuthStorage with the default
  // storage, read and written without a namespace.
  final FlutterSecureStorage keychain =
      SecureAuthStorage.defaultSecureStorage();
  final String key = 'firebase_auth_providers_dart:$run';
  // About the size of a real session: a user record and two tokens.
  final String session =
      '{"uid":"$run","name":"Zoë 测试 🔐",'
      '"idToken":"${'a' * 1200}","refreshToken":"${'r' * 300}"}';
  late Directory temp;

  String namespace(String name) => 'firebase_auth_secure_storage_it:$run:$name';

  Future<List<String>> keysOfThisRun() async => (await keychain.readAll()).keys
      .where((String k) => k.contains(run))
      .toList();

  setUpAll(() async {
    expect(Platform.isMacOS, isTrue, reason: 'these tests need macOS');
    temp = await Directory.systemTemp.createTemp('secure_storage_it');
  });

  tearDownAll(() async {
    // Only after a failed test: the last test reports what was left.
    for (final String k in await keysOfThisRun()) {
      await keychain.delete(key: k);
    }
    await temp.delete(recursive: true);
  });

  testWidgets('the default storage is the data-protection keychain', (_) async {
    expect(keychain.mOptions.toMap()['usesDataProtectionKeychain'], 'true');
    // Without the keychain-access-groups entitlement this write fails with
    // errSecMissingEntitlement (-34018), as a SecureAuthStorageException.
    final SecureAuthStorage storage = SecureAuthStorage();
    await storage.write(key, session);
    expect(await storage.read(key), session);
    expect(await keychain.read(key: storage.storageKeyFor(key)), session);
    await storage.write(key, null);
    expect(await storage.read(key), isNull);
  });

  testWidgets('a session round-trips, is replaced and is deleted', (_) async {
    final SecureAuthStorage storage = SecureAuthStorage(
      namespace: namespace('roundtrip'),
    );
    expect(await storage.read(key), isNull);

    await storage.write(key, session);
    expect(await storage.read(key), session);
    expect(await keychain.read(key: storage.storageKeyFor(key)), session);

    await storage.write(key, '{"uid":"next"}');
    expect(await storage.read(key), '{"uid":"next"}');

    await storage.write(key, null);
    expect(await storage.read(key), isNull);
    expect(await keychain.read(key: storage.storageKeyFor(key)), isNull);
  });

  testWidgets('two namespaces keep the same key apart', (_) async {
    final SecureAuthStorage a = SecureAuthStorage(namespace: namespace('a'));
    final SecureAuthStorage b = SecureAuthStorage(namespace: namespace('b'));

    await a.write(key, 'session of a');
    expect(await b.read(key), isNull);
    await b.write(key, 'session of b');
    expect(await a.read(key), 'session of a');
    expect(await b.read(key), 'session of b');

    await a.write(key, null);
    expect(await a.read(key), isNull);
    expect(await b.read(key), 'session of b');
    await b.write(key, null);
    expect(await b.read(key), isNull);
  });

  testWidgets('a session in a FileAuthStorage moves to the keychain', (
    _,
  ) async {
    final String path = '${temp.path}/move.json';
    final FileAuthStorage file = FileAuthStorage(path);
    await file.write(key, session);
    final List<SecureAuthStorageMigrationIssue> issues =
        <SecureAuthStorageMigrationIssue>[];
    final SecureAuthStorage storage = SecureAuthStorage(
      namespace: namespace('move'),
      migrateFrom: file,
      onMigrationIssue: issues.add,
    );

    expect(await storage.read(key), session);
    expect(issues, isEmpty);
    expect(await keychain.read(key: storage.storageKeyFor(key)), session);
    expect(await file.read(key), isNull);
    // The file goes with its last key.
    expect(File(path).existsSync(), isFalse);

    // The next start reads it from the keychain alone.
    final SecureAuthStorage next = SecureAuthStorage(
      namespace: namespace('move'),
    );
    expect(await next.read(key), session);
    await next.write(key, null);
    expect(await next.read(key), isNull);
  });

  testWidgets(
    'a session already in the keychain wins over the file, and a sign-out '
    'deletes both',
    (_) async {
      final String path = '${temp.path}/both.json';
      final FileAuthStorage file = FileAuthStorage(path);
      await file.write(key, 'older session in the file');
      await SecureAuthStorage(namespace: namespace('both')).write(key, session);
      final List<SecureAuthStorageMigrationIssue> issues =
          <SecureAuthStorageMigrationIssue>[];
      final SecureAuthStorage storage = SecureAuthStorage(
        namespace: namespace('both'),
        migrateFrom: file,
        onMigrationIssue: issues.add,
      );

      expect(await storage.read(key), session);
      expect(await file.read(key), 'older session in the file');

      await storage.write(key, null);
      expect(issues, isEmpty);
      expect(await storage.read(key), isNull);
      expect(await keychain.read(key: storage.storageKeyFor(key)), isNull);
      expect(await file.read(key), isNull);
      expect(File(path).existsSync(), isFalse);
    },
  );

  testWidgets('no entry of this run is left in the keychain', (_) async {
    expect(await keysOfThisRun(), isEmpty);
  });
}
