/// File helpers of `firebase_storage_dart` for platforms with `dart:io` (not the web).
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:firebase_storage_dart/firebase_storage_dart.dart';
/// import 'package:firebase_storage_dart/io.dart';
///
/// Future<void> backup(FirebaseStorage storage) async {
///   final Reference ref = storage.ref('backups/db.sqlite');
///   await ref.putFile(File('db.sqlite')).result;
///   final int bytes = await ref.writeToFile(File('restored.sqlite'));
///   print('restored $bytes bytes');
/// }
/// ```
library;

import 'dart:io';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/src/io/write_file.dart';

/// Uploads from and downloads to files.
extension ReferenceIo on Reference {
  /// Uploads [file] with a resumable upload that reads it from disk chunk by chunk, so the file is never held
  /// in memory. See [Reference.startStreamUpload] for [metadata] and [existingSessionUri].
  ///
  /// The size of the file is read when the upload starts; a missing file throws a [FileSystemException] right
  /// away. The file must not change while it is uploaded.
  UploadTask putFile(
    File file, {
    SettableMetadata? metadata,
    Uri? existingSessionUri,
  }) {
    return startStreamUpload(
      file.openRead(),
      length: file.lengthSync(),
      metadata: metadata,
      existingSessionUri: existingSessionUri,
    );
  }

  /// Downloads the object into [file] and returns its size in bytes.
  ///
  /// The bytes go to a new file next to [file] (`<file>.<random>.part`), which is renamed to [file] once the
  /// download is complete, replacing a file already there. When the download fails, the partial file is
  /// deleted, [file] is left untouched and the error is rethrown. The directory of [file] must exist.
  Future<int> writeToFile(File file) => writeStreamToFile(openRead(), file);
}
