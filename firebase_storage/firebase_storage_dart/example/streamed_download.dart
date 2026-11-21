// Downloads: a stream, a byte range, and all bytes with a size limit.

import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';

import 'common.dart';

Future<void> main() async {
  final FirebaseStorage storage = emulatorStorage();
  final Reference file = storage
      .ref(freshFolder('download'))
      .child('digits.txt');
  await file.putString(
    '0123456789',
    metadata: const SettableMetadata(contentType: 'text/plain'),
  );

  // The whole object as a stream: the body is not held in memory.
  final StringBuffer all = StringBuffer();
  await for (final String piece in file.openRead().transform(utf8.decoder)) {
    all.write(piece);
  }
  print('openRead(): $all');

  // Like File.openRead: start is inclusive, end is exclusive.
  print('openRead(2, 5): ${await _text(file.openRead(2, 5))}');
  print('openRead(7): ${await _text(file.openRead(7))}');

  // All bytes at once. maxSize makes a larger object fail instead of filling
  // memory.
  final Uint8List bytes = await file.getBytes();
  print('getBytes(): ${bytes.length} bytes');
  try {
    await file.getBytes(maxSize: 4);
  } on FirebaseStorageException catch (error) {
    print('getBytes(maxSize: 4): ${error.code}');
  }

  await file.delete();
  storage.close();
}

Future<String> _text(Stream<List<int>> stream) => utf8.decodeStream(stream);
