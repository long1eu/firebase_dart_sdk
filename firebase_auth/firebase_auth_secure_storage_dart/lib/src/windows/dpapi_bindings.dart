import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:firebase_auth_secure_storage_dart/src/secret_store.dart';
import 'package:firebase_auth_secure_storage_dart/src/windows/dpapi_store.dart';

/// `CRYPTPROTECT_UI_FORBIDDEN`: fail instead of showing a prompt.
const int cryptProtectUiForbidden = 0x1;

/// `ERROR_ACCESS_DENIED`.
const int _errorAccessDenied = 5;

/// `DATA_BLOB` (`CRYPT_INTEGER_BLOB`).
final class DataBlob extends Struct {
  /// The number of bytes.
  @Uint32()
  external int cbData;

  /// The bytes.
  external Pointer<Uint8> pbData;
}

/// The three calls of DPAPI that [Crypt32Cipher] makes: the real ones of
/// `crypt32.dll` ([Crypt32Calls]), or a fake in tests.
abstract interface class DpapiCalls {
  /// `CryptProtectData(input, NULL, entropy, NULL, NULL, flags, output)`.
  ///
  /// Returns 0 on success, else the Win32 error code that `GetLastError`
  /// gave right after the failing call, before any other call.
  int protect(
    Pointer<DataBlob> input,
    Pointer<DataBlob> entropy,
    int flags,
    Pointer<DataBlob> output,
  );

  /// `CryptUnprotectData(input, NULL, entropy, NULL, NULL, flags, output)`;
  /// returns as [protect].
  int unprotect(
    Pointer<DataBlob> input,
    Pointer<DataBlob> entropy,
    int flags,
    Pointer<DataBlob> output,
  );

  /// `LocalFree(memory)`, for the output of a successful call.
  void localFree(Pointer<Void> memory);
}

@Native<
  Int32 Function(
    Pointer<DataBlob>,
    Pointer<Utf16>,
    Pointer<DataBlob>,
    Pointer<Void>,
    Pointer<Void>,
    Uint32,
    Pointer<DataBlob>,
  )
>(symbol: 'CryptProtectData', isLeaf: true)
external int _cryptProtectData(
  Pointer<DataBlob> input,
  Pointer<Utf16> description,
  Pointer<DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<DataBlob> output,
);

@Native<
  Int32 Function(
    Pointer<DataBlob>,
    Pointer<Pointer<Utf16>>,
    Pointer<DataBlob>,
    Pointer<Void>,
    Pointer<Void>,
    Uint32,
    Pointer<DataBlob>,
  )
>(symbol: 'CryptUnprotectData', isLeaf: true)
external int _cryptUnprotectData(
  Pointer<DataBlob> input,
  Pointer<Pointer<Utf16>> description,
  Pointer<DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<DataBlob> output,
);

@Native<Uint32 Function()>(symbol: 'GetLastError', isLeaf: true)
external int _getLastError();

@Native<Pointer<Void> Function(Pointer<Void>)>(symbol: 'LocalFree')
external Pointer<Void> _localFree(Pointer<Void> memory);

/// The DPAPI functions of `crypt32.dll` and `kernel32.dll`.
///
/// They are `@Native` leaf calls resolved in the process, and each failing
/// call is followed at once by `GetLastError` in the same Dart function: no
/// closure call, Dart function entry or allocation runs between the two, so
/// no code of the Dart VM can overwrite the thread's last error first.
class Crypt32Calls implements DpapiCalls {
  Crypt32Calls._();

  /// Loads `crypt32.dll` into the process (kernel32 always is), so that the
  /// `@Native` functions resolve.
  ///
  /// Throws a [SecretStoreError] for `dlopen` when it cannot be loaded or
  /// lacks a function.
  factory Crypt32Calls.load() {
    final DynamicLibrary crypt32;
    try {
      crypt32 = DynamicLibrary.open('crypt32.dll');
    } on ArgumentError catch (e) {
      throw SecretStoreError(
        function: 'dlopen',
        message: 'crypt32.dll could not be loaded (${e.message})',
      );
    }
    for (final String symbol in <String>[
      'CryptProtectData',
      'CryptUnprotectData',
    ]) {
      if (!crypt32.providesSymbol(symbol)) {
        throw SecretStoreError(
          function: 'dlopen',
          message: 'crypt32.dll has no $symbol',
        );
      }
    }
    return Crypt32Calls._();
  }

  @override
  int protect(
    Pointer<DataBlob> input,
    Pointer<DataBlob> entropy,
    int flags,
    Pointer<DataBlob> output,
  ) {
    final int ok = _cryptProtectData(
      input,
      nullptr,
      entropy,
      nullptr,
      nullptr,
      flags,
      output,
    );
    final int error = ok == 0 ? _getLastError() : 0;
    return ok == 0 ? _nonZero(error) : 0;
  }

  @override
  int unprotect(
    Pointer<DataBlob> input,
    Pointer<DataBlob> entropy,
    int flags,
    Pointer<DataBlob> output,
  ) {
    final int ok = _cryptUnprotectData(
      input,
      nullptr,
      entropy,
      nullptr,
      nullptr,
      flags,
      output,
    );
    final int error = ok == 0 ? _getLastError() : 0;
    return ok == 0 ? _nonZero(error) : 0;
  }

  @override
  void localFree(Pointer<Void> memory) {
    _localFree(memory);
  }

  /// A failed call whose last error reads 0 still failed: report it as -1,
  /// "the code was lost", rather than as success.
  static int _nonZero(int error) => error == 0 ? -1 : error;
}

/// A [DpapiCipher] on DPAPI for the current user, with the UI forbidden.
///
/// Every failure is a new [SecretStoreError] with the error code [calls]
/// returned for that very call; nothing is cached between calls.
class Crypt32Cipher implements DpapiCipher {
  /// A cipher over [calls].
  Crypt32Cipher(this.calls);

  /// A cipher over the real DPAPI ([Crypt32Calls.load]).
  factory Crypt32Cipher.load() => Crypt32Cipher(Crypt32Calls.load());

  /// The DPAPI functions.
  final DpapiCalls calls;

  @override
  Uint8List protect(Uint8List data, Uint8List entropy) {
    return using((Arena arena) {
      final Pointer<DataBlob> input = _blob(arena, data);
      final Pointer<DataBlob> output = arena<DataBlob>();
      final int error;
      try {
        error = calls.protect(
          input,
          _blob(arena, entropy),
          cryptProtectUiForbidden,
          output,
        );
      } finally {
        _wipe(input.ref);
      }
      if (error != 0) {
        throw dpapiError('CryptProtectData', error);
      }
      try {
        return Uint8List.fromList(
          output.ref.pbData.asTypedList(output.ref.cbData),
        );
      } finally {
        calls.localFree(output.ref.pbData.cast<Void>());
      }
    });
  }

  @override
  Uint8List unprotect(Uint8List blob, Uint8List entropy) {
    return using((Arena arena) {
      final Pointer<DataBlob> output = arena<DataBlob>();
      final int error = calls.unprotect(
        _blob(arena, blob),
        _blob(arena, entropy),
        cryptProtectUiForbidden,
        output,
      );
      if (error != 0) {
        throw dpapiError('CryptUnprotectData', error);
      }
      try {
        return Uint8List.fromList(
          output.ref.pbData.asTypedList(output.ref.cbData),
        );
      } finally {
        _wipe(output.ref);
        calls.localFree(output.ref.pbData.cast<Void>());
      }
    });
  }

  static Pointer<DataBlob> _blob(Arena arena, Uint8List bytes) {
    final Pointer<Uint8> data = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    data.asTypedList(bytes.length).setAll(0, bytes);
    final Pointer<DataBlob> blob = arena<DataBlob>();
    blob.ref
      ..cbData = bytes.length
      ..pbData = data;
    return blob;
  }

  static void _wipe(DataBlob blob) {
    blob.pbData.asTypedList(blob.cbData).fillRange(0, blob.cbData, 0);
  }
}

/// The [SecretStoreError] of a failed DPAPI [function] with the Win32 error
/// [code] (-1 when the code was lost).
SecretStoreError dpapiError(String function, int code) => SecretStoreError(
  function: function,
  status: code,
  message: switch (code) {
    _errorAccessDenied => 'access denied (ERROR_ACCESS_DENIED)',
    -1 => 'failed, but GetLastError returned 0 (the error code was lost)',
    _ => 'Win32 error $code',
  },
);
