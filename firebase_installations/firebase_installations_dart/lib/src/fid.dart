import 'dart:convert';
import 'dart:typed_data';

final RegExp _fidPattern = RegExp(r'^[cdef][A-Za-z0-9_-]{21}$');

/// A new Firebase installation id from 17 bytes of [randomBytes].
///
/// The first byte becomes `0x70 | (byte0 & 0x0F)` (the FID header `0111`), the bytes are base64url
/// encoded and cut to 22 characters (`JS-FIS/helpers/generate-fid.ts:20-46`).
String generateFid(Uint8List Function(int length) randomBytes) {
  final Uint8List bytes = Uint8List.fromList(randomBytes(17));
  if (bytes.length != 17) {
    throw StateError('randomBytes(17) returned ${bytes.length} bytes');
  }
  bytes[0] = 0x70 | (bytes[0] & 0x0F);
  return base64Url.encode(bytes).substring(0, 22);
}

/// Whether [fid] has the shape of a FID: 22 base64url characters, the first one of `c`, `d`, `e`, `f`.
bool isValidFid(String fid) => _fidPattern.hasMatch(fid);
