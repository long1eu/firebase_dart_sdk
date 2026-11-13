// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

// ignore: avoid_classes_with_only_static_members
/// Minimal leveled logger that prints to stdout.
class Log {
  /// Whether [d] currently prints. Use it to avoid building expensive messages.
  static bool get isDebugEnabled => level <= InternalLogLevel.d;

  /// Messages below this level are dropped. Quiet by default (warnings and
  /// errors only), like the Java SDK; `Firestore.setLoggingEnabled(true)`
  /// turns debug output on.
  static InternalLogLevel level = InternalLogLevel.w;

  /// Longest message that is printed. Longer messages (for example the
  /// description of a huge document) are cut so that logging can't exhaust
  /// memory or flood the output.
  static const int maxMessageLength = 4096;

  /// Returns [message] cut to [maxMessageLength] characters, with a marker if
  /// something was removed.
  static String truncate(String message) {
    if (message.length <= maxMessageLength) {
      return message;
    }
    return '${message.substring(0, maxMessageLength)}... <message truncated>';
  }

  /// Logs [message] at the most detailed level ([InternalLogLevel.i], below
  /// debug).
  static void i(String tag, dynamic message) {
    if (level <= InternalLogLevel.i) {
      print('${_formatTag('I:$tag')}||${truncate('$message')}');
    }
  }

  /// Logs [message] at debug level.
  static void d(String tag, dynamic message) {
    if (level <= InternalLogLevel.d) {
      print('${_formatTag('D:$tag')}||${truncate('$message')}');
    }
  }

  /// Logs [message] at warning level.
  static void w(String tag, dynamic message) {
    if (level <= InternalLogLevel.w) {
      print('${_formatTag('W:$tag')}||${truncate('$message')}');
    }
  }

  /// Logs [message] at error level.
  static void e(String tag, dynamic message) {
    if (level <= InternalLogLevel.e) {
      print('${_formatTag('E:$tag')}||${truncate('$message')}');
    }
  }

  static String _formatTag(String tag) => tag.padRight(30, ' ');
}

/// The severity of a log message, ordered from [i] (lowest) to [e]:
/// [i] < [d] < [info] < [w] < [e] < [none].
class InternalLogLevel implements Comparable<InternalLogLevel> {
  const InternalLogLevel._(this._i);

  final int _i;

  /// The most detailed level, below debug: what the JS SDK calls `verbose`.
  /// (The name and [Log.i] predate the JS level names.)
  static const InternalLogLevel i = InternalLogLevel._(0);

  /// Debug.
  static const InternalLogLevel d = InternalLogLevel._(1);

  /// Info as in the JS SDK: above debug and below warning.
  static const InternalLogLevel info = InternalLogLevel._(2);

  /// Warning.
  static const InternalLogLevel w = InternalLogLevel._(3);

  /// Error.
  static const InternalLogLevel e = InternalLogLevel._(4);

  /// Above every message level: nothing is printed.
  static const InternalLogLevel none = InternalLogLevel._(5);

  @override
  int compareTo(InternalLogLevel other) => _i.compareTo(other._i);

  /// Whether this level is at most as severe as [other].
  bool operator <=(InternalLogLevel other) => _i <= other._i;

  /// Whether this level is at least as severe as [other].
  bool operator >=(InternalLogLevel other) => _i >= other._i;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InternalLogLevel &&
          runtimeType == other.runtimeType &&
          _i == other._i;

  @override
  int get hashCode => _i.hashCode * 31;
}
