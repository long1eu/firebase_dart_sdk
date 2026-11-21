import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth_secure_storage_dart/firebase_auth_secure_storage_dart.dart';
import 'package:firebase_auth_secure_storage_dart/src/windows/dpapi_store.dart';
import 'package:test/test.dart';

const String _account =
    'firebase_auth_secure_storage:abc/firebase_auth_providers_dart:key';
const String _secret = '{"refreshToken":"secret-refresh-token","ünïcode":"✓"}';

/// A stand-in for DPAPI: the blob is the entropy's length, the entropy and
/// the data XOR 0x5A; a blob unprotected with another entropy fails as
/// DPAPI does (`ERROR_INVALID_DATA`).
class _FakeCipher implements DpapiCipher {
  int protects = 0;
  SecretStoreError? failure;

  @override
  Uint8List protect(Uint8List data, Uint8List entropy) {
    protects++;
    final SecretStoreError? failure = this.failure;
    if (failure != null) {
      throw failure;
    }
    return Uint8List.fromList(<int>[
      entropy.length,
      ...entropy,
      for (final int byte in data) byte ^ 0x5A,
    ]);
  }

  @override
  Uint8List unprotect(Uint8List blob, Uint8List entropy) {
    final int length = blob[0];
    final List<int> stored = blob.sublist(1, 1 + length);
    if (!_same(stored, entropy)) {
      throw const SecretStoreError(
        function: 'CryptUnprotectData',
        status: 13,
        message: 'Win32 error 13',
      );
    }
    return Uint8List.fromList(<int>[
      for (final int byte in blob.sublist(1 + length)) byte ^ 0x5A,
    ]);
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

void main() {
  late Directory root;
  late String dir;
  late _FakeCipher cipher;
  late DpapiSecretStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ssd_dpapi');
    dir = '${root.path}${Platform.pathSeparator}firebase_auth_secure_storage';
    cipher = _FakeCipher();
    store = DpapiSecretStore(directory: () => dir, cipher: cipher);
  });

  tearDown(() => root.delete(recursive: true));

  test(
    'the constructor resolves nothing; the first call creates the directory',
    () async {
      int resolved = 0;
      final DpapiSecretStore lazy = DpapiSecretStore(
        directory: () {
          resolved++;
          return dir;
        },
        cipher: cipher,
      );
      expect(resolved, 0);
      expect(Directory(dir).existsSync(), isFalse);
      await lazy.write(_account, _secret);
      await lazy.read(_account);
      expect(resolved, 1);
      expect(Directory(dir).existsSync(), isTrue);
    },
  );

  test('round trip, including non-ASCII text', () async {
    expect(await store.read(_account), isNull);
    await store.write(_account, _secret);
    expect(await store.read(_account), _secret);
  });

  test(
    'one file per account, named by a hash, without the plain text',
    () async {
      await store.write(_account, _secret);
      await store.write('other', 'x');
      final List<FileSystemEntity> files = Directory(dir).listSync();
      expect(files, hasLength(2));
      final File file = File(store.fileOf(_account));
      expect(file.existsSync(), isTrue);
      expect(file.path, matches(RegExp(r'[0-9a-f]{32}\.dpapi$')));
      expect(file.path, isNot(contains(':')));
      final String raw = latin1.decode(file.readAsBytesSync());
      expect(raw, isNot(contains('secret-refresh-token')));
    },
  );

  test('a write replaces the value and leaves no temporary file', () async {
    await store.write(_account, 'first');
    await store.write(_account, 'second');
    expect(await store.read(_account), 'second');
    expect(Directory(dir).listSync(), hasLength(1));
  });

  test('delete removes the file; deleting nothing succeeds', () async {
    await store.write(_account, _secret);
    await store.delete(_account);
    expect(await store.read(_account), isNull);
    expect(File(store.fileOf(_account)).existsSync(), isFalse);
    await store.delete(_account);
    await store.delete('never written');
  });

  test('a file moved onto another account does not decrypt', () async {
    await store.write(_account, _secret);
    File(store.fileOf(_account)).renameSync(store.fileOf('another'));
    await expectLater(
      store.read('another'),
      throwsA(
        isA<SecretStoreError>()
            .having(
              (SecretStoreError e) => e.function,
              'function',
              'CryptUnprotectData',
            )
            .having(
              (SecretStoreError e) => '$e',
              'text',
              isNot(contains('secret')),
            ),
      ),
    );
  });

  test('a failed encryption writes nothing', () async {
    cipher.failure = const SecretStoreError(
      function: 'CryptProtectData',
      status: 5,
      message: 'access denied',
    );
    await expectLater(
      store.write(_account, _secret),
      throwsA(isA<SecretStoreError>()),
    );
    expect(Directory(dir).existsSync(), isFalse);
  });

  test(
    'a file that cannot be read is a SecretStoreError, not a null',
    () async {
      Directory(store.fileOf(_account)).createSync(recursive: true);
      await expectLater(
        store.read(_account),
        throwsA(
          isA<SecretStoreError>().having(
            (SecretStoreError e) => e.function,
            'function',
            'File.read',
          ),
        ),
      );
    },
  );

  test('a directory that cannot be resolved fails the call', () async {
    final DpapiSecretStore broken = DpapiSecretStore(
      directory: () => throw const SecretStoreError(
        function: 'LOCALAPPDATA',
        message: 'not set',
      ),
      cipher: cipher,
    );
    await expectLater(broken.read(_account), throwsA(isA<SecretStoreError>()));
  });

  test('decrypted bytes that are not UTF-8 fail without the bytes', () async {
    final File file = File(store.fileOf(_account));
    file.parent.createSync(recursive: true);
    final Uint8List entropy = utf8.encode(_account);
    file.writeAsBytesSync(<int>[
      entropy.length,
      ...entropy,
      0xFF ^ 0x5A,
      0xFE ^ 0x5A,
    ]);
    await expectLater(
      store.read(_account),
      throwsA(
        isA<SecretStoreError>().having(
          (SecretStoreError e) => e.message,
          'message',
          'the stored secret is not UTF-8 text',
        ),
      ),
    );
  });
}
