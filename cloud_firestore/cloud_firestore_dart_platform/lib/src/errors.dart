import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';

/// The plugin name FlutterFire puts on the exceptions of Firestore.
const String firestorePlugin = 'cloud_firestore';

/// [error] as the official plugin would report it.
///
/// `cloud_firestore_dart` throws a `FirestoreException`, which extends the
/// `FirebaseException` of `firebase_app_dart` and carries the FlutterFire
/// `plugin` and `code`. Apps catch the `FirebaseException` of `firebase_core`,
/// a different class, so the fields are copied over. Anything else is returned
/// unchanged.
Object convertError(Object error, [StackTrace? stackTrace]) {
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
/// [FirebaseException]s.
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

/// Runs [body] synchronously and rethrows its `firebase_app_dart` exceptions
/// as [FirebaseException]s.
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

/// [stream] with its `firebase_app_dart` exceptions turned into
/// [FirebaseException]s.
Stream<T> guardStream<T>(Stream<T> stream) {
  return stream.transform(
    StreamTransformer<T, T>.fromHandlers(
      handleError: (Object error, StackTrace stackTrace, EventSink<T> sink) {
        sink.addError(convertError(error, stackTrace), stackTrace);
      },
    ),
  );
}
