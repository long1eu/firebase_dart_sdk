// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;

const int _autoIdLength = 20;

const String _autoIdAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

final Random rand = Random();

const int _maxLoggedMessageBytes = 128 * 1024;

/// Describes a proto [message] for debug logging. Messages that serialize to
/// more than 128 KiB (e.g. a write of a very large document) are not turned
/// into JSON, which could exhaust memory; a type and size marker is returned
/// instead.
String describeForLog(GeneratedMessage message) {
  final int size = message.writeToBuffer().length;
  if (size > _maxLoggedMessageBytes) {
    final String readable = size >= 1024 * 1024
        ? '${(size / (1024 * 1024)).toStringAsFixed(2)} MB'
        : '${(size / 1024).toStringAsFixed(1)} KB';
    return '<${message.runtimeType} truncated for logging (Size: $readable)>';
  }
  return '${message.toProto3Json()}';
}

String toDebugString(List<int> bytes) {
  final int size = bytes.length;
  final StringBuffer result = StringBuffer();
  for (int i = 0; i < size; i++) {
    final int value = bytes[i] & 0xFF;

    result.write(value.toRadixString(16).padLeft(2, '0'));
  }

  return result.toString();
}

// ignore: avoid_positional_boolean_parameters
int compareBools(bool b1, bool b2) {
  if (b1 == b2) {
    return 0;
  } else if (b1) {
    return 1;
  } else {
    return -1;
  }
}

FirestoreError exceptionFromStatus(GrpcError error) {
  return FirestoreError(
    error.message ?? '',
    FirestoreErrorCode.fromValue(error),
  );
}

/// Compares strings in UTF-8 encoded byte order, without allocating.
///
/// Finds the first differing UTF-16 code unit. If both units are surrogates or
/// neither is, their numeric order equals the UTF-8 byte order of the code
/// points they belong to. Otherwise the string holding the surrogate (a code
/// point above U+FFFF, encoded with 4 bytes) sorts after the other one (1 to 3
/// bytes).
int compareUtf8Strings(String left, String right) {
  if (identical(left, right)) {
    return 0;
  }

  final int length = left.length < right.length ? left.length : right.length;
  for (int i = 0; i < length; i++) {
    final int leftUnit = left.codeUnitAt(i);
    final int rightUnit = right.codeUnitAt(i);
    if (leftUnit != rightUnit) {
      final bool leftSurrogate = _isSurrogate(leftUnit);
      final bool rightSurrogate = _isSurrogate(rightUnit);
      if (leftSurrogate == rightSurrogate) {
        return leftUnit < rightUnit ? -1 : 1;
      }
      return leftSurrogate ? 1 : -1;
    }
  }

  return left.length.compareTo(right.length);
}

bool _isSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDFFF;

// Shared instance so that maps built with comparator() compare equal.
int _compare(dynamic a, dynamic b) => (a as Comparable<dynamic>).compareTo(b);

Comparator<T> comparator<T extends Comparable<T>>() => _compare;

/// Describes the type of an object, handling null objects gracefully.
String typeName(Object? value) {
  return value == null ? 'null' : '${value.runtimeType}';
}

String autoId() {
  final StringBuffer builder = StringBuffer();
  const int maxRandom = _autoIdAlphabet.length;
  for (int i = 0; i < _autoIdLength; i++) {
    builder.writeCharCode(_autoIdAlphabet.codeUnitAt(rand.nextInt(maxRandom)));
  }
  return builder.toString();
}

Future<void> voidErrorTransformer(Future<void> Function() operation) async {
  try {
    await operation();
  } catch (e, s) {
    if (e is FirestoreError) {
      rethrow;
    } else {
      return Future<void>.error(
          FirestoreError('$e', FirestoreErrorCode.unknown), s);
    }
  }
}

/// Converts varargs from an update call to a list of objects, ensuring that the arguments alternate
/// between String/FieldPath and Objects.
///
/// [fieldPathOffset] is the offset of the first field path in the original update API (used as the
/// index in error messages)
List<Object?> collectUpdateArguments(
    int fieldPathOffset, List<Object?> fieldsAndValues) {
  if (fieldsAndValues.length % 2 == 1) {
    throw ArgumentError(
        'Missing value in call to update().  There must be an even number of '
        'arguments that alternate between field names and values');
  }
  final List<Object?> argumentList = fieldsAndValues.toList(growable: false);
  for (int i = 0; i < argumentList.length; i += 2) {
    final Object? fieldPath = argumentList[i];
    if (fieldPath is! String && fieldPath is! FieldPath) {
      throw ArgumentError(
          'Excepted field name at argument position ${i + fieldPathOffset + 1} but '
          'got $fieldPath in call to update. The arguments to update should alternate between '
          'field names and values');
    }
  }

  return argumentList;
}
