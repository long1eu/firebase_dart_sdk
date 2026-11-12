import 'dart:async';
import 'dart:js_interop';

import 'package:rxdart/rxdart.dart';
import 'package:web/web.dart' as web;

/// Returns the connectivity the client should listen to: the one of the app
/// (`PlatformDependencies.onNetworkConnected`) plus the `online` and `offline`
/// events of the browser, like the `BrowserConnectivityMonitor` of the JS SDK.
///
/// The client restarts its streams when the network comes back, instead of
/// waiting for their backoff. The events are only listened to while the
/// returned subject has a listener.
BehaviorSubject<bool> withPlatformConnectivity(
  BehaviorSubject<bool> onNetworkConnected,
) {
  // A window or a worker; both dispatch the events.
  final web.EventTarget target = globalContext as web.EventTarget;
  late final BehaviorSubject<bool> subject;
  StreamSubscription<bool>? appSub;
  final JSFunction onOnline = ((web.Event _) => subject.add(true)).toJS;
  final JSFunction onOffline = ((web.Event _) => subject.add(false)).toJS;

  subject = BehaviorSubject<bool>.seeded(
    onNetworkConnected.valueOrNull ?? true,
    onListen: () {
      // The seed of the app is already the seed of this subject.
      appSub = onNetworkConnected.skip(1).listen(subject.add);
      target.addEventListener('online', onOnline);
      target.addEventListener('offline', onOffline);
    },
    onCancel: () {
      target.removeEventListener('online', onOnline);
      target.removeEventListener('offline', onOffline);
      final StreamSubscription<bool>? sub = appSub;
      appSub = null;
      sub?.cancel();
    },
  );
  return subject;
}
