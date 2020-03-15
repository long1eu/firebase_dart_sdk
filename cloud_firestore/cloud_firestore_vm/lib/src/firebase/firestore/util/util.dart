// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore_vm/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:grpc/grpc.dart';

const int _autoIdLength = 20;

const String _autoIdAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

final Random rand = Random();

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

FirebaseFirestoreError exceptionFromStatus(GrpcError error) {
  return FirebaseFirestoreError(
    error.message,
    FirestoreErrorCode.values[error.code],
  );
}

Comparator<T> comparator<T extends Comparable<T>>() {
  return (T a, T b) => a.compareTo(b);
}

/// Describes the type of an object, handling null objects gracefully.
String typeName(Object value) {
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
    if (e is FirebaseFirestoreError) {
      rethrow;
    } else {
      return Future<void>.error(
          FirebaseFirestoreError('$e', FirestoreErrorCode.unknown), s);
    }
  }
}

/// Converts varargs from an update call to a list of objects, ensuring that the arguments alternate
/// between String/FieldPath and Objects.
///
/// [fieldPathOffset] is the offset of the first field path in the original update API (used as the
/// index in error messages)
List<Object> collectUpdateArguments(
    int fieldPathOffset, List<Object> fieldsAndValues) {
  if (fieldsAndValues.length % 2 == 1) {
    throw ArgumentError(
        'Missing value in call to update().  There must be an even number of '
        'arguments that alternate between field names and values');
  }
  final List<Object> argumentList = fieldsAndValues.toList(growable: false);
  for (int i = 0; i < argumentList.length; i += 2) {
    final Object fieldPath = argumentList[i];
    if (fieldPath is! String && fieldPath is! FieldPath) {
      throw ArgumentError(
          'Excepted field name at argument position ${i + fieldPathOffset + 1} but '
          'got $fieldPath in call to update. The arguments to update should alternate between '
          'field names and values');
    }
  }

  return argumentList;
}
