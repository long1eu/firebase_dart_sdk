import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth_secure_storage_dart/src/secret_store.dart';
import 'package:firebase_auth_secure_storage_dart/src/secret_text.dart';
import 'package:firebase_auth_secure_storage_dart/src/windows/dpapi_bindings.dart';

/// Encrypts and decrypts for one user: DPAPI on Windows ([Crypt32Cipher]), a
/// fake in tests.
abstract interface class DpapiCipher {
  /// [data] encrypted, bound to [entropy].
  Uint8List protect(Uint8List data, Uint8List entropy);

  /// [blob] decrypted with the same [entropy] it was encrypted with.
  Uint8List unprotect(Uint8List blob, Uint8List entropy);
}

/// A [SecretStore] of files encrypted with DPAPI for the current user, one
/// file per account in a directory of the user.
///
/// A file is named after the first 32 hexadecimal digits of the SHA-256 of
/// its account name, with the extension `.dpapi` (an account name has `:`
/// and `/`, which file names cannot), and holds the DPAPI blob of the UTF-8
/// secret. The account name is the DPAPI entropy, so a file copied or
/// renamed onto another account does not decrypt. A file is written to a
/// temporary file of its own next to its final name
/// (`<name>.<pid>.<random>.tmp`) and then renamed over it, so neither a
/// crash nor two processes writing at once leave half a secret.
///
/// A file that does not decrypt (corrupt, or written by another user) fails
/// the read with a [SecretStoreError] of `CryptUnprotectData`, which is not
/// "unavailable"; the file is left as it is.
///
/// The directory and its files keep the access control of their parent
/// (`%LOCALAPPDATA%` grants only the user, SYSTEM and the administrators).
/// DPAPI protects the files from other users and from a copy of the disk,
/// not from other programs of the same user.
///
/// The file calls are synchronous: they block the isolate briefly.
class DpapiSecretStore implements SecretStore {
  /// A store in [directory], encrypting with [cipher].
  ///
  /// [directory] is resolved at the first call; it may throw a
  /// [SecretStoreError], which that call throws. It is created then when it
  /// does not exist.
  DpapiSecretStore({required String Function() directory, required this.cipher})
    : _directory = directory;

  /// The store of Windows for [service]: `%LOCALAPPDATA%\<service>`,
  /// encrypted with DPAPI. Nothing is loaded or read before the first call.
  factory DpapiSecretStore.forService(String service) {
    Crypt32Cipher? cipher;
    return DpapiSecretStore(
      directory: () => _localAppData(service),
      cipher: _LazyCipher(() => cipher ??= Crypt32Cipher.load()),
    );
  }

  final String Function() _directory;

  /// The encryption of the files.
  final DpapiCipher cipher;

  String? _resolved;

  /// The path of the file of [account].
  String fileOf(String account) {
    final String directory = _resolved ??= _directory();
    final String name = sha256
        .convert(utf8.encode(account))
        .toString()
        .substring(0, 32);
    return '$directory${Platform.pathSeparator}$name.dpapi';
  }

  @override
  Future<String?> read(String account) => Future<String?>(() {
    final File file = File(fileOf(account));
    final Uint8List blob;
    try {
      blob = file.readAsBytesSync();
    } on PathNotFoundException {
      return null;
    } on FileSystemException catch (e) {
      throw _fileError('read', e);
    }
    final Uint8List bytes = cipher.unprotect(blob, _entropy(account));
    try {
      return decodeSecret(bytes, 'CryptUnprotectData');
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  });

  @override
  Future<void> write(String account, String secret) => Future<void>(() {
    final String path = fileOf(account);
    final Uint8List bytes = utf8.encode(secret);
    final Uint8List blob;
    try {
      blob = cipher.protect(bytes, _entropy(account));
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
    final File temporary = File(_temporaryOf(path));
    try {
      temporary.parent.createSync(recursive: true);
      temporary.writeAsBytesSync(blob, flush: true);
      temporary.renameSync(path);
    } on FileSystemException catch (e) {
      _deleteQuietly(temporary);
      throw _fileError('write', e);
    }
  });

  @override
  Future<void> delete(String account) => Future<void>(() {
    try {
      File(fileOf(account)).deleteSync();
    } on PathNotFoundException {
      return;
    } on FileSystemException catch (e) {
      throw _fileError('delete', e);
    }
  });

  static Uint8List _entropy(String account) => utf8.encode(account);

  static final Random _random = Random.secure();

  /// A temporary name next to [path] of this write only:
  /// `<path>.<pid>.<8 random hex digits>.tmp`. Two processes (or two writes)
  /// of the same account never write the same temporary file, so each
  /// rename puts a whole blob in place and the last one wins.
  static String _temporaryOf(String path) {
    final String unique = _random
        .nextInt(1 << 32)
        .toRadixString(16)
        .padLeft(8, '0');
    return '$path.$pid.$unique.tmp';
  }

  /// Deletes the temporary file of a failed write. The write's own error is
  /// what the caller sees; a failure here leaves only an encrypted file,
  /// which the next write of the account replaces.
  static void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } on FileSystemException {
      return;
    }
  }

  static SecretStoreError _fileError(
    String operation,
    FileSystemException e,
  ) => SecretStoreError(
    function: 'File.$operation',
    status: e.osError?.errorCode,
    message:
        '${e.message}: ${e.path ?? 'no path'} (${e.osError?.message ?? 'no OS error'})',
  );

  static String _localAppData(String service) {
    final String? base = Platform.environment['LOCALAPPDATA'];
    if (base == null || base.isEmpty) {
      throw const SecretStoreError(
        function: 'LOCALAPPDATA',
        message: 'the LOCALAPPDATA environment variable is not set',
      );
    }
    return '$base${Platform.pathSeparator}$service';
  }
}

/// A [DpapiCipher] whose real cipher is loaded at its first use.
class _LazyCipher implements DpapiCipher {
  _LazyCipher(this._load);

  final DpapiCipher Function() _load;

  @override
  Uint8List protect(Uint8List data, Uint8List entropy) =>
      _load().protect(data, entropy);

  @override
  Uint8List unprotect(Uint8List blob, Uint8List entropy) =>
      _load().unprotect(blob, entropy);
}
