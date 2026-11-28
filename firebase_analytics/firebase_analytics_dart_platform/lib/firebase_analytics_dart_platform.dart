/// An implementation of FlutterFire's Analytics platform interface on top of
/// the pure-Dart Measurement Protocol client `firebase_analytics_dart`.
///
/// An app keeps the official `firebase_analytics` API
/// (`FirebaseAnalytics.instance.logEvent(...)`, `logLogin()`, `setUserId(...)`),
/// and `firebase_analytics_dart` sends the events to a GA4 web data stream:
///
/// * On Windows and Linux, where `firebase_analytics` has no implementation,
///   adding this package registers it: Flutter calls
///   [FirebaseAnalyticsDart.registerWith] before `main`. The app still calls
///   [FirebaseAnalyticsDart.configure] to say where the events go.
/// * On any other platform, [FirebaseAnalyticsDart.configure] also replaces
///   the official implementation.
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   FirebaseAnalyticsDart.configure(
///     transport: AnalyticsTransport.relay(
///       Uri.parse('https://example.com/collect'),
///     ),
///   );
///   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
///   await FirebaseAnalytics.instance.logEvent(name: 'level_up');
/// }
/// ```
library;

import 'dart:io' show Platform;

import 'package:firebase_analytics_dart/firebase_analytics_dart.dart' as fa;
import 'package:firebase_analytics_dart_platform/src/app.dart';
import 'package:firebase_analytics_dart_platform/src/core.dart';
import 'package:firebase_analytics_dart_platform/src/firebase_analytics_platform.dart';
import 'package:firebase_analytics_platform_interface/firebase_analytics_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

export 'package:firebase_analytics_dart/firebase_analytics_dart.dart'
    show
        AnalyticsDevice,
        AnalyticsRegion,
        AnalyticsStore,
        AnalyticsTransport,
        AnalyticsUserLocation;
export 'src/app.dart' show AppCheckProviderFactory, TokenProviderFactory;

/// Selects `firebase_analytics_dart` as the implementation of the official
/// `firebase_analytics` package, and configures it.
abstract final class FirebaseAnalyticsDart {
  static DartFirebaseAnalytics? _registered;

  /// Whether [configure] (or [registerWith]) made this package the Analytics
  /// implementation, and nothing replaced it since.
  static bool get isRegistered {
    final DartFirebaseAnalytics? registered = _registered;
    return registered != null &&
        identical(FirebaseAnalyticsPlatform.instance, registered);
  }

  /// Called by Flutter's plugin registrant on the platforms this package
  /// declares in its pubspec (Windows and Linux), before `main` runs.
  /// Registers the package without a transport, which [configure] then sets.
  /// On Linux it also installs the small pure-Dart `firebase_core`, except
  /// under `flutter test` (`FLUTTER_TEST` is set), where it leaves
  /// `firebase_core` alone so that `setupFirebaseCoreMocks` keeps working.
  static void registerWith() {
    _register(useDartCore: _runningUnderFlutterTest() ? false : null);
  }

  /// Sets where the events of every app go, and makes `firebase_analytics_dart`
  /// the implementation of `firebase_analytics` on any platform. Call it at
  /// the start of `main`, before `Firebase.initializeApp`; calling it again
  /// replaces the whole configuration.
  ///
  /// * [transport] is required in practice: without it the first call of
  ///   `FirebaseAnalytics` throws a [StateError]. Use
  ///   [fa.AnalyticsTransport.relay] in an app shipped to users, since an API
  ///   secret in a program can be extracted; [fa.AnalyticsTransport.direct]
  ///   is for internal tools.
  /// * [measurementId] is the `G-…` id of a GA4 web data stream; by default
  ///   the app's `FirebaseOptions.measurementId`.
  /// * [store] keeps the client id, the user id, user properties, default
  ///   parameters, consent, the collection switch and unsent events. By
  ///   default one store per isolate: on the VM a `FileAnalyticsStore` in
  ///   `firebase_dart_analytics` under the application support directory, on
  ///   the web memory.
  /// * [httpClient] sends the requests (for tests and proxies); by default
  ///   each client creates its own.
  /// * [tokenProviderFor] and [appCheckProviderFor] return, per FlutterFire
  ///   app, the providers of the ID token and the App Check token a relay
  ///   request carries, so that the relay can check them. A
  ///   `firebase_app_dart` app that already exists with the name of the
  ///   FlutterFire app (another platform package of this repository created
  ///   it) keeps its own user provider, and gets this App Check provider when
  ///   it has none.
  /// * [region], [sessionTimeout], [collectionEnabledByDefault],
  ///   [batchDelay], [maxQueuedEvents], [device], [userLocation] and
  ///   [onWarning] are passed to the client as they are.
  ///   `FirebaseAnalytics.setSessionTimeoutDuration` replaces
  ///   [sessionTimeout] before the first event.
  /// * [useDartCore] replaces the implementation of `firebase_core` with a
  ///   small pure-Dart one. By default (null) that happens only on Linux, and
  ///   only while `firebase_core` has no other implementation; pass true to
  ///   force it (for example in tests), false to never do it.
  ///
  /// Throws a [StateError] once a client was created: the configuration is
  /// read then.
  static void configure({
    fa.AnalyticsTransport? transport,
    String? measurementId,
    fa.AnalyticsStore? store,
    http.Client? httpClient,
    TokenProviderFactory? tokenProviderFor,
    AppCheckProviderFactory? appCheckProviderFor,
    fa.AnalyticsRegion region = fa.AnalyticsRegion.global,
    Duration sessionTimeout = const Duration(minutes: 30),
    bool collectionEnabledByDefault = true,
    Duration batchDelay = const Duration(seconds: 5),
    int maxQueuedEvents = 1000,
    fa.AnalyticsDevice? device,
    fa.AnalyticsUserLocation? userLocation,
    void Function(String message)? onWarning,
    bool? useDartCore,
  }) {
    if (DartFirebaseAnalytics.anyStarted) {
      throw StateError(
        'FirebaseAnalyticsDart.configure must be called before the first use '
        'of FirebaseAnalytics.',
      );
    }
    DartFirebaseAnalytics.config = DartAnalyticsConfig(
      transport: transport,
      measurementId: measurementId,
      store: store,
      httpClient: httpClient,
      tokenProviderFor: tokenProviderFor,
      appCheckProviderFor: appCheckProviderFor,
      region: region,
      sessionTimeout: sessionTimeout,
      collectionEnabledByDefault: collectionEnabledByDefault,
      batchDelay: batchDelay,
      maxQueuedEvents: maxQueuedEvents,
      device: device,
      userLocation: userLocation,
      onWarning: onWarning,
    );
    _register(useDartCore: useDartCore);
  }

  /// The `firebase_analytics_dart` client behind
  /// `FirebaseAnalytics.instanceFor(app: app)`, for what the official API does
  /// not have: `flush()`, to send the queue now, and `close()`, which sends it
  /// and releases the client (later calls through `FirebaseAnalytics` then
  /// throw a [StateError]). Only for an app whose `FirebaseAnalytics` this
  /// package implements. Creates the client when there is none yet.
  static Future<fa.FirebaseAnalytics> clientFor(FirebaseApp app) =>
      DartFirebaseAnalytics.forApp(app).client();

  static void _register({bool? useDartCore}) {
    installCoreIfNeeded(force: useDartCore);
    if (!isRegistered) {
      final DartFirebaseAnalytics platform = DartFirebaseAnalytics();
      FirebaseAnalyticsPlatform.instance = platform;
      _registered = platform;
    }
  }
}

/// Whether the program runs under `flutter test`, which sets `FLUTTER_TEST`.
bool _runningUnderFlutterTest() =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
