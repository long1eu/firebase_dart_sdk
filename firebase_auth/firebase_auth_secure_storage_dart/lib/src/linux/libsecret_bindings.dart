import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:firebase_auth_secure_storage_dart/src/secret_store.dart';
import 'package:firebase_auth_secure_storage_dart/src/secret_text.dart';

/// The soname of libsecret (package `libsecret-1-0` on Debian and Ubuntu).
const String libsecretName = 'libsecret-1.so.0';

/// `SECRET_SCHEMA_ATTRIBUTE_STRING`.
const int _attributeString = 0;

/// `SECRET_SCHEMA_NONE`: the `xdg:schema` attribute is matched too.
const int _schemaNone = 0;

/// `SecretSchemaAttribute`.
final class SecretSchemaAttribute extends Struct {
  /// The attribute name.
  external Pointer<Utf8> name;

  /// A `SecretSchemaAttributeType`.
  @Int32()
  external int type;
}

/// `SecretSchema` of libsecret 0.18+: a name, flags, 32 attributes and the
/// reserved fields.
final class SecretSchema extends Struct {
  /// The schema name, stored as the `xdg:schema` attribute.
  external Pointer<Utf8> name;

  /// `SecretSchemaFlags`.
  @Int32()
  external int flags;

  /// The attributes; the first one with a null name ends the list.
  @Array(32)
  external Array<SecretSchemaAttribute> attributes;

  /// Reserved.
  @Int32()
  external int reserved;

  /// Reserved.
  external Pointer<Void> reserved1;

  /// Reserved.
  external Pointer<Void> reserved2;

  /// Reserved.
  external Pointer<Void> reserved3;

  /// Reserved.
  external Pointer<Void> reserved4;

  /// Reserved.
  external Pointer<Void> reserved5;

  /// Reserved.
  external Pointer<Void> reserved6;

  /// Reserved.
  external Pointer<Void> reserved7;
}

/// `GError`.
final class GError extends Struct {
  /// A `GQuark`.
  @Uint32()
  external int domain;

  /// The error code.
  @Int32()
  external int code;

  /// The message.
  external Pointer<Utf8> message;
}

typedef _Str = Pointer<Utf8>;
typedef _Err = Pointer<Pointer<GError>>;

typedef _StoreC =
    Int32 Function(
      Pointer<SecretSchema>,
      _Str,
      _Str,
      _Str,
      Pointer<Void>,
      _Err,
      VarArgs<(_Str, _Str, _Str, _Str, Pointer<Void>)>,
    );
typedef _StoreDart =
    int Function(
      Pointer<SecretSchema>,
      _Str,
      _Str,
      _Str,
      Pointer<Void>,
      _Err,
      _Str,
      _Str,
      _Str,
      _Str,
      Pointer<Void>,
    );
typedef _LookupC =
    _Str Function(
      Pointer<SecretSchema>,
      Pointer<Void>,
      _Err,
      VarArgs<(_Str, _Str, _Str, _Str, Pointer<Void>)>,
    );
typedef _LookupDart =
    _Str Function(
      Pointer<SecretSchema>,
      Pointer<Void>,
      _Err,
      _Str,
      _Str,
      _Str,
      _Str,
      Pointer<Void>,
    );
typedef _ClearC =
    Int32 Function(
      Pointer<SecretSchema>,
      Pointer<Void>,
      _Err,
      VarArgs<(_Str, _Str, _Str, _Str, Pointer<Void>)>,
    );
typedef _ClearDart =
    int Function(
      Pointer<SecretSchema>,
      Pointer<Void>,
      _Err,
      _Str,
      _Str,
      _Str,
      _Str,
      Pointer<Void>,
    );
typedef _FreeStringC = Void Function(_Str);
typedef _FreeStringDart = void Function(_Str);
typedef _ErrorFreeC = Void Function(Pointer<GError>);
typedef _ErrorFreeDart = void Function(Pointer<GError>);
typedef _QuarkToStringC = _Str Function(Uint32);
typedef _QuarkToStringDart = _Str Function(int);

/// The functions of libsecret (and of GLib, through it) the libsecret store
/// calls, looked up once, and the schema of its items.
///
/// The schema has the name [schemaName] and two string attributes, `service`
/// and `account`. It lives in native memory for the life of the process (one
/// per store), as libsecret expects of a schema.
class LibsecretBindings {
  LibsecretBindings._(DynamicLibrary library, this.schemaName)
    : _store = library.lookupFunction<_StoreC, _StoreDart>(
        'secret_password_store_sync',
      ),
      _lookup = library.lookupFunction<_LookupC, _LookupDart>(
        'secret_password_lookup_sync',
      ),
      _clear = library.lookupFunction<_ClearC, _ClearDart>(
        'secret_password_clear_sync',
      ),
      _passwordFree = library.lookupFunction<_FreeStringC, _FreeStringDart>(
        'secret_password_free',
      ),
      _errorFree = library.lookupFunction<_ErrorFreeC, _ErrorFreeDart>(
        'g_error_free',
      ),
      _quarkToString = library
          .lookupFunction<_QuarkToStringC, _QuarkToStringDart>(
            'g_quark_to_string',
          ),
      schema = _newSchema(schemaName);

  /// Loads libsecret ([libsecretName]) and looks up every symbol.
  ///
  /// Throws a [SecretStoreError] for `dlopen` when the library or a symbol is
  /// missing.
  factory LibsecretBindings.load(String schemaName) {
    try {
      return LibsecretBindings._(
        DynamicLibrary.open(libsecretName),
        schemaName,
      );
    } on ArgumentError catch (e) {
      throw SecretStoreError(
        function: 'dlopen',
        message: '$libsecretName could not be loaded (${e.message})',
      );
    }
  }

  /// The name of the schema (the `xdg:schema` attribute of the items).
  final String schemaName;

  /// The schema, never freed.
  final Pointer<SecretSchema> schema;

  final _StoreDart _store;
  final _LookupDart _lookup;
  final _ClearDart _clear;
  final _FreeStringDart _passwordFree;
  final _ErrorFreeDart _errorFree;
  final _QuarkToStringDart _quarkToString;

  /// Stores [secret] for [service] and [account] in the default collection,
  /// with [label] as its label.
  void store(String service, String account, String label, String secret) {
    using((Arena arena) {
      final _Err error = _newError(arena);
      final _Str password = secret.toNativeUtf8(allocator: arena);
      try {
        _store(
          schema,
          nullptr,
          label.toNativeUtf8(allocator: arena),
          password,
          nullptr,
          error,
          _serviceName(arena),
          service.toNativeUtf8(allocator: arena),
          _accountName(arena),
          account.toNativeUtf8(allocator: arena),
          nullptr,
        );
      } finally {
        _wipe(password);
      }
      _check(error, 'secret_password_store_sync');
    });
  }

  /// The secret of [service] and [account], or null when there is none. The
  /// native copy is wiped and freed once it is decoded.
  String? lookup(String service, String account) {
    return using((Arena arena) {
      final _Err error = _newError(arena);
      final _Str password = _lookup(
        schema,
        nullptr,
        error,
        _serviceName(arena),
        service.toNativeUtf8(allocator: arena),
        _accountName(arena),
        account.toNativeUtf8(allocator: arena),
        nullptr,
      );
      _check(error, 'secret_password_lookup_sync');
      if (password == nullptr) {
        return null;
      }
      try {
        final int length = password.length;
        return decodeSecret(
          password.cast<Uint8>().asTypedList(length),
          'secret_password_lookup_sync',
        );
      } finally {
        _wipe(password);
        _passwordFree(password);
      }
    });
  }

  /// Deletes the secret of [service] and [account], if any.
  void clear(String service, String account) {
    using((Arena arena) {
      final _Err error = _newError(arena);
      _clear(
        schema,
        nullptr,
        error,
        _serviceName(arena),
        service.toNativeUtf8(allocator: arena),
        _accountName(arena),
        account.toNativeUtf8(allocator: arena),
        nullptr,
      );
      _check(error, 'secret_password_clear_sync');
    });
  }

  static _Err _newError(Arena arena) {
    final _Err error = arena<Pointer<GError>>();
    error.value = nullptr;
    return error;
  }

  static _Str _serviceName(Arena arena) =>
      'service'.toNativeUtf8(allocator: arena);

  static _Str _accountName(Arena arena) =>
      'account'.toNativeUtf8(allocator: arena);

  /// Overwrites the NUL-terminated copy of a secret before it is freed.
  static void _wipe(_Str text) {
    final Pointer<Uint8> bytes = text.cast<Uint8>();
    for (int i = 0; bytes[i] != 0; i++) {
      bytes[i] = 0;
    }
  }

  /// Throws the `GError` in [error], if any, as a [SecretStoreError], and
  /// frees it.
  void _check(_Err error, String function) {
    final Pointer<GError> value = error.value;
    if (value == nullptr) {
      return;
    }
    final GError gError = value.ref;
    final _Str domain = _quarkToString(gError.domain);
    final SecretStoreError failure = SecretStoreError(
      function: function,
      status: gError.code,
      domain: domain == nullptr ? null : domain.toDartString(),
      message: gError.message == nullptr
          ? 'no message'
          : gError.message.toDartString(),
    );
    _errorFree(value);
    throw failure;
  }

  static Pointer<SecretSchema> _newSchema(String name) {
    final Pointer<SecretSchema> schema = calloc<SecretSchema>();
    schema.ref
      ..name = name.toNativeUtf8()
      ..flags = _schemaNone;
    schema.ref.attributes[0]
      ..name = 'service'.toNativeUtf8()
      ..type = _attributeString;
    schema.ref.attributes[1]
      ..name = 'account'.toNativeUtf8()
      ..type = _attributeString;
    return schema;
  }
}
