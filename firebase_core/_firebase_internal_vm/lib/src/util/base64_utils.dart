// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'dart:convert';

class Base64Utils {
  static String encodeUrlSafeNoPadding(List<int> url) {
    return url == null ? null : base64Encode(url);
  }
}
