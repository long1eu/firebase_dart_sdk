// The cache value types of FlutterFire firebase_data_connect 0.4.2 (commit 6a80b1b),
// lib/src/cache/cache_data_types.dart. Apache License 2.0; see NOTICE. 0.1.0 has no cache: a
// CacheSettings is accepted and ignored with a warning.

import 'package:firebase_data_connect_dart/src/environment_stub.dart'
    if (dart.library.io) 'package:firebase_data_connect_dart/src/environment_io.dart';

/// Where a cache would keep its results.
enum CacheStorage {
  /// On disk.
  persistent,

  /// In memory.
  memory,
}

/// Cache settings. Accepted and ignored in 0.1.0: every query goes to the server.
class CacheSettings {
  const CacheSettings._internal({required this.storage, required this.maxAge});

  /// Settings with [storage] (by default [CacheStorage.memory] on the web and
  /// [CacheStorage.persistent] elsewhere) and [maxAge].
  factory CacheSettings({
    CacheStorage? storage,
    Duration maxAge = Duration.zero,
  }) {
    return CacheSettings._internal(
      storage:
          storage ?? (isWeb ? CacheStorage.memory : CacheStorage.persistent),
      maxAge: maxAge,
    );
  }

  /// Where the results would be kept.
  final CacheStorage storage;

  /// How long a result would be used before it is fetched again.
  final Duration maxAge;
}

/// Where a query is answered from. With no cache in 0.1.0, [preferCache] and [serverOnly] go to
/// the server and [cacheOnly] fails with `DataConnectErrorCode.cacheMiss`.
enum QueryFetchPolicy {
  /// The cache when it holds a fresh result, else the server.
  preferCache,

  /// Only the cache.
  cacheOnly,

  /// Only the server.
  serverOnly,
}
