// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'package:firebase_common/firebase_common.dart';

/// Settings used to configure a FirebaseFirestore instance.
@publicApi
class FirebaseFirestoreSettings {
  /// Constructs a FirebaseFirestoreSettings object
  FirebaseFirestoreSettings({
    this.host = _defaultHost,
    this.sslEnabled = true,
    this.persistenceEnabled = true,
    this.cacheSizeBytes = _defaultCacheSizeBytes,
  })  : assert(host != null, 'Provided host must not be null.'),
        assert(!(!sslEnabled && host == _defaultHost),
            'You can"t set the "sslEnabled" setting unless you also set a non-default "host".'),
        assert(!persistenceEnabled || cacheSizeBytes == cacheSizeUnlimited || cacheSizeBytes > _minimumCacheBytes,
            'Cache size must be set to at least $_minimumCacheBytes bytes');

  static const String _defaultHost = 'firestore.googleapis.com';

  /// Constant to use with [cacheSizeBytes] to disable garbage collection.
  @publicApi
  static const int cacheSizeUnlimited = -1;

  static const int _minimumCacheBytes = 1 * 1024 * 1024; // 1 MB

  // TODO(long1eu): Set this to be the default value after SDK is past version 1.0
  //  static const long _defaultCacheSizeBytes = 100 * 1024 * 1024; // 100 MB
  //
  //  For now, we are rolling this out with collection disabled. Once the SDK has hit version 1.0, we will switch the
  //  default to the above value, 100 MB.
  static const int _defaultCacheSizeBytes = cacheSizeUnlimited;

  /// The host of the Firestore backend.
  @publicApi
  final String host;

  /// Enables or disables SSL for communication. The default is to use SSL.
  @publicApi
  final bool sslEnabled;

  /// Enables or disables local persistent storage. The default is to use local persistent storage.
  @publicApi
  final bool persistenceEnabled;

  /// Sets an approximate cache size threshold for the on-disk data. If the cache grows beyond this size, Firestore will
  /// start removing data that hasn't been recently used. The size is not a guarantee that the cache will stay below
  /// that size, only that if the cache exceeds the given size, cleanup will be attempted.
  ///
  /// By default, collection is disabled (the value is set to [cacheSizeUnlimited]). In a future release, collection
  /// will be enabled by default, with a default cache size of 100 MB. The minimum value is 1 MB.
  @publicApi
  final int cacheSizeBytes;

  FirebaseFirestoreSettings copyWith({
    String host,
    bool sslEnabled,
    bool persistenceEnabled,
    int cacheSizeBytes,
  }) {
    return FirebaseFirestoreSettings(
      host: host ?? this.host,
      sslEnabled: sslEnabled ?? this.sslEnabled,
      persistenceEnabled: persistenceEnabled ?? this.persistenceEnabled,
      cacheSizeBytes: cacheSizeBytes ?? this.cacheSizeBytes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirebaseFirestoreSettings &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          sslEnabled == other.sslEnabled &&
          persistenceEnabled == other.persistenceEnabled &&
          cacheSizeBytes == other.cacheSizeBytes;

  @override
  int get hashCode =>
      host.hashCode ^ //
      sslEnabled.hashCode ^
      persistenceEnabled.hashCode ^
      cacheSizeBytes.hashCode;

  @override
  String toString() {
    return (ToStringHelper(FirebaseFirestoreSettings)
          ..add('host', host)
          ..add('sslEnabled', sslEnabled)
          ..add('persistenceEnabled', persistenceEnabled)
          ..add('cacheSizeBytes', cacheSizeBytes))
        .toString();
  }
}
