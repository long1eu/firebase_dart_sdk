import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'errors.dart';

/// How `Reference.putString` reads its string.
enum StringFormat {
  /// The string is the content, uploaded as UTF-8 (an unpaired surrogate becomes U+FFFD).
  raw('raw'),

  /// The content in standard base64 (`+` and `/`), with or without padding.
  base64('base64'),

  /// The content in URL-safe base64 (`-` and `_`), with or without padding.
  base64Url('base64url'),

  /// A data URL (`data:[<mediatype>][;base64],<data>`). Its media type becomes the content type of the object
  /// unless the metadata of the upload has one.
  dataUrl('data_url');

  const StringFormat(this._jsName);

  /// The name of the format in the messages of the JS SDK.
  final String _jsName;
}

/// The bytes of a string of `putString`, and the content type of a data URL.
@internal
final class StringData {
  /// Creates the data.
  const StringData(this.bytes, [this.contentType]);

  /// The content.
  final Uint8List bytes;

  /// The media type of a data URL, if it has one.
  final String? contentType;
}

/// Decodes [value] in [format], like `dataFromString` of the JS SDK (`implementation/string.ts`).
///
/// Throws a `FirebaseStorageException` (`invalid-format`) when [value] does not match [format].
@internal
StringData dataFromString(StringFormat format, String value) {
  return switch (format) {
    StringFormat.raw => StringData(utf8.encode(value)),
    StringFormat.base64 ||
    StringFormat.base64Url => StringData(_base64Bytes(format, value)),
    StringFormat.dataUrl => _dataUrl(value),
  };
}

Uint8List _base64Bytes(StringFormat format, String value) {
  String standard = value;
  if (format == StringFormat.base64) {
    for (final String invalid in <String>['-', '_']) {
      if (value.contains(invalid)) {
        throw invalidFormat(
          format._jsName,
          "Invalid character '$invalid' found: is it base64url encoded?",
        );
      }
    }
  } else {
    for (final String invalid in <String>['+', '/']) {
      if (value.contains(invalid)) {
        throw invalidFormat(
          format._jsName,
          "Invalid character '$invalid' found: is it base64 encoded?",
        );
      }
    }
    standard = value.replaceAll('-', '+').replaceAll('_', '/');
  }
  // Padding is optional, like the Buffer decoding of the JS SDK on Node.
  final String unpadded = standard.replaceFirst(RegExp(r'=+$'), '');
  if (!RegExp(r'^[A-Za-z0-9+/]*$').hasMatch(unpadded) ||
      unpadded.length % 4 == 1) {
    throw invalidFormat(format._jsName, 'Invalid character found');
  }
  final int padding = (4 - unpadded.length % 4) % 4;
  return base64.decode(unpadded + '=' * padding);
}

StringData _dataUrl(String value) {
  final RegExpMatch? match = RegExp('^data:([^,]+)?,').firstMatch(value);
  if (match == null) {
    throw invalidFormat(
      StringFormat.dataUrl._jsName,
      "Must be formatted 'data:[<mediatype>][;base64],<data>",
    );
  }
  final String? middle = match.group(1);
  final bool isBase64 = middle != null && middle.endsWith(';base64');
  final String? mediaType = isBase64
      ? middle.substring(0, middle.length - ';base64'.length)
      : middle;
  final String rest = value.substring(value.indexOf(',') + 1);
  final Uint8List bytes = isBase64
      ? _base64Bytes(StringFormat.base64, rest)
      : _percentDecodedBytes(rest);
  return StringData(
    bytes,
    mediaType == null || mediaType.isEmpty ? null : mediaType,
  );
}

Uint8List _percentDecodedBytes(String value) {
  try {
    return utf8.encode(Uri.decodeComponent(value));
  } on ArgumentError {
    throw invalidFormat(StringFormat.dataUrl._jsName, 'Malformed data URL.');
  } on FormatException {
    throw invalidFormat(StringFormat.dataUrl._jsName, 'Malformed data URL.');
  }
}
