import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart'
    as fis;
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart'
    as rc;
import 'package:flutter/foundation.dart';

/// The plugin name FlutterFire puts on the exceptions of Remote Config.
const String remoteConfigPlugin = 'firebase_remote_config';

/// [error] as the official plugin would report it.
///
/// A `firebase_app_dart` exception (thrown by `firebase_remote_config_dart`
/// or `firebase_installations_dart`) becomes a [FirebaseException] of
/// `firebase_core` with the plugin `firebase_remote_config`. On the web the
/// client's code is kept (the JS SDK's names, plus `installations-error`,
/// `storage-error` and `remote-config-closed`); on the VM it becomes one of
/// the codes the platform interface documents (see [vmErrorCode]). A
/// [FirebaseException] of this plugin is returned unchanged. Anything else
/// (an [Error], another plugin's exception) becomes `internal`, with a
/// message that names only its type, so that no value it carries leaves.
Object convertError(Object error, [StackTrace? stackTrace]) {
  if (error is FirebaseException && error.plugin == remoteConfigPlugin) {
    return error;
  }
  if (error is! dart_app.FirebaseException) {
    return internalError(
      'Remote Config failed with an unexpected ${error.runtimeType}.',
      stackTrace: stackTrace,
    );
  }
  return FirebaseException(
    plugin: remoteConfigPlugin,
    code: kIsWeb ? error.code : vmErrorCode(error),
    message: _messageOf(error),
    stackTrace: error.stackTrace ?? stackTrace,
  );
}

/// The code FlutterFire's native implementations report for [error].
///
/// `network-error` for a transport failure or a timeout, also of
/// Installations; `throttled` inside a backoff window or after a 429 or
/// another throttling status; `forbidden` for a 403; `remote-config-server-error`
/// for another status; `internal` for anything else.
String vmErrorCode(dart_app.FirebaseException error) {
  if (error is! rc.FirebaseRemoteConfigException) {
    return 'internal';
  }
  switch (error.code) {
    case 'fetch-client-network':
    case 'fetch-timeout':
      return 'network-error';
    case 'installations-error':
      return _installationsCode(error.cause) == 'network-error'
          ? 'network-error'
          : 'internal';
    case 'fetch-throttle':
      return 'throttled';
    case 'fetch-status':
      if (error.throttledUntil != null) {
        return 'throttled';
      }
      return error.httpStatus == 403
          ? 'forbidden'
          : 'remote-config-server-error';
    default:
      return 'internal';
  }
}

/// The message of [error]; for an Installations failure, the message of the
/// Installations exception behind it (for example the store's).
String? _messageOf(dart_app.FirebaseException error) {
  if (error is rc.FirebaseRemoteConfigException) {
    final Object? cause = error.cause;
    if (cause is fis.FirebaseInstallationsException && cause.message != null) {
      return cause.message;
    }
  }
  return error.message;
}

String? _installationsCode(Object? cause) =>
    cause is fis.FirebaseInstallationsException ? cause.code : null;

/// The `internal` [FirebaseException] of this plugin with [message].
FirebaseException internalError(String message, {StackTrace? stackTrace}) =>
    FirebaseException(
      plugin: remoteConfigPlugin,
      code: 'internal',
      message: message,
      stackTrace: stackTrace,
    );

/// Runs [body] and rethrows what it throws as converted by [convertError].
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

/// Runs [body] and rethrows what it throws as converted by [convertError],
/// for the synchronous members.
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

/// [stream] with its errors converted by [convertError], data and done passed
/// through.
///
/// One listen of the result is one listen of [stream]; the result is a
/// broadcast stream only when [stream] is one.
Stream<T> guardStream<T>(Stream<T> stream) => stream.transform(
  StreamTransformer<T, T>.fromHandlers(
    handleError: (Object error, StackTrace stackTrace, EventSink<T> sink) {
      sink.addError(convertError(error, stackTrace), stackTrace);
    },
  ),
);

/// The `invalid-argument` [FirebaseException] for a custom signal that breaks
/// a limit; [error]'s message names the limit and the entry's position.
FirebaseException invalidArgument(ArgumentError error) => FirebaseException(
  plugin: remoteConfigPlugin,
  code: 'invalid-argument',
  message: error.message?.toString() ?? error.toString(),
);
