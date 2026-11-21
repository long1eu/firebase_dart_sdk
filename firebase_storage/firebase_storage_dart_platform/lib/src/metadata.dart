import 'package:firebase_storage_dart/firebase_storage_dart.dart' as fs;
import 'package:firebase_storage_platform_interface/firebase_storage_platform_interface.dart';

/// The map behind a FlutterFire [FullMetadata], with the keys its getters read
/// (the keys of the native implementations).
///
/// The JS SDK and the client have one `metageneration`; FlutterFire has both
/// `metageneration` and `metadataGeneration`, which get the same value.
Map<String, dynamic> metadataMapOf(fs.FullMetadata metadata) =>
    <String, dynamic>{
      'bucket': metadata.bucket,
      'fullPath': metadata.fullPath,
      'name': metadata.name,
      'generation': metadata.generation,
      'metageneration': metadata.metageneration,
      'metadataGeneration': metadata.metageneration,
      'size': metadata.size,
      'md5Hash': metadata.md5Hash,
      'creationTimeMillis': metadata.timeCreated?.millisecondsSinceEpoch,
      'updatedTimeMillis': metadata.updated?.millisecondsSinceEpoch,
      'cacheControl': metadata.cacheControl,
      'contentDisposition': metadata.contentDisposition,
      'contentEncoding': metadata.contentEncoding,
      'contentLanguage': metadata.contentLanguage,
      'contentType': metadata.contentType,
      'customMetadata': metadata.customMetadata,
    };

/// The FlutterFire [FullMetadata] of the client's [metadata].
FullMetadata fullMetadataOf(fs.FullMetadata metadata) =>
    FullMetadata(metadataMapOf(metadata));

/// The client's metadata for a FlutterFire [metadata].
///
/// A null field is not sent, as on Android and iOS: an upload takes the
/// backend's default, `updateMetadata` leaves the field as it is. The official
/// API has no way to remove a field.
fs.SettableMetadata? settableMetadataOf(SettableMetadata? metadata) {
  if (metadata == null) {
    return null;
  }
  return fs.SettableMetadata(
    cacheControl: metadata.cacheControl,
    contentDisposition: metadata.contentDisposition,
    contentEncoding: metadata.contentEncoding,
    contentLanguage: metadata.contentLanguage,
    contentType: metadata.contentType,
    customMetadata: metadata.customMetadata,
  );
}
