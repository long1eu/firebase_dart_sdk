import 'dart:io';

import 'package:firebase_analytics_dart/firebase_analytics_dart.dart';
import 'package:firebase_analytics_dart/io.dart';
import 'package:path_provider/path_provider.dart';

/// The default store on the VM: a `FileAnalyticsStore` in
/// `firebase_dart_analytics` under the application support directory.
AnalyticsStore createDefaultStore() => ApplicationSupportAnalyticsStore();

/// An [AnalyticsStore] that finds the application support directory on first
/// use, then forwards every call to a [FileAnalyticsStore] in its
/// `firebase_dart_analytics` subdirectory.
///
/// `getApplicationSupportDirectory` is asynchronous and the store is needed
/// synchronously, when the client is created. A failure to find the directory
/// is thrown by the calls waiting for it (the client then fails closed and
/// reports it to its `onWarning`), and the next call tries again.
final class ApplicationSupportAnalyticsStore implements AnalyticsStore {
  Future<AnalyticsStore>? _store;

  Future<AnalyticsStore> get _opened {
    final Future<AnalyticsStore>? existing = _store;
    if (existing != null) {
      return existing;
    }
    final Future<AnalyticsStore> opening = _open();
    _store = opening;
    opening.then<void>(
      (AnalyticsStore _) {},
      onError: (Object _) {
        if (identical(_store, opening)) {
          _store = null;
        }
      },
    );
    return opening;
  }

  static Future<AnalyticsStore> _open() async {
    final Directory support = await getApplicationSupportDirectory();
    return FileAnalyticsStore(
      Directory(
        '${support.path}${Platform.pathSeparator}firebase_dart_analytics',
      ),
    );
  }

  @override
  Future<String?> read(String key) async => (await _opened).read(key);

  @override
  Future<void> write(String key, String? value) async =>
      (await _opened).write(key, value);
}
