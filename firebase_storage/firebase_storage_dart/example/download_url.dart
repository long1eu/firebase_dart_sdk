// The download URL: a link that carries a download token and works without a
// signed-in user, whatever the security rules say.

import 'dart:convert';
import 'dart:io';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';

import 'common.dart';

Future<void> main() async {
  final FirebaseStorage storage = emulatorStorage();
  final Reference file = storage.ref(freshFolder('url')).child('hello.txt');
  await file.putString('shared by link');

  final String url = await file.downloadUrl();
  print(url.replaceAll(RegExp(r'token=[^&]+'), 'token=<token>'));

  // Any HTTP client can read it.
  final HttpClient client = HttpClient();
  final HttpClientRequest request = await client.getUrl(Uri.parse(url));
  final HttpClientResponse response = await request.close();
  print('GET: ${response.statusCode} ${await utf8.decodeStream(response)}');
  client.close();

  // The token is part of the metadata. The emulator creates one when the
  // object has none.
  print('tokens: ${(await file.metadata()).downloadTokens.length}');

  await file.delete();
  storage.close();
}
