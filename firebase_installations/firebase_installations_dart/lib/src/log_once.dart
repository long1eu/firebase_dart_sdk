/// Passes each message id to a sink only the first time, so a repeated failure is logged once.
final class LogOnce {
  /// A helper writing to the sink; with a null sink it drops everything.
  LogOnce(this._sink);

  final void Function(String message)? _sink;
  final Set<String> _seen = <String>{};

  /// Sends [message] to the sink unless a message with [id] was sent before.
  void call(String id, String message) {
    final void Function(String message)? sink = _sink;
    if (sink == null || !_seen.add(id)) {
      return;
    }
    sink(message);
  }

  /// Forgets [id], so its next message is sent again (after the failure it reported has cleared).
  void reset(String id) {
    _seen.remove(id);
  }
}
