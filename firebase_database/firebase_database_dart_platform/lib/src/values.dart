/// Values between FlutterFire and the client, in both directions.
library;

/// A write value of FlutterFire as the client takes it: a fresh structure in
/// which every `Map`, at any depth and inside lists, is a
/// `Map<String, Object?>` whose keys are the `toString()` of the original
/// keys. On a collision (`{1: 'a', '1': 'b'}`) the later entry wins.
/// Everything else (`null` map values, `.sv`, `.priority` and `.value` keys,
/// numbers, strings, booleans) is kept as it is.
///
/// Ported from FlutterFire's `transformValue`
/// (`firebase_database_platform_interface`
/// `lib/src/method_channel/utils/utils.dart`, BSD-3). Used by `set`,
/// `setWithPriority`, `update`, transaction results and `onDisconnect`.
Object? transformValue(Object? value) => switch (value) {
  Map<Object?, Object?>() => <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in value.entries)
      entry.key.toString(): transformValue(entry.value),
  },
  List<Object?>() => <Object?>[
    for (final Object? element in value) transformValue(element),
  ],
  _ => value,
};

/// A client value as FlutterFire hands it out: a deep, mutable copy, typed as
/// the native plugins type it. A `Map<String, Object?>` of the client becomes
/// a `Map<Object?, Object?>` (a `LinkedHashMap` in the client's key order), a
/// `List<Object?>` a growable `List<Object?>`; `String`, `bool`, `int`,
/// `double` and null are returned as they are.
///
/// The client's snapshot values are unmodifiable and memoised; FlutterFire
/// app code mutates what it reads, so the shim copies, once per snapshot.
Object? mutableCopy(Object? value) => switch (value) {
  Map<Object?, Object?>() => <Object?, Object?>{
    for (final MapEntry<Object?, Object?> entry in value.entries)
      entry.key: mutableCopy(entry.value),
  },
  List<Object?>() => <Object?>[
    for (final Object? element in value) mutableCopy(element),
  ],
  _ => value,
};
