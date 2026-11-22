/// Argument validation of keys, paths, priorities and data. JS: `core/util/validation.ts`;
/// Android: `core/utilities/Validation.java`, `core/ValidationPath.java` (data checks).
///
/// Failures throw [ArgumentError] with the JS message text.
library;

import 'package:firebase_database_dart/src/core/path.dart';

/// Characters a key may not contain.
final RegExp invalidKeyRegex = RegExp(r'[\[\].#$\/\u0000-\u001F\u007F]');

/// Characters a path may not contain.
final RegExp invalidPathRegex = RegExp(r'[\[\].#$\u0000-\u001F\u007F]');

/// The largest string leaf, in UTF-8 bytes.
const int maxLeafSize = 10 * 1024 * 1024;

/// Whether [key] is a non-empty string without invalid characters.
bool isValidKey(Object? key) => throw UnimplementedError();

/// Whether [pathString] is a valid path.
bool isValidPathString(String pathString) => throw UnimplementedError();

/// Whether [pathString] is a valid path that may start with `.info`.
bool isValidRootPathString(String pathString) => throw UnimplementedError();

/// Whether [priority] is null, a finite number, a string or a server value.
bool isValidPriority(Object? priority) => throw UnimplementedError();

/// Validates [data] for a write at [path] by [fnName].
void validateFirebaseDataArg(
  String fnName,
  Object? data,
  Path path, {
  bool optional = false,
}) => throw UnimplementedError();

/// Validates [data] below [path], recursively.
void validateFirebaseData(
  String errorPrefix,
  Object? data,
  ValidationPath path,
) => throw UnimplementedError();

/// Validates that no path of [mergePaths] is a prefix of another.
void validateFirebaseMergePaths(String errorPrefix, List<Path> mergePaths) =>
    throw UnimplementedError();

/// Validates the argument of `update` at [path].
void validateFirebaseMergeDataArg(
  String fnName,
  Object? data,
  Path path, {
  bool optional = false,
}) => throw UnimplementedError();

/// Validates a priority argument.
void validatePriority(
  String fnName,
  Object? priority, {
  bool optional = false,
}) => throw UnimplementedError();

/// Validates a key argument named [argumentName].
void validateKey(
  String fnName,
  String argumentName,
  String? key, {
  bool optional = false,
}) => throw UnimplementedError();

/// Validates a path argument named [argumentName].
void validatePathString(
  String fnName,
  String argumentName,
  String? pathString, {
  bool optional = false,
}) => throw UnimplementedError();

/// Validates a root path argument (may start with `.info`).
void validateRootPathString(
  String fnName,
  String argumentName,
  String? pathString, {
  bool optional = false,
}) => throw UnimplementedError();

/// Throws if [path] is under `.info`, which cannot be written.
void validateWritablePath(String fnName, Path path) =>
    throw UnimplementedError();
