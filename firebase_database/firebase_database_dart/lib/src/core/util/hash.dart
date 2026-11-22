/// SHA-1 and string-size helpers. JS: `core/util/util.ts` (`sha1`, `splitStringBySize`) and
/// `@firebase/util` `stringLength`; Android: `core/utilities/Utilities.java` (`sha1HexDigest`,
/// `stringHashV2Representation`).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The base64 of the SHA-1 digest of the UTF-8 bytes of [text], as node hashes use it.
String sha1Base64(String text) =>
    base64Encode(sha1.convert(utf8.encode(text)).bytes);

/// The number of UTF-8 bytes of [text].
///
/// Counts as `@firebase/util` `stringLength`: a lead surrogate counts 4 bytes with the unit after
/// it, a lone trail surrogate 3.
int utf8Length(String text) {
  final int length = text.length;
  int bytes = 0;
  for (int i = 0; i < length; i++) {
    final int c = text.codeUnitAt(i);
    if (c < 0x80) {
      bytes++;
    } else if (c < 0x800) {
      bytes += 2;
    } else if (c >= 0xd800 && c <= 0xdbff) {
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

/// Splits [text] into pieces of at most [segmentSize] UTF-16 code units.
List<String> splitStringBySize(String text, int segmentSize) {
  final int length = text.length;
  if (length <= segmentSize) {
    return <String>[text];
  }
  return <String>[
    for (int c = 0; c < length; c += segmentSize)
      text.substring(c, c + segmentSize > length ? length : c + segmentSize),
  ];
}

/// [text] in the V2 hash form of the compound hash: JSON-quoted with only `\` and `"` escaped.
String stringHashV2Representation(String text) {
  String escaped = text;
  if (escaped.contains(r'\')) {
    escaped = escaped.replaceAll(r'\', r'\\');
  }
  if (escaped.contains('"')) {
    escaped = escaped.replaceAll('"', r'\"');
  }
  return '"$escaped"';
}
