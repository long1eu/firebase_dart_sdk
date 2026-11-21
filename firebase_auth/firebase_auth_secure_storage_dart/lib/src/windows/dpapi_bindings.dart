import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:firebase_auth_secure_storage_dart/src/secret_store.dart';
import 'package:firebase_auth_secure_storage_dart/src/windows/dpapi_store.dart';

/// `CRYPTPROTECT_UI_FORBIDDEN`: fail instead of showing a prompt.
const int cryptProtectUiForbidden = 0x1;

/// `ERROR_ACCESS_DENIED`.
const int _errorAccessDenied = 5;

/// `ERROR_PROC_NOT_FOUND`: what a failed `GetProcAddress` leaves behind.
const int _errorProcNotFound = 127;

/// The code [DpapiCalls] returns for a failed call whose last error read 0:
/// the real code was lost.
const int dpapiLostError = -1;

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
  /// gave right after the failing call, before any other call
  /// ([dpapiLostError] when that read 0).
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

  /// Binds `GetLastError` and `LocalFree` before the first DPAPI call.
  ///
  /// A `@Native` function is resolved at its first call, and a symbol lookup
  /// that misses on the way (`GetProcAddress` fails with
  /// `ERROR_PROC_NOT_FOUND`, 127) overwrites the thread's last error. Done
  /// after a failed DPAPI call, the first read of the error would get 127
  /// instead of the DPAPI code.
  void prepare();
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
>(symbol: 'CryptProtectData')
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
>(symbol: 'CryptUnprotectData')
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

/// The DPAPI functions of `crypt32.dll` and `kernel32.dll`, as `@Native`
/// functions resolved in the process.
///
/// `CryptProtectData` and `CryptUnprotectData` are ordinary (non-leaf) calls:
/// they may wait seconds on an RPC to LSASS (a roaming or domain profile can
/// fetch its master key from a domain controller), and a leaf call would hold
/// up the garbage collector of the whole isolate group for that long.
///
/// Each failing call is followed at once by `GetLastError`, a leaf call
/// already resolved by [prepare], in the same Dart function: no closure
/// call, Dart function entry, allocation or symbol lookup runs between them.
/// What does run is the VM's return from native code. When no safepoint
/// operation (a garbage collection, a reload) is under way, that is a
/// compare-and-swap of the thread state with no system call, so the last
/// error survives. When one is under way, the thread waits in the VM until it
/// ends, and that wait may overwrite the last error. [Crypt32Cipher] retries
/// once when the code it got looks overwritten (0, or 127), and the message
/// of [dpapiError] says when a code may be wrong. Dart has no way to read
/// the error atomically with the call (dart-lang/sdk#38832) without native
/// code of its own.
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

  /// Calls `GetLastError` and `LocalFree(NULL)` (which frees nothing) once,
  /// so that both are resolved before any DPAPI call can fail. The DPAPI
  /// functions themselves are resolved before their own call, which is
  /// harmless.
  @override
  void prepare() {
    _getLastError();
    _localFree(nullptr);
  }

  /// A failed call whose last error reads 0 still failed: report it as
  /// [dpapiLostError] rather than as success.
  static int _nonZero(int error) => error == 0 ? dpapiLostError : error;
}

/// A [DpapiCipher] on DPAPI for the current user, with the UI forbidden.
///
/// Every failure is a new [SecretStoreError] with the error code [calls]
/// returned for that very call; nothing is cached between calls. A call
/// whose code looks overwritten ([dpapiLostError] or 127, see
/// [Crypt32Calls]) is made once more, and the second result counts.
class Crypt32Cipher implements DpapiCipher {
  /// A cipher over [calls]; [DpapiCalls.prepare] runs here, before any DPAPI
  /// call.
  Crypt32Cipher(this.calls) {
    calls.prepare();
  }

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
        final Pointer<DataBlob> salt = _blob(arena, entropy);
        error = _retryIfOverwritten(
          () => calls.protect(input, salt, cryptProtectUiForbidden, output),
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
      final Pointer<DataBlob> input = _blob(arena, blob);
      final Pointer<DataBlob> salt = _blob(arena, entropy);
      final int error = _retryIfOverwritten(
        () => calls.unprotect(input, salt, cryptProtectUiForbidden, output),
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

  /// The result of [call], or of a second call when the first one's code
  /// looks overwritten by the VM rather than set by DPAPI.
  static int _retryIfOverwritten(int Function() call) {
    final int error = call();
    if (error == dpapiLostError || error == _errorProcNotFound) {
      return call();
    }
    return error;
  }

  static void _wipe(DataBlob blob) {
    blob.pbData.asTypedList(blob.cbData).fillRange(0, blob.cbData, 0);
  }
}

/// The [SecretStoreError] of a failed DPAPI [function] with the Win32 error
/// [code] ([dpapiLostError] when the code was lost).
SecretStoreError dpapiError(String function, int code) => SecretStoreError(
  function: function,
  status: code,
  message: switch (code) {
    _errorAccessDenied => 'access denied (ERROR_ACCESS_DENIED)',
    dpapiLostError =>
      'failed twice, but GetLastError returned 0 (the error code was lost)',
    _errorProcNotFound =>
      'Win32 error 127 (ERROR_PROC_NOT_FOUND), twice; DPAPI does not set '
          'this itself, so the code may be wrong: the VM may have '
          'overwritten the last error',
    _ => 'Win32 error $code',
  },
);
