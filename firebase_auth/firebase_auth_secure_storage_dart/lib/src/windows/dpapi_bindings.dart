import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:firebase_auth_secure_storage_dart/src/secret_store.dart';
import 'package:firebase_auth_secure_storage_dart/src/windows/dpapi_store.dart';

/// `CRYPTPROTECT_UI_FORBIDDEN`: fail instead of showing a prompt.
const int _uiForbidden = 0x1;

/// `DATA_BLOB` (`CRYPT_INTEGER_BLOB`).
final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _ProtectC =
    Int32 Function(
      Pointer<_DataBlob>,
      Pointer<Utf16>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      Uint32,
      Pointer<_DataBlob>,
    );
typedef _ProtectDart =
    int Function(
      Pointer<_DataBlob>,
      Pointer<Utf16>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<_DataBlob>,
    );
typedef _UnprotectC =
    Int32 Function(
      Pointer<_DataBlob>,
      Pointer<Pointer<Utf16>>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      Uint32,
      Pointer<_DataBlob>,
    );
typedef _UnprotectDart =
    int Function(
      Pointer<_DataBlob>,
      Pointer<Pointer<Utf16>>,
      Pointer<_DataBlob>,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<_DataBlob>,
    );
typedef _LocalFreeC = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void>);
typedef _GetLastErrorC = Uint32 Function();
typedef _GetLastErrorDart = int Function();

/// A [DpapiCipher] on `CryptProtectData` and `CryptUnprotectData` of
/// `crypt32.dll`, for the current user, with the UI forbidden.
///
/// The DPAPI calls and `GetLastError` are leaf calls (`isLeaf: true`): the
/// Dart VM does not run between them, so the error code it reads is the one
/// the DPAPI call set.
class Crypt32Cipher implements DpapiCipher {
  Crypt32Cipher._(DynamicLibrary crypt32, DynamicLibrary kernel32)
    : _protect = crypt32.lookupFunction<_ProtectC, _ProtectDart>(
        'CryptProtectData',
        isLeaf: true,
      ),
      _unprotect = crypt32.lookupFunction<_UnprotectC, _UnprotectDart>(
        'CryptUnprotectData',
        isLeaf: true,
      ),
      _localFree = kernel32.lookupFunction<_LocalFreeC, _LocalFreeDart>(
        'LocalFree',
      ),
      _getLastError = kernel32
          .lookupFunction<_GetLastErrorC, _GetLastErrorDart>(
            'GetLastError',
            isLeaf: true,
          );

  /// Loads `crypt32.dll` and `kernel32.dll` and looks up every symbol.
  ///
  /// Throws a [SecretStoreError] for `dlopen` when a library or a symbol is
  /// missing.
  factory Crypt32Cipher.load() {
    try {
      return Crypt32Cipher._(
        DynamicLibrary.open('crypt32.dll'),
        DynamicLibrary.open('kernel32.dll'),
      );
    } on ArgumentError catch (e) {
      throw SecretStoreError(
        function: 'dlopen',
        message: 'crypt32.dll could not be loaded (${e.message})',
      );
    }
  }

  final _ProtectDart _protect;
  final _UnprotectDart _unprotect;
  final _LocalFreeDart _localFree;
  final _GetLastErrorDart _getLastError;

  @override
  Uint8List protect(Uint8List data, Uint8List entropy) {
    return using((Arena arena) {
      final Pointer<_DataBlob> input = _blob(arena, data);
      final Pointer<_DataBlob> output = arena<_DataBlob>();
      try {
        final int ok = _protect(
          input,
          nullptr,
          _blob(arena, entropy),
          nullptr,
          nullptr,
          _uiForbidden,
          output,
        );
        if (ok == 0) {
          throw _error('CryptProtectData', _getLastError());
        }
      } finally {
        _wipe(input.ref);
      }
      return _take(output.ref);
    });
  }

  @override
  Uint8List unprotect(Uint8List blob, Uint8List entropy) {
    return using((Arena arena) {
      final Pointer<_DataBlob> output = arena<_DataBlob>();
      final int ok = _unprotect(
        _blob(arena, blob),
        nullptr,
        _blob(arena, entropy),
        nullptr,
        nullptr,
        _uiForbidden,
        output,
      );
      if (ok == 0) {
        throw _error('CryptUnprotectData', _getLastError());
      }
      try {
        return Uint8List.fromList(
          output.ref.pbData.asTypedList(output.ref.cbData),
        );
      } finally {
        _wipe(output.ref);
        _localFree(output.ref.pbData.cast<Void>());
      }
    });
  }

  /// A copy of the bytes DPAPI allocated in [blob], which is then freed.
  Uint8List _take(_DataBlob blob) {
    try {
      return Uint8List.fromList(blob.pbData.asTypedList(blob.cbData));
    } finally {
      _localFree(blob.pbData.cast<Void>());
    }
  }

  static Pointer<_DataBlob> _blob(Arena arena, Uint8List bytes) {
    final Pointer<Uint8> data = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    data.asTypedList(bytes.length).setAll(0, bytes);
    final Pointer<_DataBlob> blob = arena<_DataBlob>();
    blob.ref
      ..cbData = bytes.length
      ..pbData = data;
    return blob;
  }

  static void _wipe(_DataBlob blob) {
    blob.pbData.asTypedList(blob.cbData).fillRange(0, blob.cbData, 0);
  }

  static SecretStoreError _error(String function, int code) => SecretStoreError(
    function: function,
    status: code,
    message: code == 5
        ? 'access denied (ERROR_ACCESS_DENIED)'
        : 'Win32 error $code',
  );
}
