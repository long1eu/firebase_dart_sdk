import 'package:firebase_app_dart/internal.dart' as internal;
import 'package:cloud_firestore_dart/src/firebase/firestore/log_level.dart';

/// Sets the level of the internal logger that the SDK writes to.
void applyLogLevel(LogLevel level) {
  internal.Log.level = switch (level) {
    LogLevel.verbose => internal.InternalLogLevel.i,
    LogLevel.debug => internal.InternalLogLevel.d,
    LogLevel.info => internal.InternalLogLevel.info,
    LogLevel.warn => internal.InternalLogLevel.w,
    LogLevel.error => internal.InternalLogLevel.e,
    LogLevel.silent => internal.InternalLogLevel.none,
  };
}

/// Sets the level of the internal logger the way `setLoggingEnabled` did
/// before [LogLevel] existed: debug when enabled, warnings and errors
/// otherwise (the default).
void applyLoggingEnabled(bool enabled) {
  internal.Log.level = enabled
      ? internal.InternalLogLevel.d
      : internal.InternalLogLevel.w;
}
