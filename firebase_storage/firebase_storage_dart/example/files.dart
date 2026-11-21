// Files on disk with package:firebase_storage_dart/io.dart: putFile streams a
// file into a resumable upload, writeToFile streams an object into a file.

import 'dart:io';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/io.dart';

import 'common.dart';

Future<void> main() async {
  final FirebaseStorage storage = emulatorStorage();
  final Reference object = storage.ref(freshFolder('files')).child('notes.txt');
  final Directory temp = Directory.systemTemp.createTempSync('storage_files_');

  final File source = File('${temp.path}/source.txt')
    ..writeAsStringSync('line one\nline two\n');
  final UploadTask task = object.putFile(
    source,
    metadata: const SettableMetadata(contentType: 'text/plain'),
  );
  final FullMetadata uploaded = await task.result;
  print('uploaded ${uploaded.size} bytes from ${source.path}');

  // The bytes go to a temporary file next to the target; it is renamed when
  // the download is complete, so a failed download leaves no half file.
  final File target = File('${temp.path}/copy.txt');
  final int written = await object.writeToFile(target);
  print('wrote $written bytes: ${target.readAsStringSync().trim()}');

  await object.delete();
  temp.deleteSync(recursive: true);
  storage.close();
}
