import 'package:firebase_analytics_dart/firebase_analytics_dart.dart';

/// The default store on the web: memory. The package registers itself on
/// Windows and Linux only; an app that selects it on the web passes a store of
/// its own to keep the state between page loads.
AnalyticsStore createDefaultStore() => AnalyticsStore.memory();
