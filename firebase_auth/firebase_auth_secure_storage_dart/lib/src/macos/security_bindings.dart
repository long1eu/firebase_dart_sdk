import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:firebase_auth_secure_storage_dart/src/secret_store.dart';

/// A `CFTypeRef`: any CoreFoundation object.
typedef CFTypeRef = Pointer<Void>;

/// A `CFDictionaryRef`.
typedef CFDictionaryRef = Pointer<Void>;

/// `kCFStringEncodingUTF8`.
const int kCFStringEncodingUTF8 = 0x08000100;

const String _securityPath =
    '/System/Library/Frameworks/Security.framework/Security';
const String _coreFoundationPath =
    '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation';

typedef _SecItemCopyMatchingC =
    Int32 Function(CFDictionaryRef, Pointer<CFTypeRef>);
typedef _SecItemCopyMatchingDart =
    int Function(CFDictionaryRef, Pointer<CFTypeRef>);
typedef _SecItemUpdateC = Int32 Function(CFDictionaryRef, CFDictionaryRef);
typedef _SecItemUpdateDart = int Function(CFDictionaryRef, CFDictionaryRef);
typedef _SecItemDeleteC = Int32 Function(CFDictionaryRef);
typedef _SecItemDeleteDart = int Function(CFDictionaryRef);
typedef _SecCopyErrorMessageStringC = CFTypeRef Function(Int32, Pointer<Void>);
typedef _SecCopyErrorMessageStringDart = CFTypeRef Function(int, Pointer<Void>);
typedef _CFReleaseC = Void Function(CFTypeRef);
typedef _CFReleaseDart = void Function(CFTypeRef);
typedef _CFDataCreateC =
    CFTypeRef Function(Pointer<Void>, Pointer<Uint8>, Long);
typedef _CFDataCreateDart =
    CFTypeRef Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _CFDataGetLengthC = Long Function(CFTypeRef);
typedef _CFDataGetLengthDart = int Function(CFTypeRef);
typedef _CFDataGetBytePtrC = Pointer<Uint8> Function(CFTypeRef);
typedef _CFDataGetBytePtrDart = Pointer<Uint8> Function(CFTypeRef);
typedef _CFStringCreateWithCStringC =
    CFTypeRef Function(Pointer<Void>, Pointer<Utf8>, Uint32);
typedef _CFStringCreateWithCStringDart =
    CFTypeRef Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _CFStringGetLengthC = Long Function(CFTypeRef);
typedef _CFStringGetLengthDart = int Function(CFTypeRef);
typedef _CFStringGetMaximumSizeForEncodingC = Long Function(Long, Uint32);
typedef _CFStringGetMaximumSizeForEncodingDart = int Function(int, int);
typedef _CFStringGetCStringC =
    Uint8 Function(CFTypeRef, Pointer<Utf8>, Long, Uint32);
typedef _CFStringGetCStringDart =
    int Function(CFTypeRef, Pointer<Utf8>, int, int);
typedef _CFDictionaryCreateC =
    CFDictionaryRef Function(
      Pointer<Void>,
      Pointer<CFTypeRef>,
      Pointer<CFTypeRef>,
      Long,
      Pointer<Void>,
      Pointer<Void>,
    );
typedef _CFDictionaryCreateDart =
    CFDictionaryRef Function(
      Pointer<Void>,
      Pointer<CFTypeRef>,
      Pointer<CFTypeRef>,
      int,
      Pointer<Void>,
      Pointer<Void>,
    );

/// The functions and constants of Security.framework and CoreFoundation that
/// the Keychain store calls, looked up once.
class SecurityBindings {
  SecurityBindings._(DynamicLibrary security, DynamicLibrary cf)
    : secItemAdd = security.lookupFunction<_SecItemUpdateC, _SecItemUpdateDart>(
        'SecItemAdd',
      ),
      secItemCopyMatching = security
          .lookupFunction<_SecItemCopyMatchingC, _SecItemCopyMatchingDart>(
            'SecItemCopyMatching',
          ),
      secItemUpdate = security
          .lookupFunction<_SecItemUpdateC, _SecItemUpdateDart>('SecItemUpdate'),
      secItemDelete = security
          .lookupFunction<_SecItemDeleteC, _SecItemDeleteDart>('SecItemDelete'),
      _secCopyErrorMessageString = security
          .lookupFunction<
            _SecCopyErrorMessageStringC,
            _SecCopyErrorMessageStringDart
          >('SecCopyErrorMessageString'),
      cfRelease = cf.lookupFunction<_CFReleaseC, _CFReleaseDart>('CFRelease'),
      cfDataCreate = cf.lookupFunction<_CFDataCreateC, _CFDataCreateDart>(
        'CFDataCreate',
      ),
      cfDataGetLength = cf
          .lookupFunction<_CFDataGetLengthC, _CFDataGetLengthDart>(
            'CFDataGetLength',
          ),
      cfDataGetBytePtr = cf
          .lookupFunction<_CFDataGetBytePtrC, _CFDataGetBytePtrDart>(
            'CFDataGetBytePtr',
          ),
      cfStringCreateWithCString = cf
          .lookupFunction<
            _CFStringCreateWithCStringC,
            _CFStringCreateWithCStringDart
          >('CFStringCreateWithCString'),
      _cfStringGetLength = cf
          .lookupFunction<_CFStringGetLengthC, _CFStringGetLengthDart>(
            'CFStringGetLength',
          ),
      _cfStringGetMaximumSizeForEncoding = cf
          .lookupFunction<
            _CFStringGetMaximumSizeForEncodingC,
            _CFStringGetMaximumSizeForEncodingDart
          >('CFStringGetMaximumSizeForEncoding'),
      _cfStringGetCString = cf
          .lookupFunction<_CFStringGetCStringC, _CFStringGetCStringDart>(
            'CFStringGetCString',
          ),
      _cfDictionaryCreate = cf
          .lookupFunction<_CFDictionaryCreateC, _CFDictionaryCreateDart>(
            'CFDictionaryCreate',
          ),
      _keyCallBacks = cf.lookup<Void>('kCFTypeDictionaryKeyCallBacks'),
      _valueCallBacks = cf.lookup<Void>('kCFTypeDictionaryValueCallBacks'),
      kCFBooleanTrue = _constant(cf, 'kCFBooleanTrue'),
      kCFBooleanFalse = _constant(cf, 'kCFBooleanFalse'),
      kSecClass = _constant(security, 'kSecClass'),
      kSecClassGenericPassword = _constant(
        security,
        'kSecClassGenericPassword',
      ),
      kSecAttrService = _constant(security, 'kSecAttrService'),
      kSecAttrAccount = _constant(security, 'kSecAttrAccount'),
      kSecValueData = _constant(security, 'kSecValueData'),
      kSecReturnData = _constant(security, 'kSecReturnData'),
      kSecMatchLimit = _constant(security, 'kSecMatchLimit'),
      kSecMatchLimitOne = _constant(security, 'kSecMatchLimitOne'),
      kSecUseDataProtectionKeychain = _constant(
        security,
        'kSecUseDataProtectionKeychain',
      );

  /// Loads Security.framework and CoreFoundation and looks up every symbol.
  ///
  /// Throws a [SecretStoreError] for `dlopen` when a framework or a symbol is
  /// missing.
  factory SecurityBindings.load() {
    try {
      return SecurityBindings._(
        DynamicLibrary.open(_securityPath),
        DynamicLibrary.open(_coreFoundationPath),
      );
    } on ArgumentError catch (e) {
      throw SecretStoreError(
        function: 'dlopen',
        message: 'Security.framework could not be loaded (${e.message})',
      );
    }
  }

  /// `SecItemAdd(attributes, result)`.
  final int Function(CFDictionaryRef attributes, CFDictionaryRef result)
  secItemAdd;

  /// `SecItemCopyMatching(query, result)`.
  final int Function(CFDictionaryRef query, Pointer<CFTypeRef> result)
  secItemCopyMatching;

  /// `SecItemUpdate(query, attributesToUpdate)`.
  final int Function(CFDictionaryRef query, CFDictionaryRef update)
  secItemUpdate;

  /// `SecItemDelete(query)`.
  final int Function(CFDictionaryRef query) secItemDelete;

  final _SecCopyErrorMessageStringDart _secCopyErrorMessageString;

  /// `CFRelease(object)`.
  final void Function(CFTypeRef object) cfRelease;

  /// `CFDataCreate(allocator, bytes, length)`: a copy of the bytes.
  final CFTypeRef Function(
    Pointer<Void> allocator,
    Pointer<Uint8> bytes,
    int length,
  )
  cfDataCreate;

  /// `CFDataGetLength(data)`.
  final int Function(CFTypeRef data) cfDataGetLength;

  /// `CFDataGetBytePtr(data)`.
  final Pointer<Uint8> Function(CFTypeRef data) cfDataGetBytePtr;

  /// `CFStringCreateWithCString(allocator, text, encoding)`.
  final CFTypeRef Function(
    Pointer<Void> allocator,
    Pointer<Utf8> text,
    int encoding,
  )
  cfStringCreateWithCString;

  final _CFStringGetLengthDart _cfStringGetLength;
  final _CFStringGetMaximumSizeForEncodingDart
  _cfStringGetMaximumSizeForEncoding;
  final _CFStringGetCStringDart _cfStringGetCString;
  final _CFDictionaryCreateDart _cfDictionaryCreate;
  final Pointer<Void> _keyCallBacks;
  final Pointer<Void> _valueCallBacks;

  /// `kCFBooleanTrue`.
  final CFTypeRef kCFBooleanTrue;

  /// `kCFBooleanFalse`.
  final CFTypeRef kCFBooleanFalse;

  /// `kSecClass`.
  final CFTypeRef kSecClass;

  /// `kSecClassGenericPassword`.
  final CFTypeRef kSecClassGenericPassword;

  /// `kSecAttrService`.
  final CFTypeRef kSecAttrService;

  /// `kSecAttrAccount`.
  final CFTypeRef kSecAttrAccount;

  /// `kSecValueData`.
  final CFTypeRef kSecValueData;

  /// `kSecReturnData`.
  final CFTypeRef kSecReturnData;

  /// `kSecMatchLimit`.
  final CFTypeRef kSecMatchLimit;

  /// `kSecMatchLimitOne`.
  final CFTypeRef kSecMatchLimitOne;

  /// `kSecUseDataProtectionKeychain`.
  final CFTypeRef kSecUseDataProtectionKeychain;

  /// `CFDictionaryCreate` with [count] [keys] and [values] and the CFType
  /// callbacks, so the dictionary retains them. The caller releases it.
  CFDictionaryRef cfDictionaryCreate(
    Pointer<Void> allocator,
    Pointer<CFTypeRef> keys,
    Pointer<CFTypeRef> values,
    int count,
  ) => _cfDictionaryCreate(
    allocator,
    keys,
    values,
    count,
    _keyCallBacks,
    _valueCallBacks,
  );

  /// The message Security.framework has for [status], or a generic one.
  String errorMessage(int status) {
    final CFTypeRef message = _secCopyErrorMessageString(status, nullptr);
    if (message == nullptr) {
      return 'OSStatus $status';
    }
    try {
      return _cfString(message) ?? 'OSStatus $status';
    } finally {
      cfRelease(message);
    }
  }

  String? _cfString(CFTypeRef string) {
    final int size =
        _cfStringGetMaximumSizeForEncoding(
          _cfStringGetLength(string),
          kCFStringEncodingUTF8,
        ) +
        1;
    return using((Arena arena) {
      final Pointer<Utf8> buffer = arena<Uint8>(size).cast<Utf8>();
      if (_cfStringGetCString(string, buffer, size, kCFStringEncodingUTF8) ==
          0) {
        return null;
      }
      return buffer.toDartString();
    });
  }

  /// The value of the global `CFTypeRef` constant [name] of [library].
  static CFTypeRef _constant(DynamicLibrary library, String name) =>
      library.lookup<CFTypeRef>(name).value;
}
