/// Network reachability from the platform, where it offers it without a
/// plugin: the `online` and `offline` events of browsers.
library;

export 'connectivity_monitor_none.dart'
    if (dart.library.js_interop) 'connectivity_monitor_web.dart';
