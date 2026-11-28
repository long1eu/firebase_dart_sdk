/// The part of Firebase App Check for pure Dart that needs `dart:io`: a debug provider from the
/// process environment. Not available on the web.
library;

import 'dart:io';

import 'package:firebase_app_check_dart/src/provider.dart';
import 'package:meta/meta.dart';

/// A [DebugAppCheckProvider] whose debug token is the value of the environment variable [name].
///
/// A debug token is a secret: set the variable outside the program and keep it out of source
/// control and logs. [environment] replaces the process environment in tests.
///
/// Throws a [StateError] that names the variable, and never its value, when the variable is
/// unset, empty or not a version 4 UUID.
DebugAppCheckProvider debugProviderFromEnvironment({
  String name = 'FIREBASE_APPCHECK_DEBUG_TOKEN',
  @visibleForTesting Map<String, String>? environment,
}) {
  final String? value = (environment ?? Platform.environment)[name];
  if (value == null) {
    throw StateError('The environment variable $name is not set.');
  }
  if (value.isEmpty) {
    throw StateError('The environment variable $name is empty.');
  }
  if (!isValidDebugToken(value)) {
    throw StateError(
      'The environment variable $name does not hold a version 4 UUID.',
    );
  }
  return DebugAppCheckProvider(debugToken: value);
}
