import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:test/test.dart';

void main() {
  final LogLevel original = Log.level;
  tearDown(() => Log.level = original);

  test('logging is quiet by default and setLoggingEnabled toggles debug', () {
    expect(LogLevel.w, original);
    Firestore.setLoggingEnabled(loggingEnabled: true);
    expect(Log.isDebugEnabled, isTrue);
    Firestore.setLoggingEnabled(loggingEnabled: false);
    expect(Log.isDebugEnabled, isFalse);
    expect(Log.level, LogLevel.w);
  });
}
