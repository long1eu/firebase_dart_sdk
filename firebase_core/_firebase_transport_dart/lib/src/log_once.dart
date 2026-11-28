/// The most ids one [LogOnce] remembers.
const int _maxIds = 256;

/// Passes a message to its sink the first time its id is seen, and drops later messages with that
/// id.
///
/// Used for problems that would otherwise repeat on every call. It remembers at most 256 ids; once
/// it holds that many, a message with a new id is dropped. An id given to [reset] keeps its place,
/// so its next message is logged even when the helper is full.
final class LogOnce {
  /// Creates a helper writing to [sink]; a null sink drops every message.
  LogOnce(void Function(String message)? sink) : _sink = sink;

  final void Function(String message)? _sink;
  final Set<String> _seen = <String>{};
  final Set<String> _forgotten = <String>{};

  /// Passes [message] to the sink unless a message with [id] was passed since the last [reset] of
  /// [id], or [id] is new and 256 ids are already remembered.
  void call(String id, String message) {
    final void Function(String message)? sink = _sink;
    if (sink == null || _seen.contains(id)) {
      return;
    }
    final bool known = _forgotten.remove(id);
    if (!known && _seen.length + _forgotten.length >= _maxIds) {
      return;
    }
    _seen.add(id);
    sink(message);
  }

  /// Forgets [id], so its next message is logged again.
  void reset(String id) {
    if (_seen.remove(id)) {
      _forgotten.add(id);
    }
  }
}
