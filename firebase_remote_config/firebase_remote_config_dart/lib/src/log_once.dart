/// Passes a message to its sink the first time its id is seen, and drops later messages with that id.
///
/// Used for problems that would otherwise repeat on every call, such as a store that keeps failing.
final class LogOnce {
  /// Creates a helper writing to [sink]; a null sink drops every message.
  LogOnce(void Function(String message)? sink) : _sink = sink;

  final void Function(String message)? _sink;
  final Set<String> _seen = <String>{};

  /// Passes [message] to the sink unless a message with [id] was passed before.
  void call(String id, String message) {
    final void Function(String message)? sink = _sink;
    if (sink == null || !_seen.add(id)) {
      return;
    }
    sink(message);
  }
}
