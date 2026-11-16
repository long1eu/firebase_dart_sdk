import 'dart:convert';
import 'dart:typed_data';

/// Encodes [bytes] in base64url without padding, as JWT requires (RFC 7515, section 2).
String base64UrlNoPadding(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Encodes [json] as a JWT segment: UTF-8 JSON in base64url without padding.
String encodeJsonSegment(Map<String, Object?> json) =>
    base64UrlNoPadding(utf8.encode(jsonEncode(json)));

final RegExp _base64UrlAlphabet = RegExp(r'^[A-Za-z0-9_-]*$');

/// Decodes a JWT segment: base64url without padding. Anything else (the standard alphabet, padding, white
/// space) throws a [FormatException].
Uint8List decodeSegment(String segment) {
  if (!_base64UrlAlphabet.hasMatch(segment) || segment.length % 4 == 1) {
    throw const FormatException('Not base64url without padding');
  }
  return base64Url.decode(base64Url.normalize(segment));
}

/// Decodes a JWT segment that holds a JSON object. Throws a [FormatException] otherwise.
Map<String, Object?> decodeJsonSegment(String segment) {
  final Object? json = jsonDecode(utf8.decode(decodeSegment(segment)));
  if (json is! Map<String, Object?>) {
    throw const FormatException('Not a JSON object');
  }
  return json;
}
