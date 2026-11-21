import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:firebase_auth_secure_storage_dart/firebase_auth_secure_storage_dart.dart';
import 'package:firebase_auth_secure_storage_dart/src/windows/dpapi_bindings.dart';
import 'package:test/test.dart';

/// A stand-in for the DPAPI functions: copies the input (XOR 0x5A) into
/// memory it allocates, or fails with the next code of [failures].
class _FakeCalls implements DpapiCalls {
  /// The error codes the next calls fail with, in order; empty = succeed.
  final List<int> failures = <int>[];

  /// The flags of every call.
  final List<int> flags = <int>[];

  int allocated = 0;

  @override
  int protect(
    Pointer<DataBlob> input,
    Pointer<DataBlob> entropy,
    int flags,
    Pointer<DataBlob> output,
  ) => _call(input, flags, output);

  @override
  int unprotect(
    Pointer<DataBlob> input,
    Pointer<DataBlob> entropy,
    int flags,
    Pointer<DataBlob> output,
  ) => _call(input, flags, output);

  @override
  void localFree(Pointer<Void> memory) {
    allocated--;
    calloc.free(memory);
  }

  int _call(Pointer<DataBlob> input, int flags, Pointer<DataBlob> output) {
    this.flags.add(flags);
    if (failures.isNotEmpty) {
      return failures.removeAt(0);
    }
    final int length = input.ref.cbData;
    final Pointer<Uint8> bytes = calloc<Uint8>(length == 0 ? 1 : length);
    allocated++;
    for (int i = 0; i < length; i++) {
      bytes[i] = input.ref.pbData[i] ^ 0x5A;
    }
    output.ref
      ..cbData = length
      ..pbData = bytes;
    return 0;
  }
}

void main() {
  late _FakeCalls calls;
  late Crypt32Cipher cipher;
  final Uint8List data = Uint8List.fromList(<int>[1, 2, 3]);
  final Uint8List entropy = Uint8List.fromList(<int>[9]);

  setUp(() {
    calls = _FakeCalls();
    cipher = Crypt32Cipher(calls);
  });

  test('round trip; the UI is forbidden; DPAPI memory is freed', () {
    final Uint8List blob = cipher.protect(data, entropy);
    expect(cipher.unprotect(blob, entropy), data);
    expect(calls.flags, <int>[
      cryptProtectUiForbidden,
      cryptProtectUiForbidden,
    ]);
    expect(calls.allocated, 0);
  });

  test('two failures in a row both carry ERROR_ACCESS_DENIED', () {
    calls.failures.addAll(<int>[5, 5]);
    final List<SecretStoreError> errors = <SecretStoreError>[];
    for (int i = 0; i < 2; i++) {
      try {
        cipher.protect(data, entropy);
        fail('protect should fail');
      } on SecretStoreError catch (e) {
        errors.add(e);
      }
    }
    for (final SecretStoreError e in errors) {
      expect(e.function, 'CryptProtectData');
      expect(e.status, 5);
      expect(e.message, contains('ERROR_ACCESS_DENIED'));
      final SecureAuthStorageException wrapped = SecureAuthStorageException(
        platform: 'windows',
        operation: 'write',
        cause: e,
      );
      expect(wrapped.isUnavailable, isTrue);
    }
  });

  test(
    'each failure carries its own code; a success in between does not stick',
    () {
      calls.failures.addAll(<int>[5]);
      expect(
        () => cipher.protect(data, entropy),
        throwsA(
          isA<SecretStoreError>().having(
            (SecretStoreError e) => e.status,
            'status',
            5,
          ),
        ),
      );
      final Uint8List blob = cipher.protect(data, entropy);
      calls.failures.addAll(<int>[13, 5]);
      expect(
        () => cipher.unprotect(blob, entropy),
        throwsA(
          isA<SecretStoreError>()
              .having(
                (SecretStoreError e) => e.function,
                'function',
                'CryptUnprotectData',
              )
              .having((SecretStoreError e) => e.status, 'status', 13),
        ),
      );
      expect(
        () => cipher.unprotect(blob, entropy),
        throwsA(
          isA<SecretStoreError>().having(
            (SecretStoreError e) => e.status,
            'status',
            5,
          ),
        ),
      );
    },
  );

  test('a lost error code is reported as such, not as unavailable', () {
    final SecretStoreError lost = dpapiError('CryptProtectData', -1);
    expect(lost.message, contains('the error code was lost'));
    expect(
      SecureAuthStorageException(
        platform: 'windows',
        operation: 'write',
        cause: lost,
      ).isUnavailable,
      isFalse,
    );
  });
}
