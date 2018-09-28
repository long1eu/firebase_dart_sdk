// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

class Log {
  static bool get isDebugEnabled => _level >= LogLevel.d;
  static LogLevel _level;

  static void i(String tag, dynamic message) {
    if (_level >= LogLevel.i) print('I:$tag||$message');
  }

  static void d(String tag, dynamic message) {
    if (_level >= LogLevel.d) print('D:$tag||$message');
  }

  static void w(String tag, dynamic message) {
    if (_level >= LogLevel.w) print('W:$tag||$message');
  }

  static void e(String tag, dynamic message) {
    if (_level >= LogLevel.e) print('E:$tag||$message');
  }

  static void setLogLevel(LogLevel level) {}
}

class LogLevel implements Comparable<LogLevel> {
  final int _i;

  const LogLevel(this._i);

  static const LogLevel i = const LogLevel(0);
  static const LogLevel d = const LogLevel(1);
  static const LogLevel w = const LogLevel(2);
  static const LogLevel e = const LogLevel(3);

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
