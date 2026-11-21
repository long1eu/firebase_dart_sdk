/// The body of a multipart upload, as `multipartUpload` of the JS SDK (`implementation/requests.ts`) builds it.
@internal
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A multipart boundary of decimal digits, like the JS SDK's two `Math.random()` strings, from [random] (a
/// number in `[0, 1)`).
@internal
String multipartBoundary(double Function() random) {
  String digits() => (random() * 1e16).floor().toString().padLeft(16, '0');
  return '${digits()}${digits()}';
}

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
