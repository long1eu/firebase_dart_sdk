import 'package:firebase_analytics_dart/firebase_analytics_dart.dart';
import 'package:firebase_analytics_dart_platform/src/default_store_io.dart'
    if (dart.library.js_interop) 'package:firebase_analytics_dart_platform/src/default_store_web.dart';

AnalyticsStore? _sharedStore;

/// The store of every per-app client when `FirebaseAnalyticsDart.configure`
/// got none: one per isolate, created on first call.
///
/// On the VM it keeps its files in `firebase_dart_analytics` under the
/// application support directory; on the web it keeps everything in memory.
/// The client prefixes its keys with the app name and the measurement id, so
/// the apps can share it.
AnalyticsStore defaultStore() => _sharedStore ??= createDefaultStore();
