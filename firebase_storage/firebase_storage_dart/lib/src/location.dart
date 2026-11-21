import 'package:meta/meta.dart';

import 'errors.dart';

/// The host of the Firebase Storage REST API.
const String defaultHost = 'firebasestorage.googleapis.com';

/// A bucket and the path of an object in it (empty for the root of the bucket), as `Location` of the JS SDK
/// (`implementation/location.ts`).
@immutable
@internal
final class Location {
  /// Creates the location of [path] in [bucket]. [path] has no leading or trailing slash.
  const Location(this.bucket, this.path);

  /// Parses a `gs://`, Firebase Storage REST (`https://<host>/v0/b/<bucket>/o/<path>`) or Cloud Storage
  /// (`https://storage.googleapis.com/<bucket>/<path>`) URL, where `<host>` is [host] (the production host or
  /// the `host:port` of the emulator), like `Location.makeFromUrl` of the JS SDK.
  ///
  /// The path of a `gs://` URL is taken as it is (one trailing slash removed); the path of an HTTP URL is
  /// percent-decoded, and its query and fragment are ignored. Throws a `FirebaseStorageException`
  /// (`invalid-url`) when [url] is none of these, or has a malformed percent-encoding.
  factory Location.fromUrl(String url, String host) {
    final RegExpMatch? gs = _gsRegExp.firstMatch(url);
    if (gs != null) {
      String path = gs.group(3) ?? '';
      if (path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      return Location(gs.group(1)!, path);
    }
    for (final RegExp regExp in <RegExp>[
      _firebaseRegExp(host),
      _cloudStorageRegExp(host),
    ]) {
      final RegExpMatch? match = regExp.firstMatch(url);
      if (match != null) {
        return Location(match.group(1)!, _decode(match.group(2) ?? '', url));
      }
    }
    throw invalidUrl(url);
  }

  /// The bucket of a bucket specification: a bare bucket name (`my-bucket`) or a URL without a path
  /// (`gs://my-bucket`, `gs://my-bucket/`), like `Location.makeFromBucketSpec` of the JS SDK.
  ///
  /// Throws an [ArgumentError] when [spec] is a URL with an object path, or is empty.
  static String bucketOf(String spec, String host) {
    Location location;
    try {
      location = Location.fromUrl(spec, host);
    } on Object {
      location = Location(spec, '');
    }
    if (location.path.isNotEmpty || location.bucket.isEmpty) {
      throw ArgumentError.value(
        spec,
        'bucket',
        'Expected a bucket name or a gs:// URL without a path',
      );
    }
    return location.bucket;
  }

  /// The name of the bucket.
  final String bucket;

  /// The path of the object, empty for the root of the bucket.
  final String path;

  /// Whether this is the root of the bucket.
  bool get isRoot => path.isEmpty;

  /// The part of the REST URL after `/v0` that names the bucket's objects: `/b/<bucket>/o`.
  String get bucketOnlyUrlPart => '/b/${percentEncode(bucket)}/o';

  /// The part of the REST URL after `/v0` that names the object: `/b/<bucket>/o/<path>`, where the whole path
  /// is one percent-encoded component (`a/b` is `a%2Fb`).
  String get fullUrlPart => '$bucketOnlyUrlPart/${percentEncode(path)}';

  @override
  bool operator ==(Object other) =>
      other is Location && other.bucket == bucket && other.path == path;

  @override
  int get hashCode => Object.hash(bucket, path);

  @override
  String toString() => 'gs://$bucket/$path';

  static const String _bucketDomain = r'([A-Za-z0-9.\-_]+)';

  static final RegExp _gsRegExp = RegExp(
    '^gs://$_bucketDomain(/(.*))?\$',
    caseSensitive: false,
  );

  static RegExp _firebaseRegExp(String host) => RegExp(
    '^https?://${RegExp.escape(host)}/v[A-Za-z0-9_]+/b/$_bucketDomain'
    r'/o(?:/([^?#]*).*)?$',
    caseSensitive: false,
  );

  static RegExp _cloudStorageRegExp(String host) {
    final String hosts = host == defaultHost
        ? r'(?:storage\.googleapis\.com|storage\.cloud\.google\.com)'
        : RegExp.escape(host);
    return RegExp(
      '^https?://$hosts/$_bucketDomain/([^?#]*)',
      caseSensitive: false,
    );
  }

  static String _decode(String path, String url) {
    try {
      return Uri.decodeComponent(path);
    } on ArgumentError {
      throw invalidUrl(url);
    } on FormatException {
      throw invalidUrl(url);
    }
  }
}

/// [value] percent-encoded like `encodeURIComponent` of JavaScript: everything but `A-Z a-z 0-9 - _ . ! ~ * ' ( )`
/// is escaped as UTF-8.
@internal
String percentEncode(String value) => Uri.encodeComponent(value);

/// The parent of [path]: null for the root (an empty path), `''` for a top-level path.
@internal
String? parentPath(String path) {
  if (path.isEmpty) {
    return null;
  }
  final int index = path.lastIndexOf('/');
  return index == -1 ? '' : path.substring(0, index);
}

/// [childPath] appended to [path], with the empty components of [childPath] (repeated, leading and trailing
/// slashes) dropped.
@internal
String joinPath(String path, String childPath) {
  final String canonical = childPath
      .split('/')
      .where((String component) => component.isNotEmpty)
      .join('/');
  if (path.isEmpty) {
    return canonical;
  }
  return canonical.isEmpty ? path : '$path/$canonical';
}

/// The last component of [path], ignoring one trailing slash; the whole path when it has no slash.
@internal
String lastComponent(String path) {
  final int index = path.length < 2
      ? -1
      : path.lastIndexOf('/', path.length - 2);
  return index == -1 ? path : path.substring(index + 1);
}
