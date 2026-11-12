// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/emulator_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local_cache_settings.dart';
import 'package:collection/collection.dart';
import 'package:firebase_app_dart/internal.dart';

/// Settings used to configure a FirebaseFirestore instance.
class FirestoreSettings {
  /// Constructs a FirebaseFirestoreSettings object
  FirestoreSettings({
    String host = defaultHost,
    int port = defaultPort,
    bool sslEnabled = true,
    bool persistenceEnabled = true,
    int cacheSizeBytes = defaultCacheSizeBytes,
    LocalCacheSettings? cacheSettings,
  }) : this._(
          host: host,
          port: port,
          sslEnabled: sslEnabled,
          persistenceEnabled: persistenceEnabled,
          cacheSizeBytes: cacheSizeBytes,
          cacheSettings: cacheSettings,
          emulator: false,
          mockUserToken: null,
        );

  /// [emulator] is true only for settings made by [withEmulator]; a
  /// [mockUserToken] is rejected without it, so that the unsigned token is
  /// never sent to a production host.
  FirestoreSettings._({
    required String host,
    required this.port,
    required bool sslEnabled,
    required bool persistenceEnabled,
    required int cacheSizeBytes,
    required this.cacheSettings,
    required bool emulator,
    required Object? mockUserToken,
  })  : _emulator = emulator,
        host = _checkHost(host),
        sslEnabled = _checkSslEnabled(sslEnabled, host),
        mockUserToken =
            _checkMockUserToken(mockUserToken, emulator, host, sslEnabled),
        persistenceEnabled = _resolvePersistenceEnabled(
            persistenceEnabled, cacheSizeBytes, cacheSettings),
        cacheSizeBytes = _resolveCacheSizeBytes(
            persistenceEnabled, cacheSizeBytes, cacheSettings),
        assert(
            !persistenceEnabled ||
                cacheSizeBytes == cacheSizeUnlimited ||
                cacheSizeBytes >= _minimumCacheBytes,
            'Cache size must be set to at least $_minimumCacheBytes bytes');

  /// The host of the production Firestore service.
  static const String defaultHost = 'firestore.googleapis.com';

  /// The port of the production Firestore service.
  static const int defaultPort = 443;

  /// Constant to use with [cacheSizeBytes] to disable garbage collection.
  static const int cacheSizeUnlimited = -1;

  /// The minimum cache size, 1 MB.
  static const int minimumCacheBytes = 1 * 1024 * 1024;
  static const int _minimumCacheBytes = minimumCacheBytes;

  /// The cache size threshold used when none is configured (100 MB).
  static const int defaultCacheSizeBytes = 100 * 1024 * 1024; // 100 MB

  /// The host of the Firestore backend.
  final String host;

  /// The port of the Firestore backend. Defaults to 443.
  final int port;

  /// Enables or disables SSL for communication. The default is to use SSL.
  final bool sslEnabled;

  /// Enables or disables local persistent storage. The default is to use local
  /// persistent storage.
  ///
  /// When [cacheSettings] is set this is derived from it: true for
  /// [PersistentCacheSettings], false for [MemoryCacheSettings].
  final bool persistenceEnabled;

  /// Sets an approximate cache size threshold for the on-disk data. If the
  /// cache grows beyond this size, Firestore will start removing data that
  /// hasn't been recently used. The size is not a guarantee that the cache will
  /// stay below that size, only that if the cache exceeds the given size,
  /// cleanup will be attempted.
  ///
  /// By default, collection is enabled with a cache size of 100 MB. The minimum
  /// value is 1 MB.
  ///
  /// When [cacheSettings] is set this is derived from it: the size of the
  /// [PersistentCacheSettings], [cacheSizeUnlimited] for [MemoryCacheSettings].
  final int cacheSizeBytes;

  /// Configures the local cache with [PersistentCacheSettings] or
  /// [MemoryCacheSettings]. It replaces [persistenceEnabled] and
  /// [cacheSizeBytes]: passing it together with a non default value of either
  /// throws a [StateError]. When null, the cache is configured by those two
  /// settings.
  final LocalCacheSettings? cacheSettings;

  /// The token sent to the Firestore emulator to authenticate the requests,
  /// set with [withEmulator] (the only way to set it: it is never sent to a
  /// host that was not configured as an emulator). Same as the `mockUserToken` option of
  /// `connectFirestoreEmulator` in the JS SDK; meant for testing security
  /// rules, it replaces the token of Firebase Auth.
  ///
  /// Either a token string, sent as is (the user is `mock-user`), or a
  /// `Map<String, Object?>` with the claims of a Firebase ID token, which is
  /// encoded as an unsigned JWT for the project of the app. The claims need a
  /// `sub` or `user_id`, which becomes the user id; missing claims get
  /// defaults. For example `{'sub': 'alice', 'email': 'alice@example.com'}`.
  final Object? mockUserToken;

  /// Whether these settings were made by [withEmulator] (and the host was not
  /// changed afterwards).
  final bool _emulator;

  static final RegExp _notHostCharacters = RegExp(r'[/@?#\\\s]');

  /// [host] is used as the authority of the URLs and connections of the
  /// transport. Anything that could change which server that is (a user info
  /// part, a path, a scheme) is rejected: requests carry credentials.
  static String _checkHost(String host) {
    if (host.isEmpty || _notHostCharacters.hasMatch(host)) {
      throw ArgumentError.value(host, 'host',
          'Must be a host name or an IP address, without scheme, user info or path');
    }
    return host;
  }

  /// Whether [host] names the production Firestore service, however it is
  /// spelled (host names are case insensitive and may end with a dot).
  static bool _isProductionHost(String host) {
    String normalized = host.trim().toLowerCase();
    while (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized == defaultHost;
  }

  /// TLS can be turned off only for another host than the production one (an
  /// emulator or a proxy the caller configured). Checked in every build mode:
  /// without TLS the auth token of every request would be sent in clear text.
  static bool _checkSslEnabled(bool sslEnabled, String host) {
    if (!sslEnabled && _isProductionHost(host)) {
      throw ArgumentError.value(
          sslEnabled,
          'sslEnabled',
          "You can't turn off SSL for the production host '$defaultHost'; "
              "set a different 'host' (for example with withEmulator) first");
    }
    return sslEnabled;
  }

  static Object? _checkMockUserToken(
      Object? mockUserToken, bool emulator, String host, bool sslEnabled) {
    if (mockUserToken == null) {
      return null;
    }
    if (!emulator || _isProductionHost(host) || sslEnabled) {
      throw ArgumentError.value(
          host,
          'host',
          'mockUserToken can only be used with the Firestore emulator: set it '
              'with withEmulator(host, port, mockUserToken: ...) and do not '
              'change the host, port or SSL setting afterwards');
    }
    if (mockUserToken is String) {
      return mockUserToken;
    }
    if (mockUserToken is Map<String, Object?>) {
      // Rejects a missing "sub" / "user_id" and the old "uid" claim now
      // rather than when the instance is created.
      createMockUserToken(mockUserToken);
      return Map<String, Object?>.unmodifiable(mockUserToken);
    }
    throw ArgumentError.value(mockUserToken, 'mockUserToken',
        'Must be a String or a Map<String, Object?> of token claims');
  }

  static bool _resolvePersistenceEnabled(bool persistenceEnabled,
      int cacheSizeBytes, LocalCacheSettings? cacheSettings) {
    if (cacheSettings == null) {
      return persistenceEnabled;
    }
    _checkNotMixed(persistenceEnabled, cacheSizeBytes);
    return cacheSettings is PersistentCacheSettings;
  }

  static int _resolveCacheSizeBytes(bool persistenceEnabled, int cacheSizeBytes,
      LocalCacheSettings? cacheSettings) {
    if (cacheSettings == null) {
      return cacheSizeBytes;
    }
    _checkNotMixed(persistenceEnabled, cacheSizeBytes);
    return cacheSettings is PersistentCacheSettings
        ? cacheSettings.sizeBytes
        : cacheSizeUnlimited;
  }

  static void _checkNotMixed(bool persistenceEnabled, int cacheSizeBytes) {
    if (!persistenceEnabled || cacheSizeBytes != defaultCacheSizeBytes) {
      throw StateError(
          'Given settings mix both cache config APIs: cacheSettings together '
          'with persistenceEnabled or cacheSizeBytes. Use only one of them.');
    }
  }

  /// Returns a copy that talks to the Firestore emulator listening on [host]
  /// and [port], without SSL. Equivalent to `useEmulator` of the other
  /// SDKs; it has to be applied to the settings that are passed when the
  /// instance is created. A host that was set before is replaced.
  ///
  /// [mockUserToken] authenticates the requests to the emulator, see
  /// [FirestoreSettings.mockUserToken]. Like `connectFirestoreEmulator`, the
  /// emulator options replace the previous ones: without [mockUserToken] the
  /// copy has none.
  ///
  /// Throws an [ArgumentError] when [host] is the production host
  /// ([defaultHost]).
  FirestoreSettings withEmulator(String host, int port,
      {Object? mockUserToken}) {
    if (_isProductionHost(host)) {
      throw ArgumentError.value(
          host, 'host', 'The production host is not an emulator');
    }
    return _copy(
        host: host,
        port: port,
        sslEnabled: false,
        emulator: true,
        mockUserToken: mockUserToken);
  }

  /// A copy of these settings with the given values replaced.
  FirestoreSettings copyWith({
    String? host,
    int? port,
    bool? sslEnabled,
    bool? persistenceEnabled,
    int? cacheSizeBytes,
    LocalCacheSettings? cacheSettings,
  }) {
    // The settings stay emulator settings (and keep their mock user token)
    // only while they point at the same emulator. Changing the host of
    // settings that have a token is an error: see [_checkMockUserToken].
    final bool emulator = _emulator &&
        (host ?? this.host) == this.host &&
        (port ?? this.port) == this.port &&
        !(sslEnabled ?? this.sslEnabled);
    return _copy(
      host: host,
      port: port,
      sslEnabled: sslEnabled,
      persistenceEnabled: persistenceEnabled,
      cacheSizeBytes: cacheSizeBytes,
      cacheSettings: cacheSettings,
      emulator: emulator,
      mockUserToken: mockUserToken,
    );
  }

  FirestoreSettings _copy({
    String? host,
    int? port,
    bool? sslEnabled,
    bool? persistenceEnabled,
    int? cacheSizeBytes,
    LocalCacheSettings? cacheSettings,
    required bool emulator,
    required Object? mockUserToken,
  }) {
    // The persistence flags are derived when there are cache settings, so only
    // the explicitly given ones are forwarded (and checked) in that case.
    final LocalCacheSettings? newCacheSettings =
        cacheSettings ?? this.cacheSettings;
    return FirestoreSettings._(
      host: host ?? this.host,
      port: port ?? this.port,
      sslEnabled: sslEnabled ?? this.sslEnabled,
      // Flags that these settings derived from their own cache settings are not forwarded. Flags that were set
      // directly are, so that adding cache settings to them is reported as mixing both APIs, as in the constructor.
      persistenceEnabled: persistenceEnabled ??
          (this.cacheSettings != null || this.persistenceEnabled),
      cacheSizeBytes: cacheSizeBytes ??
          (this.cacheSettings == null
              ? this.cacheSizeBytes
              : defaultCacheSizeBytes),
      cacheSettings: newCacheSettings,
      emulator: emulator,
      mockUserToken: mockUserToken,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirestoreSettings &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          sslEnabled == other.sslEnabled &&
          persistenceEnabled == other.persistenceEnabled &&
          cacheSizeBytes == other.cacheSizeBytes &&
          cacheSettings == other.cacheSettings &&
          const DeepCollectionEquality()
              .equals(mockUserToken, other.mockUserToken);

  @override
  int get hashCode =>
      host.hashCode ^ //
      port.hashCode ^
      sslEnabled.hashCode ^
      persistenceEnabled.hashCode ^
      cacheSizeBytes.hashCode ^
      cacheSettings.hashCode ^
      const DeepCollectionEquality().hash(mockUserToken);

  @override
  String toString() {
    return (ToStringHelper(FirestoreSettings)
          ..add('host', host)
          ..add('port', port)
          ..add('sslEnabled', sslEnabled)
          ..add('persistenceEnabled', persistenceEnabled)
          ..add('cacheSizeBytes', cacheSizeBytes)
          ..add('cacheSettings', cacheSettings)
          ..add('mockUserToken', mockUserToken == null ? null : '<set>'))
        .toString();
  }
}
