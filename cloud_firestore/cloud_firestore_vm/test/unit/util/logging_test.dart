import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/cloud_firestore_vm.dart';
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
