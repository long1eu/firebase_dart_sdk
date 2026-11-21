/// The body of a multipart upload, as `multipartUpload` of the JS SDK (`implementation/requests.ts`) builds it.
@internal
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A multipart boundary of 32 decimal digits, like the JS SDK's two `Math.random()` strings, from a secure
/// random generator so that the content cannot guess it and forge the metadata part.
@internal
String multipartBoundary() {
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < 32; i++) {
    buffer.write(_secureRandom.nextInt(10));
  }
  return buffer.toString();
}

final math.Random _secureRandom = math.Random.secure();

/// The `multipart/related` body: the JSON [metadata] (which holds the `contentType` of the second part), then
/// [data], separated by [boundary].
@internal
Uint8List multipartBody({
  required String boundary,
  required Map<String, Object?> metadata,
  required Uint8List data,
}) {
  final String head =
      '--$boundary\r\n'
      'Content-Type: application/json; charset=utf-8\r\n'
      '\r\n'
      '${jsonEncode(metadata)}\r\n'
      '--$boundary\r\n'
      'Content-Type: ${metadata['contentType']}\r\n'
      '\r\n';
  final String tail = '\r\n--$boundary--';
  return (BytesBuilder(copy: false)
        ..add(utf8.encode(head))
        ..add(data)
        ..add(utf8.encode(tail)))
      .takeBytes();
}
