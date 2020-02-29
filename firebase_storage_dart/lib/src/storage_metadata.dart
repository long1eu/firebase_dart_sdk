// File created by
// Lung Razvan <long1eu>
// on 21/10/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/firebase_storage.dart';
import 'package:firebase_storage/src/internal/slash_util.dart';
import 'package:firebase_storage/src/internal/util.dart';
import 'package:firebase_storage/src/storage_reference.dart';
import 'package:meta/meta.dart';

/// Metadata for a [StorageReference]. Metadata stores default attributes such
/// as size and content type. You may also store custom metadata key value
/// pairs. Metadata values may be used to authorize operations using declarative
/// validation rules.
class StorageMetadata {
  // TODO(long1eu):{23/10/2018 15:11}-long1eu: find a way to create metadata for update
  /// Creates a [StorageMetadata] object to hold metadata for a
  /// [StorageReference]
  StorageMetadata._({
    String path,
    FirebaseStorage storage,
    StorageReference reference,
    this.bucket,
    this.generation,
    this.metadataGeneration,
    this.creationTimeMillis,
    this.updatedTimeMillis,
    this.sizeBytes,
    this.md5Hash,
    _MetadataValue<String> contentEncoding,
    _MetadataValue<String> cacheControl,
    _MetadataValue<String> contentDisposition,
    _MetadataValue<String> contentLanguage,
    _MetadataValue<String> contentType,
    _MetadataValue<Map<String, String>> customMetadata,
  })  : path = path ?? '',
        _storage = storage,
        _reference = reference,
        _contentEncoding =
            contentEncoding ?? _MetadataValue<String>.withDefaultValue(''),
        _cacheControl =
            cacheControl ?? _MetadataValue<String>.withDefaultValue(''),
        _contentDisposition =
            contentDisposition ?? _MetadataValue<String>.withDefaultValue(''),
        _contentLanguage =
            contentLanguage ?? _MetadataValue<String>.withDefaultValue(''),
        _contentType =
            contentType ?? _MetadataValue<String>.withDefaultValue(''),
        _customMetadata = customMetadata ??
            _MetadataValue<Map<String, String>>.withDefaultValue(
                <String, String>{});

  factory StorageMetadata.update({
    String contentEncoding,
    String cacheControl,
    String contentDisposition,
    String contentLanguage,
    String contentType,
    Map<String, String> customMetadata,
  }) {
    return StorageMetadata._().copyWith(
      contentEncoding: contentEncoding,
      cacheControl: cacheControl,
      contentDisposition: contentDisposition,
      contentLanguage: contentLanguage,
      contentType: contentType,
      customMetadata: customMetadata,
    );
  }

  factory StorageMetadata.fromJson(
      Map<String, dynamic> jsonObject, StorageReference storageRef) {
    String extractString(Map<String, dynamic> jsonObject, String key) {
      if (jsonObject.containsKey(key) && jsonObject[key] != null) {
        final String value = jsonObject[key];
        return value;
      }
      return null;
    }

    final String generation = jsonObject[_kGenerationKey];
    final String path = jsonObject[_kNameKey];
    final String bucket = jsonObject[_kBucketKey];
    final String metadataGeneration = jsonObject[_kMetaGenerationKey];

    final String creationTime = jsonObject[_kTimeCreatedKey];
    final String updatedTime = jsonObject[_kTimeUpdatedKey];
    final int creationTimeMillis = parseDateTime(creationTime);
    final int updatedTimeMillis = parseDateTime(updatedTime);

    final int sizeBytes = jsonObject[_kSizeKey];
    final String md5Hash = jsonObject[_kMd5HashKey];

    final String contentType = extractString(jsonObject, _kContentTypeKey);
    final String cacheControl = extractString(jsonObject, _kCacheControl);
    final String contentDisposition =
        extractString(jsonObject, _kContentDisposition);
    final String contentEncoding = extractString(jsonObject, _kContentEncoding);
    final String contentLanguage = extractString(jsonObject, _kContentLanguage);
    final Map<String, String> customMetadata = <String, String>{};

    if (jsonObject.containsKey(_kCustomMetadataKey) &&
        jsonObject[_kCustomMetadataKey] != null) {
      final Map<String, String> custom = jsonObject[_kCustomMetadataKey];

      for (String key in custom.keys) {
        customMetadata[key] = custom[key];
      }
    }

    return StorageMetadata._(
      path: path,
      reference: storageRef,
      bucket: bucket,
      generation: generation,
      metadataGeneration: metadataGeneration,
      creationTimeMillis: creationTimeMillis,
      updatedTimeMillis: updatedTimeMillis,
      sizeBytes: sizeBytes,
      md5Hash: md5Hash,
      contentEncoding: _MetadataValue<String>.withUserValue(contentEncoding),
      cacheControl: _MetadataValue<String>.withUserValue(cacheControl),
      contentDisposition:
          _MetadataValue<String>.withUserValue(contentDisposition),
      contentLanguage: _MetadataValue<String>.withUserValue(contentLanguage),
      contentType: _MetadataValue<String>.withUserValue(contentType),
      customMetadata:
          _MetadataValue<Map<String, String>>.withUserValue(customMetadata),
    );
  }

  static const String _tag = 'StorageMetadata';

  static const String _kContentLanguage = 'contentLanguage';
  static const String _kContentEncoding = 'contentEncoding';
  static const String _kContentDisposition = 'contentDisposition';
  static const String _kCacheControl = 'cacheControl';
  static const String _kCustomMetadataKey = 'metadata';
  static const String _kContentTypeKey = 'contentType';
  static const String _kMd5HashKey = 'md5Hash';
  static const String _kSizeKey = 'size';
  static const String _kTimeUpdatedKey = 'updated';
  static const String _kTimeCreatedKey = 'timeCreated';
  static const String _kMetaGenerationKey = 'metageneration';
  static const String _kBucketKey = 'bucket';
  static const String _kNameKey = 'name';
  static const String _kGenerationKey = 'generation';

  final String path;
  final FirebaseStorage _storage;
  final StorageReference _reference;

  /// Return the owning Google Cloud Storage bucket for the [StorageReference]
  final String bucket;

  /// Returns a version String indicating what version of the [StorageReference]
  final String generation;

  /// Returns a version String indicating the version of this [StorageMetadata]
  final String metadataGeneration;

  /// Returns the time the [StorageReference] was created.
  final int creationTimeMillis;

  /// Returns the time the [StorageReference] was last updated.
  final int updatedTimeMillis;

  /// Returns the stored Size in bytes of the [StorageReference] object
  final int sizeBytes;

  /// Return the MD5Hash of the [StorageReference] object
  final String md5Hash;

  final _MetadataValue<String> _contentEncoding;
  final _MetadataValue<String> _cacheControl;
  final _MetadataValue<String> _contentDisposition;
  final _MetadataValue<String> _contentLanguage;
  final _MetadataValue<String> _contentType;
  final _MetadataValue<Map<String, String>> _customMetadata;

  StorageMetadata copyWith(
      {String path,
      FirebaseStorage storage,
      StorageReference reference,
      String bucket,
      String contentType,
      String cacheControl,
      String contentDisposition,
      String contentEncoding,
      String contentLanguage,
      Map<String, String> customMetadata}) {
    return StorageMetadata._(
      path: path ?? this.path,
      storage: storage ?? _storage,
      reference: reference ?? _reference,
      bucket: bucket ?? this.bucket,
      contentType: contentType != null
          ? _MetadataValue<String>.withUserValue(contentType)
          : _contentType,
      cacheControl: cacheControl != null
          ? _MetadataValue<String>.withUserValue(cacheControl)
          : _cacheControl,
      contentDisposition: contentDisposition != null
          ? _MetadataValue<String>.withUserValue(contentDisposition)
          : _contentDisposition,
      contentEncoding: contentEncoding != null
          ? _MetadataValue<String>.withUserValue(contentEncoding)
          : _contentEncoding,
      contentLanguage: contentLanguage != null
          ? _MetadataValue<String>.withUserValue(contentLanguage)
          : _contentLanguage,
      customMetadata: customMetadata != null
          ? _MetadataValue<Map<String, String>>.withUserValue(customMetadata)
          : _customMetadata,
      md5Hash: md5Hash,
      sizeBytes: sizeBytes,
      updatedTimeMillis: updatedTimeMillis,
      creationTimeMillis: creationTimeMillis,
      metadataGeneration: metadataGeneration,
      generation: generation,
    );
  }

  /// Return the content type of the [StorageReference].
  String get contentType => _contentType.value;

  /// Returns custom metadata for a [StorageReference]
  ///
  /// The [key] for which the metadata should be returned. Returns the metadata
  /// stored in the object the given key.
  String operator [](String key) {
    if (key == null || key.isEmpty) {
      return null;
    }
    final Map<String, String> metadata = _customMetadata.value;
    return metadata[key];
  }

  /// Returns the keys for custom metadata.
  Set<String> get customMetadataKeys {
    final Map<String, String> metadata = _customMetadata.value;
    return metadata.keys.toSet();
  }

  /// Returns a simple name of the [StorageReference] object
  String get name {
    if (path == null || path.isEmpty) {
      return null;
    }

    final int lastIndex = path.lastIndexOf('/');
    if (lastIndex != -1) {
      return path.substring(lastIndex + 1);
    }
    return path;
  }

  /// Returns the Cache Control setting of the [StorageReference]
  String get cacheControl => _cacheControl.value;

  /// Returns the content disposition of the [StorageReference]
  String get contentDisposition => _contentDisposition.value;

  /// Returns the content encoding for the [StorageReference]
  String get contentEncoding => _contentEncoding.value;

  /// Returns the content language for the [StorageReference]
  String get contentLanguage => _contentLanguage.value;

  /// Returns the associated [StorageReference] for which this metadata belongs
  /// to.
  StorageReference get reference {
    if (_reference == null) {
      if (_storage != null) {
        if (bucket == null || bucket.isEmpty || path == null || path.isEmpty) {
          return null;
        }

        Uri uri;
        try {
          uri = Uri.parse('gs://$bucket/${preserveSlashEncode(path)}');
        } on FormatException catch (e) {
          Log.e(_tag, 'Unable to create a valid default Uri. $bucket$path');
          throw StateError(e.message);
        }

        return StorageReference(uri, _storage);
      }
    }
    return _reference;
  }

  Map<String, dynamic> createJson() {
    final Map<String, dynamic> data = <String, dynamic>{};

    if (_contentType.userProvided) {
      data[_kContentTypeKey] = contentType;
    }
    if (_customMetadata.userProvided) {
      data[_kCustomMetadataKey] = _customMetadata.value;
    }
    if (_cacheControl.userProvided) {
      data[_kCacheControl] = cacheControl;
    }
    if (_contentDisposition.userProvided) {
      data[_kContentDisposition] = contentDisposition;
    }
    if (_contentEncoding.userProvided) {
      data[_kContentEncoding] = contentEncoding;
    }
    if (_contentLanguage.userProvided) {
      data[_kContentLanguage] = contentLanguage;
    }

    return data;
  }
}

class MetadataUpdate {}

/// Stores metadata values and indicates whether these are defaults or
/// user-provided.
class _MetadataValue<T> {
  _MetadataValue({@required this.value, @required this.userProvided});

  /// Creates an optional that doesn't have a user provided value and returns
  /// the default value. isUserProvided() will return false.
  factory _MetadataValue.withDefaultValue(T value) {
    return _MetadataValue<T>(value: value, userProvided: false);
  }

  /// Creates an optional that returns the user-provided value. [userProvided]
  /// will be true.
  factory _MetadataValue.withUserValue(T value) {
    return _MetadataValue<T>(value: value, userProvided: true);
  }

  final bool userProvided;
  final T value;
}
