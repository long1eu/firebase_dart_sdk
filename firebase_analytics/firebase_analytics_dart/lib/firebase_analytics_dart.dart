/// Unofficial pure-Dart client of Google Analytics for Firebase over the GA4 Measurement Protocol.
///
/// Start with [FirebaseAnalytics]. It sends to a GA4 web data stream through an [AnalyticsTransport]: a
/// relay you run (recommended for apps, since the API secret cannot be kept private on a user's machine) or
/// Google directly with the secret (servers and internal tools). File storage of the state and the queue is
/// in `package:firebase_analytics_dart/io.dart`.
library;

import 'src/firebase_analytics.dart';
import 'src/transport.dart';

export 'src/device.dart' show AnalyticsDevice, AnalyticsUserLocation;
export 'src/exception.dart' show FirebaseAnalyticsException;
export 'src/firebase_analytics.dart' show FirebaseAnalytics;
export 'src/limits.dart' show AnalyticsLimits;
export 'src/store.dart' show AnalyticsStore;
export 'src/transport.dart'
    show AnalyticsRegion, AnalyticsTransport, DirectTransport, RelayTransport;
