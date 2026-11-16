import 'dart:async';

import 'package:firebase_app_dart/internal.dart' as internal;
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

void main() {
  final internal.InternalLogLevel original = internal.Log.level;
  tearDown(() => internal.Log.level = original);

  test('logging is quiet by default and setLoggingEnabled toggles debug', () {
    expect(internal.InternalLogLevel.w, original);
    FirebaseFirestore.setLoggingEnabled(true);
    expect(internal.Log.isDebugEnabled, isTrue);
    FirebaseFirestore.setLoggingEnabled(false);
    expect(internal.Log.isDebugEnabled, isFalse);
    expect(internal.Log.level, internal.InternalLogLevel.w);
  });

  group('setLogLevel', () {
    test('debug logs everything', () {
      FirebaseFirestore.setLogLevel(LogLevel.debug);
      expect(internal.Log.level, internal.InternalLogLevel.d);
      expect(internal.Log.isDebugEnabled, isTrue);
    });

    test('error logs errors only', () {
      FirebaseFirestore.setLogLevel(LogLevel.error);
      expect(internal.Log.level, internal.InternalLogLevel.e);
      expect(internal.Log.isDebugEnabled, isFalse);
      expect(internal.Log.level <= internal.InternalLogLevel.w, isFalse);
      expect(internal.Log.level <= internal.InternalLogLevel.e, isTrue);
    });

    test('silent logs nothing', () {
      FirebaseFirestore.setLogLevel(LogLevel.silent);
      expect(internal.Log.level, internal.InternalLogLevel.none);
      expect(internal.Log.level <= internal.InternalLogLevel.e, isFalse);
    });

    test('silent drops every message', () {
      final List<String> printed = <String>[];
      FirebaseFirestore.setLogLevel(LogLevel.silent);
      Zone.root
          .fork(
        specification: ZoneSpecification(
          print: (_, _, _, String line) => printed.add(line),
        ),
      )
          .run(() {
        internal.Log.d('tag', 'debug');
        internal.Log.i('tag', 'info');
        internal.Log.w('tag', 'warn');
        internal.Log.e('tag', 'error');
      });
      expect(printed, isEmpty);

      FirebaseFirestore.setLogLevel(LogLevel.error);
      Zone.root
          .fork(
        specification: ZoneSpecification(
          print: (_, _, _, String line) => printed.add(line),
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

    test('the levels are the JS ones without info, from the most to the least verbose', () {
      expect(LogLevel.values, <LogLevel>[
        LogLevel.verbose,
        LogLevel.debug,
        LogLevel.warn,
        LogLevel.error,
        LogLevel.silent,
      ]);
    });

    test('warn is the default level', () {
      FirebaseFirestore.setLogLevel(LogLevel.debug);
      FirebaseFirestore.setLogLevel(LogLevel.warn);
      expect(internal.Log.level, internal.InternalLogLevel.w);
      expect(internal.Log.level, original);
    });

    test('each level prints its messages and the more severe ones', () {
      List<String> printedAt(LogLevel level) {
        final List<String> printed = <String>[];
        FirebaseFirestore.setLogLevel(level);
        Zone.root
            .fork(
              specification: ZoneSpecification(
                print: (_, _, _, String line) => printed.add(line),
              ),
            )
            .run(() {
              internal.Log.i('tag', 'verbose');
              internal.Log.d('tag', 'debug');
              internal.Log.w('tag', 'warn');
              internal.Log.e('tag', 'error');
            });
        return printed
            .map((String line) => line.split('||').last)
            .toList();
      }

      expect(printedAt(LogLevel.verbose), <String>[
        'verbose',
        'debug',
        'warn',
        'error',
      ]);
      expect(printedAt(LogLevel.debug), <String>['debug', 'warn', 'error']);
      expect(printedAt(LogLevel.warn), <String>['warn', 'error']);
      expect(printedAt(LogLevel.error), <String>['error']);
      expect(printedAt(LogLevel.silent), isEmpty);
    });

    test('setLoggingEnabled still works after setLogLevel', () {
      FirebaseFirestore.setLogLevel(LogLevel.silent);
      FirebaseFirestore.setLoggingEnabled(true);
      expect(internal.Log.level, internal.InternalLogLevel.d);
    });
  });
}
