// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/local_cache_settings.dart';
import 'package:firebase_app_dart/internal.dart';

/// Settings used to configure a FirebaseFirestore instance.
class FirestoreSettings {
  /// Constructs a FirebaseFirestoreSettings object
  FirestoreSettings({
    this.host = defaultHost,
    this.port = defaultPort,
    this.sslEnabled = true,
    bool persistenceEnabled = true,
    int cacheSizeBytes = defaultCacheSizeBytes,
    this.cacheSettings,
  })  : persistenceEnabled = _resolvePersistenceEnabled(
            persistenceEnabled, cacheSizeBytes, cacheSettings),
        cacheSizeBytes = _resolveCacheSizeBytes(
            persistenceEnabled, cacheSizeBytes, cacheSettings),
        assert(!(!sslEnabled && host == defaultHost),
            "You can't set the 'sslEnabled' setting unless you also set a non-default 'host'."),
        assert(
            !persistenceEnabled ||
                cacheSizeBytes == cacheSizeUnlimited ||
                cacheSizeBytes >= _minimumCacheBytes,
            'Cache size must be set to at least $_minimumCacheBytes bytes');

  static const String defaultHost = 'firestore.googleapis.com';
  static const int defaultPort = 443;

  /// Constant to use with [cacheSizeBytes] to disable garbage collection.
  static const int cacheSizeUnlimited = -1;

  /// The minimum cache size, 1 MB.
  static const int minimumCacheBytes = 1 * 1024 * 1024;
  static const int _minimumCacheBytes = minimumCacheBytes;
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
  FirestoreSettings withEmulator(String host, int port) =>
      copyWith(host: host, port: port, sslEnabled: false);

  FirestoreSettings copyWith({
    String? host,
    int? port,
    bool? sslEnabled,
    bool? persistenceEnabled,
    int? cacheSizeBytes,
    LocalCacheSettings? cacheSettings,
  }) {
    // The persistence flags are derived when there are cache settings, so only
    // the explicitly given ones are forwarded (and checked) in that case.
    final LocalCacheSettings? newCacheSettings =
        cacheSettings ?? this.cacheSettings;
    return FirestoreSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      sslEnabled: sslEnabled ?? this.sslEnabled,
      persistenceEnabled: persistenceEnabled ??
          (newCacheSettings != null || this.persistenceEnabled),
      cacheSizeBytes: cacheSizeBytes ??
          (newCacheSettings == null
              ? this.cacheSizeBytes
              : defaultCacheSizeBytes),
      cacheSettings: newCacheSettings,
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
          cacheSettings == other.cacheSettings;

  @override
  int get hashCode =>
      host.hashCode ^ //
      port.hashCode ^
      sslEnabled.hashCode ^
      persistenceEnabled.hashCode ^
      cacheSizeBytes.hashCode ^
      cacheSettings.hashCode;

  @override
  String toString() {
    return (ToStringHelper(FirestoreSettings)
          ..add('host', host)
          ..add('port', port)
          ..add('sslEnabled', sslEnabled)
          ..add('persistenceEnabled', persistenceEnabled)
          ..add('cacheSizeBytes', cacheSizeBytes)
          ..add('cacheSettings', cacheSettings))
        .toString();
  }
}
