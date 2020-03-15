// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';

/// Settings used to configure a FirebaseFirestore instance.
class FirestoreSettings {
  /// Constructs a FirebaseFirestoreSettings object
  FirestoreSettings({
    this.host = _defaultHost,
    this.sslEnabled = true,
    this.persistenceEnabled = true,
    this.cacheSizeBytes = _defaultCacheSizeBytes,
  })  : assert(host != null, 'Provided host must not be null.'),
        assert(!(!sslEnabled && host == _defaultHost),
            "You can't set the 'sslEnabled' setting unless you also set a non-default 'host'."),
        assert(
            !persistenceEnabled ||
                cacheSizeBytes == cacheSizeUnlimited ||
                cacheSizeBytes > _minimumCacheBytes,
            'Cache size must be set to at least $_minimumCacheBytes bytes');

  static const String _defaultHost = 'firestore.googleapis.com';

  /// Constant to use with [cacheSizeBytes] to disable garbage collection.
  static const int cacheSizeUnlimited = -1;

  static const int _minimumCacheBytes = 1 * 1024 * 1024; // 1 MB
  static const int _defaultCacheSizeBytes = 100 * 1024 * 1024; // 100 MB

  /// The host of the Firestore backend.
  final String host;

  /// Enables or disables SSL for communication. The default is to use SSL.
  final bool sslEnabled;

  /// Enables or disables local persistent storage. The default is to use local
  /// persistent storage.
  final bool persistenceEnabled;

  /// Sets an approximate cache size threshold for the on-disk data. If the
  /// cache grows beyond this size, Firestore will start removing data that
  /// hasn't been recently used. The size is not a guarantee that the cache will
  /// stay below that size, only that if the cache exceeds the given size,
  /// cleanup will be attempted.
  ///
  /// By default, collection is enabled with a cache size of 100 MB. The minimum
  /// value is 1 MB.
  final int cacheSizeBytes;

  FirestoreSettings copyWith({
    String host,
    bool sslEnabled,
    bool persistenceEnabled,
    int cacheSizeBytes,
  }) {
    return FirestoreSettings(
      host: host ?? this.host,
      sslEnabled: sslEnabled ?? this.sslEnabled,
      persistenceEnabled: persistenceEnabled ?? this.persistenceEnabled,
      cacheSizeBytes: cacheSizeBytes ?? this.cacheSizeBytes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirestoreSettings &&
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
    return (ToStringHelper(FirestoreSettings)
          ..add('host', host)
          ..add('sslEnabled', sslEnabled)
          ..add('persistenceEnabled', persistenceEnabled)
          ..add('cacheSizeBytes', cacheSizeBytes))
        .toString();
  }
}
