import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage_dart/firebase_storage_dart.dart' as fs;
import 'package:firebase_storage_dart/io.dart' as fs_io;
import 'package:firebase_storage_platform_interface/firebase_storage_platform_interface.dart';
import 'package:mime/mime.dart' show lookupMimeType;

import 'errors.dart';
import 'firebase_storage.dart';
import 'list_result.dart';
import 'metadata.dart';
import 'task.dart';

/// A [ReferencePlatform] that runs its operations on the client of its
/// storage instance.
///
/// The path is kept as FlutterFire keeps it (the root is `/`); each operation
/// takes the client's reference for it, so that it follows the settings of
/// the instance at the time it starts.
class DartReference extends ReferencePlatform {
  DartReference(DartFirebaseStorage super.storage, super.path);

  DartFirebaseStorage get _storage => storage as DartFirebaseStorage;

  /// The client's reference for this path, with the current settings.
  fs.Reference get clientRef =>
      _storage.client.ref(fullPath == '/' ? '' : fullPath);

  @override
  Future<void> delete() => guard(() => clientRef.delete());

  @override
  Future<String> getDownloadURL() => guard(() => clientRef.downloadUrl());

  @override
  Future<FullMetadata> getMetadata() =>
      guard(() async => fullMetadataOf(await clientRef.metadata()));

  @override
  Future<FullMetadata> updateMetadata(SettableMetadata metadata) =>
      guard(() async {
        final fs.FullMetadata updated = await clientRef.updateMetadata(
          settableMetadataOf(metadata)!,
        );
        return fullMetadataOf(updated);
      });

  @override
  Future<ListResultPlatform> list([ListOptions? options]) => guard(() async {
    final fs.ListResult result = await clientRef.list(
      maxResults: options?.maxResults,
      pageToken: options?.pageToken,
    );
    return DartListResult.of(_storage, result);
  });

  @override
  Future<ListResultPlatform> listAll() => guard(() async {
    return DartListResult.of(_storage, await clientRef.listAll());
  });

  /// The bytes of the object, or an error with the code
  /// `download-size-exceeded` when it is larger than [maxSize].
  @override
  Future<Uint8List?> getData(int maxSize) =>
      guard(() => clientRef.getBytes(maxSize: maxSize));

  @override
  TaskPlatform putData(Uint8List data, [SettableMetadata? metadata]) =>
      DartUploadTask.start(
        this,
        () =>
            clientRef.startUpload(data, metadata: settableMetadataOf(metadata)),
      );

  /// Not supported: a `Blob` exists only on the web, where the official
  /// plugin has its own implementation. Use [putData].
  @override
  TaskPlatform putBlob(dynamic data, [SettableMetadata? metadata]) {
    throw UnimplementedError(
      'putBlob() is only supported on the web. Use putData() instead.',
    );
  }

  /// Streams [file] from the disk in a resumable upload. Without a content
  /// type in [metadata], the content type comes from the extension of the
  /// file name, as on Android and iOS.
  @override
  TaskPlatform putFile(File file, [SettableMetadata? metadata]) {
    final SettableMetadata? withType = withContentType(
      metadata,
      lookupMimeType(file.path),
    );
    return DartUploadTask.start(
      this,
      () => fs_io.ReferenceIo(
        clientRef,
      ).putFile(file, metadata: settableMetadataOf(withType)),
    );
  }

  /// Decodes [data] and uploads the bytes in a resumable upload, as the
  /// native SDKs do. The content type of a data URL is used unless [metadata]
  /// has one. A string that does not match [format] fails the task with the
  /// code `invalid-format`.
  @override
  TaskPlatform putString(
    String data,
    PutStringFormat format, [
    SettableMetadata? metadata,
  ]) {
    return DartUploadTask.start(this, () {
      final ({Uint8List bytes, String? contentType}) decoded = decodeString(
        data,
        format,
      );
      return clientRef.startUpload(
        decoded.bytes,
        metadata: settableMetadataOf(
          withContentType(metadata, decoded.contentType),
        ),
      );
    });
  }

  /// Downloads the object to [file]: the bytes go to a temporary file next to
  /// it, which replaces [file] once the download is complete. The task can be
  /// paused, resumed and canceled, and reports its progress.
  @override
  TaskPlatform writeToFile(File file) => DartDownloadTask.start(this, file);
}

/// [metadata] with [contentType] when it has no content type of its own.
SettableMetadata? withContentType(
  SettableMetadata? metadata,
  String? contentType,
) {
  if (contentType == null || metadata?.contentType != null) {
    return metadata;
  }
  return SettableMetadata(
    cacheControl: metadata?.cacheControl,
    contentDisposition: metadata?.contentDisposition,
    contentEncoding: metadata?.contentEncoding,
    contentLanguage: metadata?.contentLanguage,
    contentType: contentType,
    customMetadata: metadata?.customMetadata,
  );
}

/// The bytes of a string of `putString` in [format], and the media type of a
/// data URL. Throws a [FirebaseException] (`invalid-format`) when [data] does
/// not match [format].
({Uint8List bytes, String? contentType}) decodeString(
  String data,
  PutStringFormat format,
) {
  try {
    switch (format) {
      case PutStringFormat.raw:
        return (bytes: utf8.encode(data), contentType: null);
      case PutStringFormat.base64:
        return (
          bytes: base64.decode(base64.normalize(data)),
          contentType: null,
        );
      case PutStringFormat.base64Url:
        return (
          bytes: base64Url.decode(base64Url.normalize(data)),
          contentType: null,
        );
      case PutStringFormat.dataUrl:
        final UriData uri = UriData.parse(data);
        return (
          bytes: uri.contentAsBytes(),
          contentType: uri.mimeType.isEmpty ? null : uri.mimeType,
        );
    }
  } on FormatException catch (error) {
    throw storageException(
      'invalid-format',
      'The string does not match the format ${format.name}: '
          '${error.message}',
    );
  }
}
