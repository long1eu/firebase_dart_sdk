// Resuming an upload after a restart: keep UploadTask.sessionUri, and pass it
// as existingSessionUri with the same data.
//
// A program that was stopped in the middle of an upload would have saved the
// URI to disk. Here the first task is paused, which stands for the process
// ending: the session stays open on the server, and a second task asks it how
// much it has and sends only the rest.

import 'dart:typed_data';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';

import 'common.dart';

Future<void> main() async {
  final FirebaseStorage storage = emulatorStorage();
  final Reference target = storage
      .ref(freshFolder('resume-session'))
      .child('big.bin');
  final Uint8List data = Uint8List(4 * 1024 * 1024);

  final UploadTask first = target.startUpload(data);
  // The session exists once the first request has been answered; the first
  // progress event after that carries the bytes the server has.
  await first.progress.firstWhere(
    (UploadProgress event) => event.bytesTransferred > 0,
  );
  first.pause();
  final Uri? session = first.sessionUri;
  print('paused after ${first.bytesTransferred} of ${first.totalBytes} bytes');
  print('session saved: ${session != null}');
  if (session == null) {
    // A small upload is a single request and has no session to resume.
    print('finished before it could be interrupted');
    await first.result;
    await target.delete();
    storage.close();
    return;
  }

  // The same reference, the same data, and the saved URI. Treat the URI as a
  // credential: whoever has it can write to the session.
  final UploadTask second = target.startUpload(
    data,
    existingSessionUri: session,
  );
  final FullMetadata done = await second.result;
  print('resumed: ${done.size} bytes in ${done.fullPath}');

  // The data to resume must be the data of the first attempt: a stream
  // upload, or putFile of io.dart, takes existingSessionUri the same way.
  await target.delete();
  storage.close();
}
