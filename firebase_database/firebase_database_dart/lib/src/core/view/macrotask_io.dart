/// The event dispatcher's yield outside a browser: `Timer.run`. Selected by
/// `event_dispatcher.dart` when `dart:io` is available.
library;

import 'dart:async';

/// Runs [callback] in a later turn of the event loop (`Timer.run`), in the current zone.
void scheduleMacrotask(void Function() callback) => Timer.run(callback);
