// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

// ignore: avoid_classes_with_only_static_members
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

  static void i(String tag, dynamic message) {
    if (level <= InternalLogLevel.i) {
      print('${_formatTag('I:$tag')}||${truncate('$message')}');
    }
  }

  static void d(String tag, dynamic message) {
    if (level <= InternalLogLevel.d) {
      print('${_formatTag('D:$tag')}||${truncate('$message')}');
    }
  }

  static void w(String tag, dynamic message) {
    if (level <= InternalLogLevel.w) {
      print('${_formatTag('W:$tag')}||${truncate('$message')}');
    }
  }

  static void e(String tag, dynamic message) {
    if (level <= InternalLogLevel.e) {
      print('${_formatTag('E:$tag')}||${truncate('$message')}');
    }
  }

  static String _formatTag(String tag) => tag.padRight(30, ' ');
}

class InternalLogLevel implements Comparable<InternalLogLevel> {
  const InternalLogLevel._(this._i);

  final int _i;

  static const InternalLogLevel i = InternalLogLevel._(0);
  static const InternalLogLevel d = InternalLogLevel._(1);
  static const InternalLogLevel w = InternalLogLevel._(2);
  static const InternalLogLevel e = InternalLogLevel._(3);

  /// Above every message level: nothing is printed.
  static const InternalLogLevel none = InternalLogLevel._(4);

  @override
  int compareTo(InternalLogLevel other) => _i.compareTo(other._i);

  bool operator <=(InternalLogLevel other) => _i <= other._i;

  bool operator >=(InternalLogLevel other) => _i >= other._i;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InternalLogLevel && runtimeType == other.runtimeType && _i == other._i;

  @override
  int get hashCode => _i.hashCode * 31;
}
