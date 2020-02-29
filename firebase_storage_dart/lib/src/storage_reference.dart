// File created by
// Lung Razvan <long1eu>
// on 22/10/2018

import 'dart:async';
import 'dart:io';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/delete_storage_task.dart';
import 'package:firebase_storage/src/file_download_task.dart';
import 'package:firebase_storage/src/firebase_storage.dart';
import 'package:firebase_storage/src/get_download_url_task.dart';
import 'package:firebase_storage/src/get_metadata_task.dart';
import 'package:firebase_storage/src/internal/slash_util.dart';
import 'package:firebase_storage/src/internal/task_events.dart';
import 'package:firebase_storage/src/storage_metadata.dart';
import 'package:firebase_storage/src/storage_task_manager.dart';
import 'package:firebase_storage/src/stream_download_task.dart';
import 'package:firebase_storage/src/streamed_task.dart';
import 'package:firebase_storage/src/task.dart';
import 'package:firebase_storage/src/update_metadata_task.dart';

/// Represents a reference to a Google Cloud Storage object. Developers can
/// upload and download objects, get/set object metadata, and delete an object
/// at a specified path. (see <a href='https://cloud.google.com/storage/'>Google Cloud Storage</a>)
class StorageReference {
  // region Constructors
  StorageReference(this.storageUri, this.storage)
      : assert(storageUri != null, 'storageUri cannot be null'),
        assert(storage != null, 'FirebaseApp cannot be null');

  static const String _tag = 'StorageReference';
  final Uri storageUri;

  /// The [FirebaseStorage] service which created this reference.
  final FirebaseStorage storage;

  /// Returns a new instance of [StorageReference] pointing to a child location
  /// of the current reference. All leading and trailing slashes will be
  /// removed, and consecutive slashes will be compressed to single slashes.
  ///
  /// For example:
  ///
  /// child = /foo/bar     path = foo/bar
  /// child = foo/bar/     path = foo/bar
  /// child = foo///bar    path = foo/bar
  ///
  /// [pathString] is the relative path from this reference.
  StorageReference child(String pathString) {
    Preconditions.checkArgument(pathString != null && pathString.isNotEmpty,
        'childName cannot be null or empty');

    final String normalizedPath = normalizeSlashes(pathString);
    Uri child;
    try {
      child = storageUri.replace(
          pathSegments: storageUri.pathSegments
            ..add(preserveSlashEncode(normalizedPath)));
    } on FormatException catch (_) {
      Log.e(_tag, 'Unable to create a valid default Uri. $normalizedPath');

      throw ArgumentError('childName');
    }
    return StorageReference(child, storage);
  }

  /// Returns a new instance of [StorageReference] pointing to the parent
  /// location or null if this instance references the root location.
  ///
  /// For example:
  ///
  /// path = foo/bar/baz   parent = foo/bar
  /// path = foo           parent = (root)
  /// path = (root)        parent = (null)
  ///
  /// @return the parent {@link StorageReference}.
  StorageReference get parent {
    String path = storageUri.path;

    if ((path == null && path.isEmpty) || path == '/') {
      return null;
    }

    final int childIndex = path.lastIndexOf('/');
    if (childIndex == -1) {
      path = '/';
    } else {
      path = path.substring(0, childIndex);
    }

    final Uri child = storageUri.replace(path: path);
    return StorageReference(child, storage);
  }

  /// Returns a new instance of [StorageReference] pointing to the root
  /// location.
  StorageReference get root {
    final Uri child = storageUri.replace(path: '');
    return StorageReference(child, storage);
  }

  /// Returns the short name of this object.
  String get name {
    final String path = storageUri.path;
    assert(path != null);
    final int lastIndex = path.lastIndexOf('/');
    if (lastIndex != -1) {
      return path.substring(lastIndex + 1);
    }
    return path;
  }

  /// Returns the full path to this object, not including the Google Cloud
  /// Storage bucket.
  String get path {
    final String path = storageUri.path;
    assert(path != null);
    return path;
  }

  /// Return the Google Cloud Storage bucket that holds this object.
  String get bucket => storageUri.authority;

  FirebaseApp get app => storage.app;

  /*
  /**
   * Asynchronously uploads byte data to this {@link StorageReference}. This is not recommended for
   * large files. Instead upload a file via {@link #putFile(Uri)} or an {@link InputStream} via
   * {@link #putStream(InputStream)}.
   *
   * @param bytes The byte array to upload.
   * @return An instance of {@link UploadTask} which can be used to monitor and manage the upload.
   */
  @SuppressWarnings('ConstantConditions')
  UploadTask putBytes(List<int> bytes) {
    Preconditions.checkArgument(bytes != null, 'bytes cannot be null');

    UploadTask task = new UploadTask(this, null, bytes);
    task.queue();
    return task;
  }

  /**
   * Asynchronously uploads byte data to this {@link StorageReference}. This is not recommended for
   * large files. Instead upload a file via {@link #putFile(Uri)} or a Stream via {@link
   * #putStream(InputStream)}.
   *
   * @param bytes The List<int> to upload.
   * @param metadata {@link StorageMetadata} containing additional information (MIME type, etc.)
   *     about the object being uploaded.
   * @return An instance of {@link UploadTask} which can be used to monitor and manage the upload.
   */

  UploadTask putBytes(List<int> bytes, StorageMetadata metadata) {
    Preconditions.checkArgument(bytes != null, 'bytes cannot be null');
    Preconditions.checkArgument(metadata != null, 'metadata cannot be null');

    UploadTask task = new UploadTask(this, metadata, bytes);
    task.queue();
    return task;
  }

  /**
   * Asynchronously uploads from a content URI to this {@link StorageReference}.
   *
   * @param uri The source of the upload. This can be a file:// scheme or any content URI. A content
   *     resolver will be used to load the data.
   * @return An instance of {@link UploadTask} which can be used to monitor or manage the upload.
   */
  @SuppressWarnings('ConstantConditions')
  UploadTask putFile(Uri uri) {
    Preconditions.checkArgument(uri != null, 'uri cannot be null');

    UploadTask task = new UploadTask(this, null, uri, null);
    task.queue();
    return task;
  }

  /**
   * Asynchronously uploads from a content URI to this {@link StorageReference}.
   *
   * @param uri The source of the upload. This can be a file:// scheme or any content URI. A content
   *     resolver will be used to load the data.
   * @param metadata {@link StorageMetadata} containing additional information (MIME type, etc.)
   *     about the object being uploaded.
   * @return An instance of {@link UploadTask} which can be used to monitor or manage the upload.
   */
  @SuppressWarnings('ConstantConditions')
  UploadTask putFile(Uri uri, StorageMetadata metadata) {
    Preconditions.checkArgument(uri != null, 'uri cannot be null');
    Preconditions.checkArgument(metadata != null, 'metadata cannot be null');

    UploadTask task = new UploadTask(this, metadata, uri, null);
    task.queue();
    return task;
  }

  /**
   * Asynchronously uploads from a content URI to this {@link StorageReference}.
   *
   * @param uri The source of the upload. This can be a file:// scheme or any content URI. A content
   *     resolver will be used to load the data.
   * @param metadata {@link StorageMetadata} containing additional information (MIME type, etc.)
   *     about the object being uploaded.
   * @param existingUploadUri If set, an attempt is made to resume an existing upload session as
   *     defined by {@link UploadTask.TaskSnapshot#getUploadSessionUri()}.
   * @return An instance of {@link UploadTask} which can be used to monitor or manage the upload.
   */
  @SuppressWarnings('ConstantConditions')
  UploadTask putFile(Uri uri, StorageMetadata metadata, Uri existingUploadUri) {
    Preconditions.checkArgument(uri != null, 'uri cannot be null');
    Preconditions.checkArgument(metadata != null, 'metadata cannot be null');

    UploadTask task = new UploadTask(this, metadata, uri, existingUploadUri);
    task.queue();
    return task;
  }

  /**
   * Asynchronously uploads a stream of data to this {@link StorageReference}. The stream will
   * remain open at the end of the upload.
   *
   * @param stream The {@link InputStream} to upload.
   * @return An instance of {@link UploadTask} which can be used to monitor and manage the upload.
   */
  @SuppressWarnings('ConstantConditions')
  UploadTask putStream(InputStream stream) {
    Preconditions.checkArgument(stream != null, 'stream cannot be null');

    UploadTask task = UploadTask(this, null, stream);
    task.queue();
    return task;
  }

  /**
   * Asynchronously uploads a stream of data to this {@link StorageReference}. The stream will
   * remain open at the end of the upload.
   *
   * @param stream The {@link InputStream} to upload.
   * @param metadata {@link StorageMetadata} containing additional information (MIME type, etc.)
   *     about the object being uploaded.
   * @return An instance of {@link UploadTask} which can be used to monitor and manage the upload.
   */
  @SuppressWarnings('ConstantConditions')
  UploadTask putStream(InputStream stream, StorageMetadata metadata) {
    Preconditions.checkArgument(stream != null, 'stream cannot be null');
    Preconditions.checkArgument(metadata != null, 'metadata cannot be null');

    UploadTask task = UploadTask(this, metadata, stream);
    task.queue();
    return task;
  }


  /// Returns the set of active upload tasks currently in progress or recently
  /// completed.
  List<UploadTask> get activeUploadTasks {
    return StorageTaskManager.instance.getUploadTasksUnder(this);
  }
  */

  /// Returns the set of active download tasks currently in progress or recently
  /// completed.
  List<FileDownloadTask> get activeDownloadTasks {
    return StorageTaskManager.instance.getDownloadTasksUnder(this);
  }

  /// Retrieves metadata associated with an object at this [StorageReference].
  Future<StorageMetadata> get metadata => GetMetadataTask.execute(this);

  /// Retrieves a long lived download URL with a revokable token. This can be
  /// used to share the file with others, but can be revoked by a developer in
  /// the Firebase Console if desired.
  ///
  /// Returns the [Uri] representing the download URL.
  Future<Uri> get downloadUrl => GetDownloadUrlTask.execute(this);

  /// Updates the metadata associated with this [StorageReference].
  ///
  /// Returns a [Future] that will return the final [StorageMetadata] once the
  /// operation is complete.
  Future<StorageMetadata> updateMetadata(StorageMetadata metadata) {
    Preconditions.checkNotNull(metadata);
    return UpdateMetadataTask.execute(this, metadata);
  }

  /// Downloads the object from this [StorageReference]. A [List<int>] will be
  /// allocated large enough to hold the entire file in memory. Therefore, using
  /// this method will impact memory usage of your process. If you are
  /// downloading many large files, [stream] may be a better option.
  ///
  /// [maxDownloadSizeBytes] The maximum allowed size in bytes that will be
  /// allocated. Set this parameter to prevent out of memory conditions from
  /// occurring. If the download exceeds this limit, the task will fail and an
  /// [RangeError] will be returned.
  ///
  /// Returns the bytes downloaded.
  Future<List<int>> getBytes(final int maxDownloadSizeBytes) {
    final Completer<List<int>> pendingResult = Completer<List<int>>();
    final StreamedTask<DownloadStreamTaskSnapshot> task =
        StreamDownloadTask.schedule(this);

    task.data
        .reduce((List<int> p, List<int> e) {
          if (e.length > maxDownloadSizeBytes) {
            Log.e(_tag, 'the maximum allowed buffer size was exceeded.');
            throw RangeError('the maximum allowed buffer size was exceeded.');
          }
          p.addAll(e);
          return p;
        })
        .then(pendingResult.complete)
        .catchError(pendingResult.completeError);

    return pendingResult.future;
  }

  /// Downloads the object at this [StorageReference] to a specified system
  /// filepath.
  ///
  /// Returns a [Task] that can be used to monitor or manage the
  /// download.
  Task<DownloadTaskSnapshot> getFile(File destinationFile) {
    return FileDownloadTask.schedule(this, destinationFile);
  }

  /// Asynchronously downloads the object at this [StorageReference] via a
  /// [Stream<List<int>>].
  ///
  /// Returns a [StreamedTask] that can be used to monitor or manage the
  /// download.
  StreamedTask<DownloadStreamTaskSnapshot> get stream {
    return StreamDownloadTask.schedule(this);
  }

  /// Deletes the object at this [StorageReference].
  ///
  /// Return a Future that indicates whether the operation succeeded or failed.
  Future<void> delete() => DeleteStorageTask.execute(this);

  /// Returns this object in URI form, which can then be shared and passed into
  /// [FirebaseStorage.getReferenceFromUrl].
  @override
  String toString() => 'gs://${storageUri.authority}${storageUri.path}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorageReference &&
          runtimeType == other.runtimeType &&
          toString() == other.toString();

  @override
  int get hashCode => toString().hashCode;
}
