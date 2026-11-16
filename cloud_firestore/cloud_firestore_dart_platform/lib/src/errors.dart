import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:firebase_core/firebase_core.dart';

/// The plugin name FlutterFire puts on the exceptions of Firestore.
const String firestorePlugin = 'cloud_firestore';

/// The FlutterFire `code` of a `cloud_firestore_dart` error code: the gRPC
/// status name in kebab case, as the official plugin reports it.
String codeOf(fs.FirestoreErrorCode code) {
  return _codes[code] ?? 'unknown';
}

const Map<fs.FirestoreErrorCode, String> _codes =
    <fs.FirestoreErrorCode, String>{
      fs.FirestoreErrorCode.ok: 'ok',
      fs.FirestoreErrorCode.cancelled: 'cancelled',
      fs.FirestoreErrorCode.unknown: 'unknown',
      fs.FirestoreErrorCode.invalidArgument: 'invalid-argument',
      fs.FirestoreErrorCode.deadlineExceeded: 'deadline-exceeded',
      fs.FirestoreErrorCode.notFound: 'not-found',
      fs.FirestoreErrorCode.alreadyExists: 'already-exists',
      fs.FirestoreErrorCode.permissionDenied: 'permission-denied',
      fs.FirestoreErrorCode.resourceExhausted: 'resource-exhausted',
      fs.FirestoreErrorCode.failedPrecondition: 'failed-precondition',
      fs.FirestoreErrorCode.aborted: 'aborted',
      fs.FirestoreErrorCode.outOfRange: 'out-of-range',
      fs.FirestoreErrorCode.unimplemented: 'unimplemented',
      fs.FirestoreErrorCode.internal: 'internal',
      fs.FirestoreErrorCode.unavailable: 'unavailable',
      fs.FirestoreErrorCode.dataLoss: 'data-loss',
      fs.FirestoreErrorCode.unauthenticated: 'unauthenticated',
    };

/// [error] as the official plugin would report it: a `FirestoreError` becomes a
/// [FirebaseException]; anything else is returned unchanged.
Object convertError(Object error, [StackTrace? stackTrace]) {
  if (error is fs.FirestoreError) {
    return FirebaseException(
      plugin: firestorePlugin,
      code: codeOf(error.code),
      message: error.message,
      stackTrace: error.stackTrace ?? stackTrace,
    );
  }
  return error;
}

/// Runs [body] and rethrows its `FirestoreError`s as [FirebaseException]s.
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

/// Runs [body] synchronously and rethrows its `FirestoreError`s as
/// [FirebaseException]s.
T guardSync<T>(T Function() body) {
  try {
    return body();
  } catch (error, stackTrace) {
    final Object converted = convertError(error, stackTrace);
    if (identical(converted, error)) {
      rethrow;
    }
    Error.throwWithStackTrace(converted, stackTrace);
  }
}

/// [stream] with its `FirestoreError`s turned into [FirebaseException]s.
Stream<T> guardStream<T>(Stream<T> stream) {
  return stream.transform(
    StreamTransformer<T, T>.fromHandlers(
      handleError: (Object error, StackTrace stackTrace, EventSink<T> sink) {
        sink.addError(convertError(error, stackTrace), stackTrace);
      },
    ),
  );
}
