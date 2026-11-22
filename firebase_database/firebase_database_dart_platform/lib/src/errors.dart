/// The errors of the client as FlutterFire reports them: one place for the
/// conversion of `firebase_database_dart` exceptions and their codes.
library;

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;

/// The plugin name FlutterFire puts on the exceptions of the Realtime
/// Database.
const String databasePlugin = 'firebase_database';

/// Every code of the client's `FirebaseDatabaseException`, client code to
/// FlutterFire code. Two are spelled differently:
///
/// * `write-canceled` is `write-cancelled` on Android and the web.
/// * `operation-failed` is `failure` on Android (`DatabaseError.OPERATION_FAILED`).
///
/// `too-big` and `database-closed` have no FlutterFire
/// counterpart and pass through, as every other code does. The client has no
/// `expired-token` or `invalid-token` code (nothing raises them).
const Map<String, String> flutterFireCodes = <String, String>{
  'permission-denied': 'permission-denied',
  'disconnected': 'disconnected',
  'max-retries': 'max-retries',
  'overridden-by-set': 'overridden-by-set',
  'unavailable': 'unavailable',
  'network-error': 'network-error',
  'write-canceled': 'write-cancelled',
  'index-not-defined': 'index-not-defined',
  'operation-failed': 'failure',
  'too-big': 'too-big',
  'database-closed': 'database-closed',
  'unknown': 'unknown',
};

/// The FlutterFire spelling of the client's [code] ([flutterFireCodes]);
/// `unknown` for a code not in the table.
String flutterFireCode(String code) => flutterFireCodes[code] ?? 'unknown';

/// [error] as the official plugin would report it.
///
/// `firebase_database_dart` throws a `FirebaseDatabaseException`, which extends
/// the `FirebaseException` of `firebase_app_dart` (plugin `firebase_database`).
/// Apps catch the [FirebaseException] of `firebase_core`, a different class,
/// so the fields are copied over, with the code through [flutterFireCode] and
/// the message of the client. Another `firebase_app_dart` exception (from a
/// token provider, say) is copied with its plugin and code as they are.
/// Anything else, `ArgumentError`, `StateError` and the exception a
/// transaction handler threw included, is returned unchanged (the same
/// object).
Object convertError(Object error, [StackTrace? stackTrace]) {
  if (error is fs.FirebaseDatabaseException) {
    return FirebaseException(
      plugin: databasePlugin,
      code: flutterFireCode(error.code),
      message: error.message,
      stackTrace: error.stackTrace ?? stackTrace,
    );
  }
  if (error is dart_app.FirebaseException) {
    return FirebaseException(
      plugin: error.plugin,
      code: error.code,
      message: error.message,
      stackTrace: error.stackTrace ?? stackTrace,
    );
  }
  return error;
}

/// Runs [body] and rethrows its `firebase_app_dart` exceptions as
/// [FirebaseException]s ([convertError]), with the original stack trace.
/// Other errors are rethrown as they are.
Future<T> guard<T>(Future<T> Function() body) async {
  try {
    return await body();
  } catch (error, stackTrace) {
    final Object converted = convertError(error, stackTrace);
    if (identical(converted, error)) {
      rethrow;
    }
    Error.throwWithStackTrace(converted, stackTrace);
  }
}

/// [stream] with its errors converted by [convertError], data and done passed
/// through.
///
/// One listen of the result is one listen of [stream] (a `Stream.multi` of the
/// client stays one registration per listen); the result is a broadcast
/// stream only when [stream] is one.
Stream<T> guardStream<T>(Stream<T> stream) => stream.transform(
  StreamTransformer<T, T>.fromHandlers(
    handleError: (Object error, StackTrace stackTrace, EventSink<T> sink) {
      sink.addError(convertError(error, stackTrace), stackTrace);
    },
  ),
);
