import 'dart:io';

/// The value of the environment variable [name], or null when it is not set or empty.
String? environmentVariable(String name) {
  final String? value = Platform.environment[name]?.trim();
  return value == null || value.isEmpty ? null : value;
}
