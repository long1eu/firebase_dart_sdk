/// Network reachability from the platform, where it offers it without a
/// plugin: the `online` and `offline` events of browsers, and on `dart:io` a
/// detector of changes of the network interfaces that only runs while a
/// stream is failing (see `ConnectivityChangeDetector`).
library;

export 'connectivity_monitor_none.dart'
    if (dart.library.io) 'connectivity_monitor_io.dart'
    if (dart.library.js_interop) 'connectivity_monitor_web.dart';
