// File created by
// Lung Razvan <long1eu>
// on 20/10/2018

import 'package:firebase_core/firebase_core.dart';

/// URL encodes a string, but leaves slashes unmolested. This is used for
/// encoding gs uri paths to objects -- where the individual path segments need
/// to be escaped, but the slashes do not.
///
/// Returns a partially URL encoded string where slashes are preserved.
String preserveSlashEncode(String s) {
  if (s == null || s.isEmpty) {
    return '';
  }
  return slashize(Uri.encodeComponent(s));
}

/// Restores slashes within an encoded string.
///
/// Returns a modified string that replaces escaped slashes with unescaped
/// slashes.
String slashize(String s) {
  Preconditions.checkNotNull(s);
  return s.replaceAll('%2F', '/');
}

/// URL Encodes slashes (only) within a string.
///
/// Returns a modified string that replaces slashes with their escape codes.
String unSlashize(String s) {
  Preconditions.checkNotNull(s);
  return s.replaceAll('/', '%2F');
}

String normalizeSlashes(String uriSegment) {
  if (uriSegment == null || uriSegment.isEmpty) {
    return '';
  }

  if (uriSegment.startsWith('/') ||
      uriSegment.endsWith('/') ||
      uriSegment.contains('//')) {
    final StringBuffer result = StringBuffer();
    for (String stringSegment in uriSegment.split('/')) {
      if (stringSegment != null && stringSegment.isNotEmpty) {
        if (result.length > 0) {
          result..write('/')..write(stringSegment);
        } else {
          result.write(stringSegment);
        }
      }
    }
    return result.toString();
  }
  return uriSegment;
}
