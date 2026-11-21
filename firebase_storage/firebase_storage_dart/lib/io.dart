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
///
/// Future<void> fetchVideo(FirebaseStorage storage) async {
///   final DownloadTask task = storage.ref('videos/clip.mp4').startDownloadToFile(File('clip.mp4'));
///   task.progress.listen((DownloadProgress p) => print('${p.bytesTransferred}/${p.totalBytes}'));
///   await task.result;
/// }
/// ```
library;

import 'dart:io';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/src/io/download_task.dart';
import 'package:firebase_storage_dart/src/upload/upload_source.dart';

export 'package:firebase_storage_dart/src/io/download_task.dart'
    show DownloadProgress, DownloadState, DownloadTask;

/// Uploads from and downloads to files.
extension ReferenceIo on Reference {
  /// Uploads [file] with a resumable upload that streams it from disk, so the file is never held in memory.
  /// See [Reference.startUpload] for [metadata] and [existingSessionUri].
  ///
  /// Up to 256 KiB it is one multipart request. Above that it is one streamed request (or chunks of the
  /// `maxUploadChunkSize` of `FirebaseStorage`); after a failure or a pause the file is read again from the
  /// offset the server reports.
  ///
  /// The size of the file is read when the upload starts; a missing file throws a [FileSystemException] right
  /// away. The file must not change while it is uploaded: a file that gets shorter or longer fails the task
  /// with `invalid-argument`.
  UploadTask putFile(
    File file, {
    SettableMetadata? metadata,
    Uri? existingSessionUri,
  }) {
    return startUploadFrom(
      UploadSource.seekable(file.lengthSync(), file.openRead),
      operation: 'putFile',
      metadata: metadata,
      existingSessionUri: existingSessionUri,
    );
  }

  /// Starts a download of the object into [file] that can be paused, resumed and canceled, and resumes by
  /// itself after a network failure; see [DownloadTask].
  ///
  /// The bytes go to a new file next to [file] (`<file>.<random>.part`), which is renamed to [file] once the
  /// download is complete, replacing a file already there. When the download fails or is canceled, the
  /// partial file is deleted and [file] is left untouched. The directory of [file] must exist.
  ///
  /// Throws `invalid-root-operation` on the root of the bucket; other errors come through
  /// [DownloadTask.result].
  DownloadTask startDownloadToFile(File file) {
    throwIfRoot('startDownloadToFile');
    return DownloadTask.start(this, file);
  }

  /// Downloads the object into [file] and returns its size in bytes: [startDownloadToFile] without the
  /// controls, so it resumes after a network failure the same way.
  ///
  /// When the download fails, the partial file is deleted, [file] is left untouched and the error is thrown.
  Future<int> writeToFile(File file) async {
    final DownloadTask task = startDownloadToFile(file);
    await task.result;
    return task.bytesTransferred;
  }
}
