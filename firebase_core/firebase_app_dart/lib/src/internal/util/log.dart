// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

// ignore: avoid_classes_with_only_static_members
class Log {
  /// Whether [d] currently prints. Use it to avoid building expensive messages.
  static bool get isDebugEnabled => level <= LogLevel.d;

  /// Messages below this level are dropped. Quiet by default (warnings and
  /// errors only), like the Java SDK; `Firestore.setLoggingEnabled(true)`
  /// turns debug output on.
  static LogLevel level = LogLevel.w;

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

  static void i(String tag, dynamic message) {
    if (level <= LogLevel.i) {
      print('${_formatTag('I:$tag')}||${truncate('$message')}');
    }
  }

  static void d(String tag, dynamic message) {
    if (level <= LogLevel.d) {
      print('${_formatTag('D:$tag')}||${truncate('$message')}');
    }
  }

  static void w(String tag, dynamic message) {
    if (level <= LogLevel.w) {
      print('${_formatTag('W:$tag')}||${truncate('$message')}');
    }
  }

  static void e(String tag, dynamic message) {
    if (level <= LogLevel.e) {
      print('${_formatTag('E:$tag')}||${truncate('$message')}');
    }
  }

  static String _formatTag(String tag) => tag.padRight(30, ' ');
}

class LogLevel implements Comparable<LogLevel> {
  const LogLevel._(this._i);

  final int _i;

  static const LogLevel i = LogLevel._(0);
  static const LogLevel d = LogLevel._(1);
  static const LogLevel w = LogLevel._(2);
  static const LogLevel e = LogLevel._(3);

  @override
  int compareTo(LogLevel other) => _i.compareTo(other._i);

  bool operator <=(LogLevel other) => _i <= other._i;

  bool operator >=(LogLevel other) => _i >= other._i;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogLevel && runtimeType == other.runtimeType && _i == other._i;

  @override
  int get hashCode => _i.hashCode * 31;
}
