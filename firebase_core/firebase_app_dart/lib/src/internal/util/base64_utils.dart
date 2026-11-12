// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'dart:convert';

/// Base64 helpers.
class Base64Utils {
  /// Encodes bytes as URL-safe base64 without `=` padding, or returns `null` for `null`.
  static String? encodeUrlSafeNoPadding(List<int>? url) {
    return url == null ? null : base64Url.encode(url).replaceAll('=', '');
  }
}
