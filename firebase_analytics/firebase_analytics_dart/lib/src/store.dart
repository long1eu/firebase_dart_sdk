/// Where a `FirebaseAnalytics` keeps its state between runs: the client id, the user id, user properties,
/// default parameters, consent, the collection switch, the session and the queue of unsent events.
///
/// A store holds strings under keys. The client chooses the keys and prefixes each with the app name and the
/// measurement id, so several clients can share one store.
///
/// Two stores ship: [AnalyticsStore.memory], the default, which forgets everything when the program ends,
/// and `FileAnalyticsStore` of `package:firebase_analytics_dart/io.dart`, which keeps one file per key in a
/// directory. Implement this interface to keep the state anywhere else (a database, the browser's
/// `localStorage`, a Flutter preferences plugin).
///
/// A store that fails does not throw into the client's methods, and it fails closed. When the state cannot
/// be read (the store throws, or the text is not valid), it may hold an opt-out, so the client collects
/// nothing and leaves the store as it is until `setAnalyticsCollectionEnabled`, `setConsent` or
/// `resetAnalyticsData` is called. A failed write keeps the state in memory and is tried again with the next
/// change. Both are reported to the client's `onWarning`.
abstract interface class AnalyticsStore {
  /// A store that keeps everything in memory.
  factory AnalyticsStore.memory() = _MemoryAnalyticsStore;

  /// The value stored under [key], or null when there is none.
  Future<String?> read(String key);

  /// Stores [value] under [key]; null removes the key.
  Future<void> write(String key, String? value);
}

final class _MemoryAnalyticsStore implements AnalyticsStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}
