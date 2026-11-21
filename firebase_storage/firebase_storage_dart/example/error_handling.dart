// Errors: FirebaseStorageException with a code, the HTTP status and the body
// of the answer.

import 'package:firebase_storage_dart/firebase_storage_dart.dart';

import 'common.dart';

Future<void> main() async {
  final FirebaseStorage storage = emulatorStorage();

  // A missing object.
  try {
    await storage.ref(freshFolder('errors')).child('missing.txt').metadata();
  } on FirebaseStorageException catch (error) {
    print('missing: ${error.code}, HTTP ${error.httpStatus}');
  }

  // A rule that refuses the request: no user, no access.
  final FirebaseStorage guarded = emulatorStorage(bucket: authBucket);
  try {
    await guarded.ref('users/u1/secret.txt').putString('x');
  } on FirebaseStorageException catch (error) {
    print('guarded: ${error.code}, HTTP ${error.httpStatus}');
    print('server said: ${error.serverResponse}');
  }

  // Arguments are checked before anything is sent.
  try {
    await storage.ref('folder').list(maxResults: 0);
  } on FirebaseStorageException catch (error) {
    print('argument: ${error.code}');
  }
  try {
    await storage.ref().metadata();
  } on FirebaseStorageException catch (error) {
    print('root: ${error.code}');
  }

  // A canceled upload and a download over the size limit are errors too:
  // see resumable_upload.dart and streamed_download.dart.

  // After close() every call throws a StateError.
  storage.close();
  guarded.close();
  try {
    await storage.ref('folder/a.txt').metadata();
  } on StateError catch (error) {
    print('closed: ${error.message}');
  }
}
