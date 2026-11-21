// A resumable upload: progress events, pause, resume and cancel.
//
// startUpload sends the data in chunks of at least 256 KiB, so the object is
// larger than one chunk to make the progress visible.

import 'dart:typed_data';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';

import 'common.dart';

Future<void> main() async {
  final FirebaseStorage storage = emulatorStorage();
  final Reference folder = storage.ref(freshFolder('resumable'));
  final Uint8List data = Uint8List(2 * 1024 * 1024);

  // Progress and the result.
  final UploadTask task = folder
      .child('two_megabytes.bin')
      .startUpload(
        data,
        metadata: const SettableMetadata(contentType: 'application/x-example'),
      );
  final progress = task.progress.listen((UploadProgress event) {
    final int percent = 100 * event.bytesTransferred ~/ event.totalBytes;
    print('${event.state.name}: $percent% (${event.bytesTransferred} bytes)');
  });
  final FullMetadata done = await task.result;
  await progress.asFuture<void>();
  print('uploaded ${done.size} bytes, state ${task.state.name}');

  // Pause and resume. pause() and resume() return false when the task is not
  // in a state where they apply, for example after it finished.
  final UploadTask pausing = folder.child('paused.bin').startUpload(data);
  print('pause accepted: ${pausing.pause()}');
  await Future<void>.delayed(const Duration(milliseconds: 200));
  print('state ${pausing.state.name}, ${pausing.bytesTransferred} bytes sent');
  print('resume accepted: ${pausing.resume()}');
  await pausing.result;
  print('resumed and finished: ${pausing.state.name}');
  print('pause after the end: ${pausing.pause()}');

  // Cancel. The result then fails with the code 'canceled'.
  final UploadTask canceled = folder.child('canceled.bin').startUpload(data);
  canceled.cancel();
  try {
    await canceled.result;
  } on FirebaseStorageException catch (error) {
    print('cancel: ${error.code}, state ${canceled.state.name}');
  }

  for (final Reference item in (await folder.listAll()).items) {
    await item.delete();
  }
  storage.close();
}
