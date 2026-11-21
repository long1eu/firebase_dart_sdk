import 'package:meta/meta.dart';

import 'errors.dart';
import 'location.dart';

/// A metadata field that [SettableMetadata.delete] can remove from an object.
enum MetadataField {
  /// `Cache-Control`.
  cacheControl,

  /// `Content-Disposition`.
  contentDisposition,

  /// `Content-Encoding`.
  contentEncoding,

  /// `Content-Language`.
  contentLanguage,

  /// `Content-Type`.
  contentType,

  /// All the custom metadata.
  customMetadata,
}

/// The metadata that an upload or `Reference.updateMetadata` can set.
///
/// A field left null is not sent: an upload uses the default of the backend (for [contentType],
/// `application/octet-stream`), and `updateMetadata` leaves the field of the object as it is. To remove a field
/// with `updateMetadata`, name it in [delete]; the JS SDK does the same with a field set to `null`, which a Dart
/// constructor cannot tell apart from a field that is not given. [customMetadata] replaces the custom keys it
/// names and keeps the others.
///
/// ```dart
/// await ref.updateMetadata(
///   const SettableMetadata(
///     cacheControl: 'public, max-age=300',
///     customMetadata: <String, String>{'owner': 'me'},
///     delete: <MetadataField>{MetadataField.contentLanguage},
///   ),
/// );
/// ```
@immutable
final class SettableMetadata {
  /// Creates the metadata; every field is optional.
  const SettableMetadata({
    this.cacheControl,
    this.contentDisposition,
    this.contentEncoding,
    this.contentLanguage,
    this.contentType,
    this.customMetadata,
    this.md5Hash,
    this.delete = const <MetadataField>{},
  });

  /// `Cache-Control` of the downloads, for example `public, max-age=300`.
  final String? cacheControl;

  /// `Content-Disposition` of the downloads, for example `attachment; filename="report.pdf"`.
  final String? contentDisposition;

  /// `Content-Encoding` of the downloads, for example `gzip`.
  final String? contentEncoding;

  /// `Content-Language` of the downloads, for example `en-US`.
  final String? contentLanguage;

  /// `Content-Type` of the object, for example `image/png`.
  final String? contentType;

  /// Your own key-value pairs.
  final Map<String, String>? customMetadata;

  /// The MD5 hash of the content in base64, sent with an upload so that the backend checks it (like
  /// `UploadMetadata.md5Hash` of the JS SDK). `updateMetadata` ignores it.
  final String? md5Hash;

  /// The fields that `Reference.updateMetadata` removes from the object. A field named here and also given a
  /// value is removed. Uploads ignore it.
  final Set<MetadataField> delete;

  /// A copy with the given fields replaced.
  SettableMetadata copyWith({
    String? cacheControl,
    String? contentDisposition,
    String? contentEncoding,
    String? contentLanguage,
    String? contentType,
    Map<String, String>? customMetadata,
    String? md5Hash,
    Set<MetadataField>? delete,
  }) {
    return SettableMetadata(
      cacheControl: cacheControl ?? this.cacheControl,
      contentDisposition: contentDisposition ?? this.contentDisposition,
      contentEncoding: contentEncoding ?? this.contentEncoding,
      contentLanguage: contentLanguage ?? this.contentLanguage,
      contentType: contentType ?? this.contentType,
      customMetadata: customMetadata ?? this.customMetadata,
      md5Hash: md5Hash ?? this.md5Hash,
      delete: delete ?? this.delete,
    );
  }

  /// The body of `updateMetadata`: the fields with a value, and those in [delete] as `null`, under the names of
  /// the REST API.
  @internal
  Map<String, Object?> toUpdateJson() {
    final Map<String, Object?> json = <String, Object?>{};
    void put(MetadataField field, String key, Object? value) {
      if (delete.contains(field)) {
        json[key] = null;
      } else if (value != null) {
        json[key] = value;
      }
    }

    put(MetadataField.cacheControl, 'cacheControl', cacheControl);
    put(
      MetadataField.contentDisposition,
      'contentDisposition',
      contentDisposition,
    );
    put(MetadataField.contentEncoding, 'contentEncoding', contentEncoding);
    put(MetadataField.contentLanguage, 'contentLanguage', contentLanguage);
    put(MetadataField.contentType, 'contentType', contentType);
    put(MetadataField.customMetadata, 'metadata', customMetadata);
    return json;
  }

  /// The metadata part of an upload of [path] (multipart, or the start of a resumable upload), like
  /// `metadataForUpload_` of the JS SDK: the object name, the content type ([contentType], else
  /// `application/octet-stream`) and the other fields with a value.
  ///
  /// Throws `invalid-argument` for a content type with a control character (CR, LF, ...): it is written into a
  /// header of the request.
  @internal
  static Map<String, Object?> uploadJson(
    String path,
    SettableMetadata? metadata,
  ) {
    final String contentType =
        metadata?.contentType ?? 'application/octet-stream';
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(contentType)) {
      throw invalidArgument(
        'The content type must not contain control characters.',
      );
    }
    return <String, Object?>{
      'name': path,
      if (metadata?.md5Hash case final String value) 'md5Hash': value,
      if (metadata?.cacheControl case final String value) 'cacheControl': value,
      if (metadata?.contentDisposition case final String value)
        'contentDisposition': value,
      if (metadata?.contentEncoding case final String value)
        'contentEncoding': value,
      if (metadata?.contentLanguage case final String value)
        'contentLanguage': value,
      'contentType': contentType,
      if (metadata?.customMetadata case final Map<String, String> value)
        'metadata': value,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is SettableMetadata &&
      other.cacheControl == cacheControl &&
      other.contentDisposition == contentDisposition &&
      other.contentEncoding == contentEncoding &&
      other.contentLanguage == contentLanguage &&
      other.contentType == contentType &&
      _mapEquals(other.customMetadata, customMetadata) &&
      other.md5Hash == md5Hash &&
      other.delete.length == delete.length &&
      other.delete.containsAll(delete);

  @override
  int get hashCode => Object.hash(
    cacheControl,
    contentDisposition,
    contentEncoding,
    contentLanguage,
    contentType,
    customMetadata == null
        ? null
        : Object.hashAllUnordered(customMetadata!.entries.map(_entryHash)),
    md5Hash,
    Object.hashAllUnordered(delete),
  );

  @override
  String toString() =>
      'SettableMetadata(cacheControl: $cacheControl, contentDisposition: $contentDisposition, '
      'contentEncoding: $contentEncoding, contentLanguage: $contentLanguage, contentType: $contentType, '
      'customMetadata: $customMetadata, md5Hash: $md5Hash, delete: $delete)';
}

/// The metadata of an object, as the backend returns it.
///
/// [toJson] gives the fields under these names (dates as ISO 8601 strings), for logs and for the FlutterFire
/// shim.
@immutable
final class FullMetadata {
  /// Creates metadata; the package creates them from responses, you need this only in tests.
  const FullMetadata({
    required this.bucket,
    required this.fullPath,
    this.generation,
    this.metageneration,
    this.size,
    this.md5Hash,
    this.timeCreated,
    this.updated,
    this.cacheControl,
    this.contentDisposition,
    this.contentEncoding,
    this.contentLanguage,
    this.contentType,
    this.customMetadata,
    this.downloadTokens = const <String>[],
  });

  /// Reads a metadata resource of the REST API, like `fromResource` of the JS SDK (with types: [size] is an
  /// integer, the dates are [DateTime]s). [fallbackBucket] is used when the resource has no `bucket`.
  @internal
  factory FullMetadata.fromResource(
    Map<String, Object?> resource, {
    required String fallbackBucket,
  }) {
    final Object? metadata = resource['metadata'];
    final Object? tokens = resource['downloadTokens'];
    return FullMetadata(
      bucket: _string(resource['bucket']) ?? fallbackBucket,
      fullPath: _string(resource['name']) ?? '',
      generation: _string(resource['generation']),
      metageneration: _string(resource['metageneration']),
      size: switch (resource['size']) {
        final int value => value,
        final num value => value.toInt(),
        final String value => int.tryParse(value),
        _ => null,
      },
      md5Hash: _string(resource['md5Hash']),
      timeCreated: _date(resource['timeCreated']),
      updated: _date(resource['updated']),
      cacheControl: _string(resource['cacheControl']),
      contentDisposition: _string(resource['contentDisposition']),
      contentEncoding: _string(resource['contentEncoding']),
      contentLanguage: _string(resource['contentLanguage']),
      contentType: _string(resource['contentType']),
      customMetadata: metadata is Map<String, Object?>
          ? <String, String>{
              for (final MapEntry<String, Object?> entry in metadata.entries)
                if (entry.value != null) entry.key: '${entry.value}',
            }
          : null,
      downloadTokens: tokens is String
          ? tokens.split(',').where((String t) => t.isNotEmpty).toList()
          : const <String>[],
    );
  }

  /// The bucket of the object.
  final String bucket;

  /// The path of the object in the bucket.
  final String fullPath;

  /// The last component of [fullPath].
  String get name => lastComponent(fullPath);

  /// The generation of the object's content (a decimal number as a string).
  final String? generation;

  /// The generation of the object's metadata (a decimal number as a string).
  final String? metageneration;

  /// The size of the object in bytes.
  final int? size;

  /// The MD5 hash of the content, in base64.
  final String? md5Hash;

  /// When the object was created.
  final DateTime? timeCreated;

  /// When the object was last changed.
  final DateTime? updated;

  /// `Cache-Control` of the downloads.
  final String? cacheControl;

  /// `Content-Disposition` of the downloads.
  final String? contentDisposition;

  /// `Content-Encoding` of the downloads.
  final String? contentEncoding;

  /// `Content-Language` of the downloads.
  final String? contentLanguage;

  /// `Content-Type` of the object.
  final String? contentType;

  /// The custom key-value pairs.
  final Map<String, String>? customMetadata;

  /// The download tokens of the object; `Reference.downloadUrl` uses the first. Empty when there are none.
  final List<String> downloadTokens;

  /// The fields of this metadata; null fields are left out.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'bucket': bucket,
      'fullPath': fullPath,
      'name': name,
      'generation': ?generation,
      'metageneration': ?metageneration,
      'size': ?size,
      'md5Hash': ?md5Hash,
      'timeCreated': ?timeCreated?.toIso8601String(),
      'updated': ?updated?.toIso8601String(),
      'cacheControl': ?cacheControl,
      'contentDisposition': ?contentDisposition,
      'contentEncoding': ?contentEncoding,
      'contentLanguage': ?contentLanguage,
      'contentType': ?contentType,
      'customMetadata': ?customMetadata,
      'downloadTokens': downloadTokens,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is FullMetadata &&
      other.bucket == bucket &&
      other.fullPath == fullPath &&
      other.generation == generation &&
      other.metageneration == metageneration &&
      other.size == size &&
      other.md5Hash == md5Hash &&
      other.timeCreated == timeCreated &&
      other.updated == updated &&
      other.cacheControl == cacheControl &&
      other.contentDisposition == contentDisposition &&
      other.contentEncoding == contentEncoding &&
      other.contentLanguage == contentLanguage &&
      other.contentType == contentType &&
      _mapEquals(other.customMetadata, customMetadata) &&
      _listEquals(other.downloadTokens, downloadTokens);

  @override
  int get hashCode => Object.hash(bucket, fullPath, generation, metageneration);

  @override
  String toString() {
    // Download tokens grant access to the object: never part of the string form.
    final Map<String, Object?> fields = toJson()
      ..['downloadTokens'] = '<${downloadTokens.length} redacted>';
    return 'FullMetadata($fields)';
  }

  static String? _string(Object? value) => value is String ? value : null;

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

int _entryHash(MapEntry<String, String> entry) =>
    Object.hash(entry.key, entry.value);

bool _mapEquals(Map<String, String>? a, Map<String, String>? b) {
  if (a == null || b == null) {
    return a == b;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry<String, String> entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
