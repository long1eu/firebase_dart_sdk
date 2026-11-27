/// The event dispatcher's yield in a browser: a `MessageChannel` post. Selected by
/// `event_dispatcher.dart` on the web; must compile with dart2js and dart2wasm.
///
/// A hidden tab delays timers (about one `setTimeout(0)` per second after a few nested ones) but
/// not messages, and a message is still a task of its own, so rendering and input can run first.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Runs [callback] in a later task of the event loop, in the current zone. Each call uses its
/// own channel and closes both ports when the message arrives, so nothing stays open.
void scheduleMacrotask(void Function() callback) {
  final void Function() run = Zone.current.bindCallbackGuarded(callback);
  final web.MessageChannel channel = web.MessageChannel();
  channel.port1.onmessage = (web.MessageEvent _) {
    channel.port1.close();
    channel.port2.close();
    run();
  }.toJS;
  channel.port2.postMessage(null);
}
