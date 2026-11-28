## 0.1.0-dev.1

Not released.

- First version: an implementation of `FirebaseAnalyticsPlatform` (the platform interface of the official
  `firebase_analytics` plugin) on top of `firebase_analytics_dart`, so that an app keeps the official API on Windows
  and Linux, where `firebase_analytics` has no implementation.
- Registers itself on Windows and Linux; `FirebaseAnalyticsDart.configure()` sets the transport, the measurement id,
  the store and the HTTP client, and selects the package on any other platform. Under `flutter test` the registration
  leaves `firebase_core` alone.
- A small pure-Dart `firebase_core` implementation, installed on Linux only while `firebase_core` has no other one.
- One client per FlutterFire app, created on first use, with one store per isolate by default (a `FileAnalyticsStore`
  in `firebase_dart_analytics` under the application support directory on the VM, memory on the web).
- Every method of the platform interface is mapped as `docs/analytics_parity.md` lists it. `logScreenView` is sent as
  `page_view`; `setSessionTimeoutDuration` works before the first event and throws a `StateError` after it;
  `logTransaction` and `initiateOnDeviceConversionMeasurement` throw `UnimplementedError`; `ad_impression` and
  `in_app_purchase` are refused with `reserved-name`.
- The rules of the client surface as `FirebaseException`s of `firebase_core` with the plugin `firebase_analytics` and
  the client's code.
- `AppLifecycleListener` tells the client when the app is in use, from the first call after the binding exists.
