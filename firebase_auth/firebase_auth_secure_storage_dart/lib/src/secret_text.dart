import 'dart:convert';

import 'package:firebase_auth_secure_storage_dart/src/secret_store.dart';

/// [bytes] read from a secret store as UTF-8 text.
///
/// Bytes that are not UTF-8 fail with a [SecretStoreError] that names
/// [function] but, unlike the [FormatException] of `utf8.decode`, does not
/// carry the bytes.
String decodeSecret(List<int> bytes, String function) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw SecretStoreError(
      function: function,
      message: 'the stored secret is not UTF-8 text',
    );
  }
}
