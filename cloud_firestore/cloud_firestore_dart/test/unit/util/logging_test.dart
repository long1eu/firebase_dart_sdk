import 'dart:async';

import 'package:firebase_app_dart/internal.dart' as internal;
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

void main() {
  final internal.InternalLogLevel original = internal.Log.level;
  tearDown(() => internal.Log.level = original);

  test('logging is quiet by default and setLoggingEnabled toggles debug', () {
    expect(internal.InternalLogLevel.w, original);
    Firestore.setLoggingEnabled(loggingEnabled: true);
    expect(internal.Log.isDebugEnabled, isTrue);
    Firestore.setLoggingEnabled(loggingEnabled: false);
    expect(internal.Log.isDebugEnabled, isFalse);
    expect(internal.Log.level, internal.InternalLogLevel.w);
  });

  group('setLogLevel', () {
    test('debug logs everything', () {
      Firestore.setLogLevel(LogLevel.debug);
      expect(internal.Log.level, internal.InternalLogLevel.d);
      expect(internal.Log.isDebugEnabled, isTrue);
    });

    test('error logs errors only', () {
      Firestore.setLogLevel(LogLevel.error);
      expect(internal.Log.level, internal.InternalLogLevel.e);
      expect(internal.Log.isDebugEnabled, isFalse);
      expect(internal.Log.level <= internal.InternalLogLevel.w, isFalse);
      expect(internal.Log.level <= internal.InternalLogLevel.e, isTrue);
    });

    test('silent logs nothing', () {
      Firestore.setLogLevel(LogLevel.silent);
      expect(internal.Log.level, internal.InternalLogLevel.none);
      expect(internal.Log.level <= internal.InternalLogLevel.e, isFalse);
    });

    test('silent drops every message', () {
      final List<String> printed = <String>[];
      Firestore.setLogLevel(LogLevel.silent);
      Zone.root
          .fork(
        specification: ZoneSpecification(
          print: (_, __, ___, String line) => printed.add(line),
        ),
      )
          .run(() {
        internal.Log.d('tag', 'debug');
        internal.Log.i('tag', 'info');
        internal.Log.w('tag', 'warn');
        internal.Log.e('tag', 'error');
      });
      expect(printed, isEmpty);

      Firestore.setLogLevel(LogLevel.error);
      Zone.root
          .fork(
        specification: ZoneSpecification(
          print: (_, __, ___, String line) => printed.add(line),
        ),
      )
          .run(() {
        internal.Log.d('tag', 'debug');
        internal.Log.w('tag', 'warn');
        internal.Log.e('tag', 'error');
      });
      expect(printed, hasLength(1));
      expect(printed.single, contains('error'));
    });

    test('setLoggingEnabled still works after setLogLevel', () {
      Firestore.setLogLevel(LogLevel.silent);
      Firestore.setLoggingEnabled(loggingEnabled: true);
      expect(internal.Log.level, internal.InternalLogLevel.d);
    });
  });
}
