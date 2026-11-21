// Single-request uploads: putBytes and putString with each StringFormat.

import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';

import 'common.dart';

Future<void> main() async {
  final FirebaseStorage storage = emulatorStorage();
  final Reference folder = storage.ref(freshFolder('upload-bytes'));

  // Bytes, with the content type and a custom key.
  final FullMetadata bytes = await folder
      .child('hello.bin')
      .putBytes(
        Uint8List.fromList(utf8.encode('hello')),
        metadata: const SettableMetadata(
          contentType: 'application/octet-stream',
          customMetadata: <String, String>{'source': 'putBytes'},
        ),
      );
  print('${bytes.fullPath}: ${bytes.size} bytes, ${bytes.contentType}');

  // A string as it is: UTF-8.
  final FullMetadata raw = await folder
      .child('raw.txt')
      .putString(
        'Grüße',
        metadata: const SettableMetadata(contentType: 'text/plain'),
      );
  print('${raw.fullPath}: ${raw.size} bytes (UTF-8 of a 5 character string)');

  // Base64 and base64url are decoded before the upload.
  final FullMetadata base64 = await folder
      .child('base64.txt')
      .putString(
        base64Encode(utf8.encode('from base64')),
        format: StringFormat.base64,
        metadata: const SettableMetadata(contentType: 'text/plain'),
      );
  final FullMetadata base64Url = await folder
      .child('base64url.txt')
      .putString(
        base64UrlEncode(utf8.encode('from base64url')),
        format: StringFormat.base64Url,
        metadata: const SettableMetadata(contentType: 'text/plain'),
      );
  print('base64: ${base64.size} bytes, base64url: ${base64Url.size} bytes');

  // A data URL carries its own content type; it is used when the metadata
  // does not set one.
  final FullMetadata dataUrl = await folder
      .child('data_url.txt')
      .putString(
        'data:text/plain;base64,${base64Encode(utf8.encode('from a data URL'))}',
        format: StringFormat.dataUrl,
      );
  print('data URL: ${dataUrl.size} bytes, ${dataUrl.contentType}');

  print(utf8.decode(await folder.child('base64.txt').getBytes()));

  for (final Reference item in (await folder.listAll()).items) {
    await item.delete();
  }
  storage.close();
}
