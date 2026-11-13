// Helpers for the fuzz tests of untrusted input (test/unit/fuzz): byte level
// mutations of valid input, and what counts as a clean rejection of hostile
// input.
//
// The cases come from the seeded generator of property.dart: a failure prints
// the PROPERTY_SEED that reproduces it. The default run takes a few seconds
// per file; PROPERTY_SCALE multiplies the number of cases for long runs, and a
// different PROPERTY_SEED explores other cases:
//
//   PROPERTY_SCALE=200 PROPERTY_SEED=7 dart test test/unit/fuzz

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:protobuf/protobuf.dart';

import 'property.dart';

/// Whether [error] is a deliberate rejection of malformed input, as opposed to
/// a crash: a [FirestoreError], an [ArgumentError] (but not a [RangeError],
/// which is an index out of bounds), a [FormatException], an
/// [InvalidProtocolBufferException], or an internal assertion of the SDK
/// (`hardAssert` or `fail` of util/assert.dart, the upstream
/// `Assert.hardAssert`).
///
/// A plain `assert` of a constructor does not count: it is not checked in
/// production code, so the malformed value would be accepted there.
bool isCleanRejection(Object error, StackTrace stackTrace) {
  if (error is RangeError) {
    return false;
  }
  if (error is FirestoreError ||
      error is ArgumentError ||
      error is FormatException ||
      error is InvalidProtocolBufferException) {
    return true;
  }
  if (error is AssertionError || error is StateError) {
    return _thrownBySdkAssert(stackTrace);
  }
  return false;
}

bool _thrownBySdkAssert(StackTrace stackTrace) {
  final String top = stackTrace
      .toString()
      .split('\n')
      .firstWhere((String line) => line.trim().isNotEmpty, orElse: () => '');
  return top.contains('firestore/util/assert.dart');
}

/// Runs [body] and returns its result, or null if it rejected the input
/// cleanly (see [isCleanRejection]). Any other error fails the test with
/// [describe] of the input.
T? acceptOrReject<T>(T Function() body, String Function() input) {
  try {
    return body();
  } catch (error, stackTrace) {
    if (isCleanRejection(error, stackTrace)) {
      return null;
    }
    throw StateError(
      'Malformed input was not rejected cleanly: '
      '${error.runtimeType}: $error\n'
      '  input: ${_clip(input())}\n'
      '  at: ${stackTrace.toString().split('\n').take(8).join('\n      ')}',
    );
  }
}

/// [acceptOrReject] for asynchronous [body].
Future<T?> acceptOrRejectAsync<T>(
  Future<T> Function() body,
  String Function() input,
) async {
  try {
    return await body();
  } catch (error, stackTrace) {
    if (isCleanRejection(error, stackTrace)) {
      return null;
    }
    throw StateError(
      'Malformed input was not rejected cleanly: '
      '${error.runtimeType}: $error\n'
      '  input: ${_clip(input())}\n'
      '  at: ${stackTrace.toString().split('\n').take(8).join('\n      ')}',
    );
  }
}

String _clip(String text) => text.length <= 2000
    ? text
    : '${text.substring(0, 2000)}... (${text.length} characters)';

extension FuzzGen on Gen {
  /// [bytes] with a few random byte-level mutations: flipped bits, replaced,
  /// inserted, deleted and duplicated ranges, truncation.
  Uint8List mutateBytes(
    List<int> bytes, {
    List<int> dictionary = const <int>[],
  }) {
    final List<int> result = List<int>.of(bytes);
    for (int edits = between(1, 4); edits > 0; edits--) {
      final int at = below(result.length + 1);
      switch (below(8)) {
        case 0:
          if (at < result.length) {
            result[at] ^= 1 << below(8);
          }
          break;
        case 1:
          if (at < result.length) {
            result[at] = chance(50) && dictionary.isNotEmpty
                ? pick(dictionary)
                : below(256);
          }
          break;
        case 2:
          result.insert(
            at,
            chance(50) && dictionary.isNotEmpty ? pick(dictionary) : below(256),
          );
          break;
        case 3:
          result.removeRange(at, (at + between(1, 16)).clamp(0, result.length));
          break;
        case 4:
          final int end = (at + between(1, 32)).clamp(0, result.length);
          result.insertAll(below(result.length + 1), result.sublist(at, end));
          break;
        case 5:
          result.length = at;
          break;
        case 6:
          if (at < result.length) {
            result[at] = pick(const <int>[0x00, 0x7f, 0x80, 0xff, 0x01, 0xfe]);
          }
          break;
        default:
          // Swap two ranges.
          final int other = below(result.length + 1);
          final int length = between(1, 8);
          if (at + length <= result.length && other + length <= result.length) {
            final List<int> a = result.sublist(at, at + length);
            result
              ..setRange(at, at + length, result.sublist(other, other + length))
              ..setRange(other, other + length, a);
          }
      }
    }
    return Uint8List.fromList(result);
  }
}
