/// The errors of the client as FlutterFire reports them: one place for the
/// conversion of `firebase_database_dart` exceptions and their codes.
library;

import 'package:firebase_core/firebase_core.dart';

/// The plugin name FlutterFire puts on the exceptions of the Realtime
/// Database.
const String databasePlugin = 'firebase_database';

/// The client codes that FlutterFire spells differently, client code to
/// FlutterFire code. Every other client code passes through unchanged.
///
/// * `write-canceled` is `write-cancelled` on Android and the web.
/// * `operation-failed` is `failure` on Android (`DatabaseError.OPERATION_FAILED`).
const Map<String, String> flutterFireCodes = <String, String>{
  'write-canceled': 'write-cancelled',
  'operation-failed': 'failure',
};

/// The FlutterFire spelling of the client's [code] ([flutterFireCodes]).
String flutterFireCode(String code) => throw UnimplementedError();

/// [error] as the official plugin would report it.
///
/// `firebase_database_dart` throws a `FirebaseDatabaseException`, which extends
/// the `FirebaseException` of `firebase_app_dart` (plugin `firebase_database`).
/// Apps catch the [FirebaseException] of `firebase_core`, a different class,
/// so the fields are copied over, with the code through [flutterFireCode] and
/// the message of the client (never empty). Anything else, `ArgumentError`,
/// `StateError` and the exception a transaction handler threw included, is
/// returned unchanged (the same object).
Object convertError(Object error, [StackTrace? stackTrace]) =>
    throw UnimplementedError();

/// Runs [body] and rethrows its `firebase_app_dart` exceptions as
/// [FirebaseException]s ([convertError]), with the original stack trace.
/// Other errors are rethrown as they are.
Future<T> guard<T>(Future<T> Function() body) => throw UnimplementedError();

/// [stream] with its errors converted by [convertError], data and done passed
/// through.
///
/// One listen of the result is one listen of [stream] (a `Stream.multi` of the
/// client stays one registration per listen); the result is a broadcast
/// stream only when [stream] is one.
Stream<T> guardStream<T>(Stream<T> stream) => throw UnimplementedError();
