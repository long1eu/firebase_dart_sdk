import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:protobuf/protobuf.dart';

/// Parses a proto stored in the SQLite cache with [parse], failing an internal assertion ('[what] failed to parse')
/// if the bytes are malformed, as upstream does (Android `throw fail("... failed to parse: %s", e)` on an
/// `InvalidProtocolBufferException`).
///
/// The Java parser reports all malformed bytes with an `InvalidProtocolBufferException`. The Dart protobuf package
/// (6.1.0) throws one for most of them, but a `RangeError` or an `ArgumentError` for some malformed lengths: they are
/// the same failure.
///
/// Only the parsing is guarded: errors of decoding the parsed message into the model are not parse errors.
T parseStoredProto<T extends GeneratedMessage>(
  String what,
  T Function() parse,
) {
  try {
    return parse();
  } on InvalidProtocolBufferException catch (e) {
    throw fail('$what failed to parse: $e');
  } on ArgumentError catch (e) {
    // RangeError and IndexError are ArgumentErrors.
    throw fail('$what failed to parse: $e');
  }
}
