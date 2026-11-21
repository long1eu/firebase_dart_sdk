import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'errors.dart';
import 'firebase_storage.dart';
import 'list_result.dart';
import 'location.dart';
import 'metadata.dart';
import 'request/requester.dart';
import 'string_format.dart';
import 'upload/multipart.dart';

/// A pointer to an object (or a "folder") in a Cloud Storage bucket. Creating one makes no request.
///
/// Get one from `FirebaseStorage.ref` or `FirebaseStorage.refFromUrl`, and walk with [child], [parent] and
/// [root]. Two references are equal when they point to the same path in the same bucket.
///
/// The operations that act on an object ([metadata], [updateMetadata], [downloadUrl], [delete], [getBytes],
/// [putBytes], [putString]) throw `invalid-root-operation` on the root of the bucket. They fail with a
/// `FirebaseStorageException`; see its codes. After `FirebaseStorage.close` they throw a [StateError].
///
/// ```dart
/// final Reference avatar = storage.ref('users/$uid/avatar.png');
/// await avatar.putBytes(png, metadata: const SettableMetadata(contentType: 'image/png'));
/// final Uint8List bytes = await avatar.getBytes(maxSize: 1024 * 1024);
/// print('${avatar.gsUri} has ${bytes.length} bytes');
/// ```
@immutable
final class Reference {
  /// The reference to [location] of [storage]. Use `FirebaseStorage.ref` instead.
  @internal
  const Reference.fromLocation(this.storage, this.location);

  /// The instance this reference belongs to.
  final FirebaseStorage storage;

  /// The bucket and path.
  @internal
  final Location location;

  /// The bucket of the object.
  String get bucket => location.bucket;

  /// The path of the object in the bucket, without a leading slash; empty for the root.
  String get fullPath => location.path;

  /// The last component of [fullPath]; empty for the root.
  String get name => lastComponent(location.path);

  /// The reference one level up, or null at the root.
  Reference? get parent {
    final String? path = parentPath(location.path);
    return path == null ? null : _at(path);
  }

  /// The root of the bucket.
  Reference get root => _at('');

  /// The reference at [path] below this one. Leading, trailing and repeated slashes in [path] are dropped, so
  /// `child('a//b/')` is `child('a/b')`, and `child('')` is this reference.
  Reference child(String path) => _at(joinPath(location.path, path));

  /// The `gs://bucket/path` URI of this reference.
  Uri get gsUri => Uri(scheme: 'gs', host: bucket, path: '/$fullPath');

  /// Reads the metadata of the object.
  Future<FullMetadata> metadata() async {
    throwIfRoot('metadata');
    final StorageResponse response = await _requester.send(
      StorageRequest(
        method: 'GET',
        url: objectUrl(),
        timeout: storage.retry.operation,
        errorMapper: _objectErrors(),
      ),
    );
    return metadataOf(response);
  }

  /// Changes the metadata of the object and returns the new metadata.
  ///
  /// Only the fields of [metadata] with a value are changed, and those it names in [SettableMetadata.delete]
  /// are removed; the others stay as they are.
  Future<FullMetadata> updateMetadata(SettableMetadata metadata) async {
    throwIfRoot('updateMetadata');
    final StorageResponse response = await _requester.send(
      StorageRequest(
        method: 'PATCH',
        url: objectUrl(),
        headers: const <String, String>{
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: utf8.encode(jsonEncode(metadata.toUpdateJson())),
        timeout: storage.retry.operation,
        errorMapper: _objectErrors(),
      ),
    );
    return metadataOf(response);
  }

  /// A long-lived URL that downloads the object without credentials, made of its first download token.
  ///
  /// Throws `no-download-url` when the object has no download token.
  Future<String> downloadUrl() async {
    throwIfRoot('downloadUrl');
    final StorageResponse response = await _requester.send(
      StorageRequest(
        method: 'GET',
        url: objectUrl(),
        timeout: storage.retry.operation,
        errorMapper: _objectErrors(),
      ),
    );
    final FullMetadata metadata = metadataOf(response);
    if (metadata.downloadTokens.isEmpty) {
      throw noDownloadUrl();
    }
    final Location target = Location(metadata.bucket, metadata.fullPath);
    return '${storage.origin}/v0${target.fullUrlPart}'
        '${_query(<String, String>{'alt': 'media', 'token': metadata.downloadTokens.first})}';
  }

  /// Deletes the object.
  Future<void> delete() async {
    throwIfRoot('delete');
    await _requester.send(
      StorageRequest(
        method: 'DELETE',
        url: objectUrl(),
        successCodes: const <int>{200, 204},
        timeout: storage.retry.operation,
        errorMapper: _objectErrors(),
      ),
    );
  }

  /// Lists one page of the objects and prefixes directly under this reference.
  ///
  /// [maxResults] (1 to 1000) caps the size of the page; without it the backend returns up to 1000. Pass the
  /// [ListResult.nextPageToken] of a page as [pageToken] for the next one. Throws `invalid-argument` for a
  /// [maxResults] out of range. A missing bucket fails with `unknown` and the HTTP status 404, like the JS
  /// SDK: listing does not map 404 to `object-not-found`.
  Future<ListResult> list({int? maxResults, String? pageToken}) async {
    if (maxResults != null && maxResults < 1) {
      throw invalidArgument(
        "Invalid value for 'maxResults'. Expected 1 or greater.",
      );
    }
    if (maxResults != null && maxResults > 1000) {
      throw invalidArgument(
        "Invalid value for 'maxResults'. Expected 1000 or less.",
      );
    }
    final Map<String, String> query = <String, String>{
      'prefix': location.isRoot ? '' : '${location.path}/',
      'delimiter': '/',
      if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      if (maxResults != null) 'maxResults': '$maxResults',
    };
    final StorageResponse response = await _requester.send(
      StorageRequest(
        method: 'GET',
        url: Uri.parse(
          '${storage.origin}/v0${location.bucketOnlyUrlPart}${_query(query)}',
        ),
        timeout: storage.retry.operation,
        errorMapper: sharedErrorMapper(bucket, fullPath),
      ),
    );
    return _listResultOf(response);
  }

  /// Lists every object and prefix directly under this reference, following the pages.
  ///
  /// It holds everything in memory; for large folders prefer [listPages].
  Future<ListResult> listAll() async {
    final List<Reference> items = <Reference>[];
    final List<Reference> prefixes = <Reference>[];
    await for (final ListResult page in listPages()) {
      items.addAll(page.items);
      prefixes.addAll(page.prefixes);
    }
    return ListResult(items: items, prefixes: prefixes);
  }

  /// The pages of [list], one after another: the next page is requested when the previous one was delivered
  /// and the stream is listened to. [pageSize] is the `maxResults` of each page.
  Stream<ListResult> listPages({int? pageSize}) async* {
    String? pageToken;
    do {
      final ListResult page = await list(
        maxResults: pageSize,
        pageToken: pageToken,
      );
      yield page;
      pageToken = page.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);
  }

  /// Downloads the object into memory.
  ///
  /// With [maxSize], only that many bytes are requested (with a `Range` header) and an object larger than
  /// [maxSize] throws `download-size-exceeded`, like the Android, iOS and C++ SDKs; reading stops as soon as
  /// more than [maxSize] bytes arrived. The JS SDK returns the first [maxSize] bytes instead. A negative [maxSize] throws `invalid-argument`.
  Future<Uint8List> getBytes({int? maxSize}) async {
    throwIfRoot('getBytes');
    if (maxSize != null && maxSize < 0) {
      throw invalidArgument(
        "Invalid value for 'maxSize'. Expected 0 or greater.",
      );
    }
    final StorageResponse response;
    try {
      response = await _requester.send(
        maxBodyBytes: maxSize,
        StorageRequest(
          method: 'GET',
          url: objectUrl(media: true),
          // Like the JS SDK, one byte more than the maximum: that byte tells an object that is too large.
          headers: <String, String>{
            if (maxSize != null) 'Range': 'bytes=0-$maxSize',
          },
          successCodes: maxSize == null
              ? const <int>{200}
              : const <int>{200, 206},
          timeout: storage.retry.download,
          errorMapper: _objectErrors(),
        ),
      );
    } on BodyTooLargeException {
      // Reading stopped at maxSize + 1 bytes, even from a server that ignores the Range header.
      throw downloadSizeExceeded(fullPath, maxSize!);
    }
    return response.bodyBytes;
  }

  /// Uploads [data] in one multipart request and returns the metadata of the new object, replacing an object
  /// at the same path. The content type is that of [metadata], else `application/octet-stream`.
  Future<FullMetadata> putBytes(Uint8List data, {SettableMetadata? metadata}) {
    throwIfRoot('putBytes');
    return _multipartUpload(data, metadata);
  }

  /// Uploads [data], read in [format], in one multipart request and returns the metadata of the new object.
  ///
  /// For [StringFormat.dataUrl], the media type of the data URL is the content type of the object unless
  /// [metadata] has one. Throws `invalid-format` when [data] does not match [format].
  Future<FullMetadata> putString(
    String data, {
    StringFormat format = StringFormat.raw,
    SettableMetadata? metadata,
  }) async {
    throwIfRoot('putString');
    final StringData decoded = dataFromString(format, data);
    SettableMetadata? effective = metadata;
    final String? dataUrlType = decoded.contentType;
    if (dataUrlType != null && metadata?.contentType == null) {
      effective = (metadata ?? const SettableMetadata()).copyWith(
        contentType: dataUrlType,
      );
    }
    return _multipartUpload(decoded.bytes, effective);
  }

  Future<FullMetadata> _multipartUpload(
    Uint8List data,
    SettableMetadata? metadata,
  ) async {
    final StorageResponse response = await _requester.send(
      multipartRequest(data, metadata),
    );
    return metadataOf(response);
  }

  /// The multipart upload of [data] with [metadata] (`multipartUpload` of the JS SDK), for `putBytes`,
  /// `putString` and the small uploads of an upload task. Throws `invalid-argument` for a content type with a
  /// control character.
  @internal
  StorageRequest multipartRequest(Uint8List data, SettableMetadata? metadata) {
    final String boundary = multipartBoundary();
    return StorageRequest(
      method: 'POST',
      url: uploadUrl,
      headers: <String, String>{
        'X-Goog-Upload-Protocol': 'multipart',
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: multipartBody(
        boundary: boundary,
        metadata: SettableMetadata.uploadJson(fullPath, metadata),
        data: data,
      ),
      timeout: storage.retry.upload,
      errorMapper: sharedErrorMapper(bucket, fullPath),
    );
  }

  /// The URL that uploads (multipart or resumable start) go to: `/v0/b/<bucket>/o?name=<path>`.
  @internal
  Uri get uploadUrl => Uri.parse(
    '${storage.origin}/v0${location.bucketOnlyUrlPart}'
    '${_query(<String, String>{'name': fullPath})}',
  );

  /// The URL of the object's metadata and, with `?alt=media`, of its content.
  @internal
  Uri objectUrl({bool media = false}) => Uri.parse(
    '${storage.origin}/v0${location.fullUrlPart}${media ? '?alt=media' : ''}',
  );

  /// Throws `invalid-root-operation` for [operation] when this is the root of the bucket.
  @internal
  ///
  /// Also throws `invalid-argument` for the paths `.` and `..`: Cloud Storage forbids those names, and a URL
  /// would resolve them as dot segments to another resource.
  void throwIfRoot(String operation) {
    if (location.isRoot) {
      throw invalidRootOperation(operation);
    }
    if (location.path == '.' || location.path == '..') {
      throw invalidArgument("The object name '${location.path}' is not valid.");
    }
  }

  /// Reads the metadata in the body of [response]; throws `unknown` when it is not a JSON object.
  @internal
  FullMetadata metadataOf(StorageResponse response) =>
      FullMetadata.fromResource(response.jsonObject, fallbackBucket: bucket);

  Requester get _requester => storage.requester;

  StorageErrorMapper _objectErrors() => objectErrorMapper(bucket, fullPath);

  ListResult _listResultOf(StorageResponse response) {
    final Map<String, Object?> json = response.jsonObject;
    final List<Reference> prefixes = <Reference>[
      for (final Object? prefix in _listOf(json['prefixes']))
        if (prefix is String) _at(prefix.replaceFirst(RegExp(r'/$'), '')),
    ];
    final List<Reference> items = <Reference>[
      for (final Object? item in _listOf(json['items']))
        if (item case <String, Object?>{'name': final String name}) _at(name),
    ];
    final Object? token = json['nextPageToken'];
    return ListResult(
      items: items,
      prefixes: prefixes,
      nextPageToken: token is String ? token : null,
    );
  }

  static List<Object?> _listOf(Object? value) =>
      value is List<Object?> ? value : const <Object?>[];

  Reference _at(String path) =>
      Reference.fromLocation(storage, Location(location.bucket, path));

  static String _query(Map<String, String> params) {
    if (params.isEmpty) {
      return '';
    }
    return '?${params.entries.map((MapEntry<String, String> e) => '${percentEncode(e.key)}=${percentEncode(e.value)}').join('&')}';
  }

  @override
  bool operator ==(Object other) =>
      other is Reference && other.location == location;

  @override
  int get hashCode => location.hashCode;

  /// `gs://bucket/path`, the path unescaped (like the JS SDK).
  @override
  String toString() => location.toString();
}
