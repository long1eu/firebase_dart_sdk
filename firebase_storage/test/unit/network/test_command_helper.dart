// File created by
// Lung Razvan <long1eu>
// on 23/10/2018

import 'dart:async';

import 'package:firebase_storage/src/firebase_storage.dart';
import 'package:firebase_storage/src/storage_exception.dart';
import 'package:firebase_storage/src/storage_metadata.dart';
import 'package:firebase_storage/src/storage_reference.dart';

Future<StringBuffer> testDownloadUrl() async {
  final StorageReference ref = FirebaseStorage.getInstance()
      .getReferenceFromUrl(
          'gs://project-5516366556574091405.appspot.com/flubbertest.txt');

  final StringBuffer builder = StringBuffer()..write('Getting Download Url.\n');

  final Uri uri = await ref.downloadUrl;

  builder
    ..write('Received Download Url.\n')
    ..write('getDownloadUrl:')
    ..write(uri.toString())
    ..write('\nonComplete:Success=\n')
    ..write(true);

  return builder;
}

Future<StringBuffer> _getMetadata(StorageReference ref) async {
  final StringBuffer builder = StringBuffer()..write('Getting Metadata.\n');
  final StorageMetadata metadata = await ref.metadata;

  builder.write('Received Metadata.\n');
  dumpMetadata(builder, metadata);

  return builder;
}

Future<StringBuffer> _updateMetadata(
    StorageReference ref, StorageMetadata metadata) async {
  final StringBuffer builder = StringBuffer();

  final StringBuffer originalMetadata = await _getMetadata(ref);

  builder //
    ..write(originalMetadata)
    ..write('Updating Metadata.\n');
  final StorageMetadata updatedMetadata = await ref.updateMetadata(metadata);

  builder.write('Updated Metadata.\n');
  dumpMetadata(builder, updatedMetadata);

  final StringBuffer verifiedMetadata = await _getMetadata(ref);
  return builder..write(verifiedMetadata);
}

Future<StringBuffer> testUpdateMetadata() {
  final StorageReference storage = FirebaseStorage.getInstance()
      .getReferenceFromUrl(
          'gs://project-5516366556574091405.appspot.com/flubbertest.txt');

  final StorageMetadata metadata = StorageMetadata.update(
      customMetadata: <String, String>{
        'newKey': 'newValue',
        'newKey2': 'newValue2'
      });

  return _updateMetadata(storage, metadata);
}

Future<StringBuffer> testUnicodeMetadata() {
  final StorageMetadata unicodeMetadata =
      StorageMetadata.update(customMetadata: <String, String>{'unicode': '☺'});
  final StorageReference storage = FirebaseStorage.getInstance()
      .getReferenceFromUrl(
          'gs://project-5516366556574091405.appspot.com/flubbertest.txt');

  return _updateMetadata(storage, unicodeMetadata);
}

Future<StringBuffer> testClearMetadata() async {
  final StorageMetadata fullMetadata = StorageMetadata.update(
    cacheControl: 'cache-control',
    contentDisposition: 'content-disposition',
    contentEncoding: 'gzip',
    contentLanguage: 'de',
    contentType: 'content-type',
    customMetadata: <String, String>{
      'key': 'value',
    },
  );

  final StorageMetadata emptyMetadata = StorageMetadata.update(
    cacheControl: null,
    contentDisposition: null,
    contentEncoding: null,
    contentLanguage: null,
    contentType: null,
    customMetadata: <String, String>{
      'key': null,
    },
  );

  final StorageReference storage = FirebaseStorage.instance.getReferenceFromUrl(
      'gs://project-5516366556574091405.appspot.com/flubbertest.txt');

  final StringBuffer fullMetadataTask =
      await _updateMetadata(storage, fullMetadata);
  final StringBuffer updatedMetadataTask =
      await _updateMetadata(storage, emptyMetadata);

  return fullMetadataTask..write(updatedMetadataTask);
}

void dumpMetadata(final StringBuffer builder, StorageMetadata metadata) {
  if (metadata == null) {
    builder.write('metadata:null\n');
    return;
  }
  builder
    ..write('getBucket:')
    ..write(metadata.bucket)
    ..write('\n')
    ..write('getCacheControl:')
    ..write(metadata.cacheControl)
    ..write('\n')
    ..write('getContentDisposition:')
    ..write(metadata.contentDisposition)
    ..write('\n')
    ..write('getContentEncoding:')
    ..write(metadata.contentEncoding)
    ..write('\n')
    ..write('getContentLanguage:')
    ..write(metadata.contentLanguage)
    ..write('\n')
    ..write('getContentType:')
    ..write(metadata.contentType)
    ..write('\n')
    ..write('getName:')
    ..write(metadata.name)
    ..write('\n')
    ..write('getPath:')
    ..write(metadata.path)
    ..write('\n')
    ..write('getMD5Hash:')
    ..write(metadata.md5Hash)
    ..write('\n')
    ..write('getGeneration:')
    ..write(metadata.generation)
    ..write('\n')
    ..write('getMetadataGeneration:')
    ..write(metadata.metadataGeneration)
    ..write('\n')
    ..write('getSizeBytes:')
    ..write(metadata.sizeBytes)
    ..write('\n')
    ..write('getReference:')
    ..write(metadata.reference.name)
    ..write('\n')
    ..write('getCreationTimeMillis:')
    ..write(DateTime.fromMillisecondsSinceEpoch(metadata.creationTimeMillis))
    ..write('\n')
    ..write('getUpdatedTimeMillis:')
    ..write(DateTime.fromMillisecondsSinceEpoch(metadata.updatedTimeMillis))
    ..write('\n')
    ..write('Type:FILE\n');

  for (String key in metadata.customMetadataKeys.toList()..sort()) {
    builder..write(key)..write(':')..write(metadata[key])..write('\n');
  }
}

Future<StringBuffer> deleteBlob() async {
  final StringBuffer builder = StringBuffer()..write('deleting.\n');
  final StorageReference storage = FirebaseStorage.getInstance()
      .getReferenceFromUrl(
          'gs://project-5516366556574091405.appspot.com/flubbertest.txt');

  try {
    await storage.delete();
    builder.write('onComplete.\n');
  } on StorageException catch (se) {
    builder
      ..write('onError.\n')
      ..write(se.errorCode)
      ..write(se.cause != null ? se.cause.toString() : 'no cause');
  }
  return builder;
}
