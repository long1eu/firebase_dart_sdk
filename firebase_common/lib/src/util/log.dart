// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

// ignore: avoid_classes_with_only_static_members
class Log {
  static bool get isDebugEnabled => level >= LogLevel.d;
  static LogLevel level = LogLevel.d;

  static void i(String tag, dynamic message) {
    if (level >= LogLevel.i) {
      print('${_formatTag('I:$tag')}||$message');
    }
  }

  static void d(String tag, dynamic message) {
    if (level >= LogLevel.d) {
      print('${_formatTag('D:$tag')}||$message');
    }
  }

  static void w(String tag, dynamic message) {
    if (level >= LogLevel.w) {
      print('${_formatTag('W:$tag')}||$message');
    }
  }

  static void e(String tag, dynamic message) {
    if (level >= LogLevel.e) {
      print('${_formatTag('E:$tag')}||$message');
    }
  }

  static String _formatTag(String tag) => tag.padRight(30, ' ');
}

class LogLevel implements Comparable<LogLevel> {
  final int _i;

  const LogLevel(this._i);

  static const LogLevel i = LogLevel(0);
  static const LogLevel d = LogLevel(1);
  static const LogLevel w = LogLevel(2);
  static const LogLevel e = LogLevel(3);

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
