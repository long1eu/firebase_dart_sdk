import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:firebase_auth_secure_storage_dart/src/macos/security_bindings.dart';
import 'package:firebase_auth_secure_storage_dart/src/secret_store.dart';
import 'package:firebase_auth_secure_storage_dart/src/secret_text.dart';

/// `errSecSuccess`.
const int _errSecSuccess = 0;

/// `errSecItemNotFound`: no item matches the query.
const int _errSecItemNotFound = -25300;

/// A [SecretStore] in the login keychain of macOS: generic-password items
/// with the Keychain service [service] and the account name as the account.
///
/// A command line program has no entitlements, so the items go to the legacy
/// (file-based) keychain, selected explicitly with
/// `kSecUseDataProtectionKeychain = false`. Its items are guarded by an access
/// control list that trusts the program that created them: another program,
/// or the same one after it was rebuilt with another signature, makes macOS
/// ask the user, which fails without a window server (an SSH session, a
/// daemon).
///
/// Security.framework and CoreFoundation are loaded at the first call. The
/// calls are synchronous: they block the isolate while the Keychain answers.
class KeychainSecretStore implements SecretStore {
  /// A store for the items of [service].
  KeychainSecretStore({required this.service});

  /// The Keychain service (`kSecAttrService`) of the items.
  final String service;

  SecurityBindings? _bindings;

  SecurityBindings get _api => _bindings ??= SecurityBindings.load();

  @override
  Future<String?> read(String account) => Future<String?>(() => _read(account));

  @override
  Future<void> write(String account, String secret) =>
      Future<void>(() => _write(account, secret));

  @override
  Future<void> delete(String account) => Future<void>(() => _delete(account));

  String? _read(String account) {
    final SecurityBindings api = _api;
    return using((Arena arena) {
      final _Dictionary query = _query(api, arena, account)
        ..put(api.kSecReturnData, api.kCFBooleanTrue)
        ..put(api.kSecMatchLimit, api.kSecMatchLimitOne);
      final Pointer<Pointer<Void>> result = arena<Pointer<Void>>();
      final int status = _withDictionary(
        api,
        query,
        (CFDictionaryRef q) => api.secItemCopyMatching(q, result),
      );
      if (status == _errSecItemNotFound) {
        return null;
      }
      _check(api, 'SecItemCopyMatching', status);
      final Pointer<Void> data = result.value;
      try {
        final int length = api.cfDataGetLength(data);
        final Uint8List bytes = api.cfDataGetBytePtr(data).asTypedList(length);
        return decodeSecret(bytes, 'SecItemCopyMatching');
      } finally {
        api.cfRelease(data);
      }
    });
  }

  void _write(String account, String secret) {
    final SecurityBindings api = _api;
    using((Arena arena) {
      final Uint8List bytes = utf8.encode(secret);
      final Pointer<Uint8> buffer = arena<Uint8>(bytes.length);
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final CFTypeRef data = api.cfDataCreate(nullptr, buffer, bytes.length);
      buffer.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      try {
        _upsert(api, arena, account, data);
      } finally {
        api.cfRelease(data);
      }
    });
  }

  void _upsert(
    SecurityBindings api,
    Arena arena,
    String account,
    CFTypeRef data,
  ) {
    final _Dictionary query = _query(api, arena, account);
    final _Dictionary update = _Dictionary(arena)..put(api.kSecValueData, data);
    final int status = _withDictionary(
      api,
      query,
      (CFDictionaryRef q) => _withDictionary(
        api,
        update,
        (CFDictionaryRef u) => api.secItemUpdate(q, u),
      ),
    );
    if (status != _errSecItemNotFound) {
      _check(api, 'SecItemUpdate', status);
      return;
    }
    final _Dictionary add = _query(api, arena, account)
      ..put(api.kSecValueData, data);
    final int added = _withDictionary(
      api,
      add,
      (CFDictionaryRef a) => api.secItemAdd(a, nullptr),
    );
    _check(api, 'SecItemAdd', added);
  }

  void _delete(String account) {
    final SecurityBindings api = _api;
    using((Arena arena) {
      final int status = _withDictionary(
        api,
        _query(api, arena, account),
        api.secItemDelete,
      );
      if (status != _errSecItemNotFound) {
        _check(api, 'SecItemDelete', status);
      }
    });
  }

  /// The attributes that name the item of [account]. The CF strings are
  /// released with [arena].
  _Dictionary _query(SecurityBindings api, Arena arena, String account) {
    return _Dictionary(arena)
      ..put(api.kSecClass, api.kSecClassGenericPassword)
      ..put(api.kSecAttrService, _string(api, arena, service))
      ..put(api.kSecAttrAccount, _string(api, arena, account))
      ..put(api.kSecUseDataProtectionKeychain, api.kCFBooleanFalse);
  }

  static CFTypeRef _string(SecurityBindings api, Arena arena, String value) {
    final CFTypeRef string = api.cfStringCreateWithCString(
      nullptr,
      value.toNativeUtf8(allocator: arena),
      kCFStringEncodingUTF8,
    );
    arena.onReleaseAll(() => api.cfRelease(string));
    return string;
  }

  static int _withDictionary(
    SecurityBindings api,
    _Dictionary dictionary,
    int Function(CFDictionaryRef dictionary) call,
  ) {
    final CFDictionaryRef ref = dictionary.create(api);
    try {
      return call(ref);
    } finally {
      api.cfRelease(ref);
    }
  }

  static void _check(SecurityBindings api, String function, int status) {
    if (status == _errSecSuccess) {
      return;
    }
    throw SecretStoreError(
      function: function,
      status: status,
      message: api.errorMessage(status),
    );
  }
}

/// The keys and values of a `CFDictionary` to create.
class _Dictionary {
  _Dictionary(this._arena);

  final Arena _arena;
  final List<CFTypeRef> _keys = <CFTypeRef>[];
  final List<CFTypeRef> _values = <CFTypeRef>[];

  void put(CFTypeRef key, CFTypeRef value) {
    _keys.add(key);
    _values.add(value);
  }

  /// A new immutable dictionary; the caller releases it.
  CFDictionaryRef create(SecurityBindings api) {
    final Pointer<CFTypeRef> keys = _arena<CFTypeRef>(_keys.length);
    final Pointer<CFTypeRef> values = _arena<CFTypeRef>(_values.length);
    for (int i = 0; i < _keys.length; i++) {
      keys[i] = _keys[i];
      values[i] = _values[i];
    }
    return api.cfDictionaryCreate(nullptr, keys, values, _keys.length);
  }
}
