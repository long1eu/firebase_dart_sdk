import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'environment_stub.dart' if (dart.library.io) 'environment_io.dart';
import 'location.dart';
import 'reference.dart';
import 'request/requester.dart';
import 'retry_policy.dart';

/// Cloud Storage for Firebase over its REST API: the entry point to the objects of one bucket.
///
/// Requests run as the signed-in user of the app: they carry the token of `app.authProvider` (for example a
/// `FirebaseUserAuth` of `package:firebase_auth_providers_dart`), so the security rules see `request.auth`, and the
/// token of `app.appCheckProvider` when the app has one. Nobody signed in means no token. A request answered
/// with 401 is sent once more with a token fetched with `forceRefresh: true`.
///
/// ```dart
/// import 'dart:convert';
///
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
/// import 'package:firebase_storage_dart/firebase_storage_dart.dart';
///
/// Future<void> main() async {
///   final FirebaseApp app = FirebaseApp.withOptions(
///     const FirebaseOptions(
///       apiKey: '<the Web API key of the project>',
///       appId: '1:1234567890:dart:example',
///       projectId: 'my-project',
///       storageBucket: 'my-project.appspot.com',
///     ),
///   );
///   final FirebaseStorage storage = FirebaseStorage(
///     app,
///     emulatorHost: FirebaseStorage.emulatorHostFromEnvironment,
///   );
///   final Reference ref = storage.ref('notes/hello.txt');
///   await ref.putString('Hello!');
///   print(utf8.decode(await ref.getBytes()));
///   storage.close();
/// }
/// ```
///
/// The configuration is fixed at construction; there is no instance cache, create one instance per bucket and
/// keep it. Network errors and retryable responses are retried as [retry] says. [close] releases the HTTP
/// client.
class FirebaseStorage {
  /// Creates an instance for a bucket of [app].
  ///
  /// * [bucket] is a bucket name (`my-bucket`) or a `gs://my-bucket` URL; by default the `storageBucket` of the
  ///   app's options. An [ArgumentError] is thrown when there is neither, or when [bucket] has an object path
  ///   (`gs://my-bucket/a`).
  /// * [emulatorHost] (`host:port`) sends the requests to the Cloud Storage emulator over plain HTTP; see
  ///   [emulatorHostFromEnvironment]. Anything else than a host and a port throws an [ArgumentError].
  /// * [mockUserToken] is sent as the user token in place of the app's auth provider, like the
  ///   `mockUserToken` string of `connectStorageEmulator` in the JS SDK. Only with [emulatorHost]; an
  ///   [ArgumentError] otherwise.
  /// * [retry] sets how long requests keep being retried.
  /// * [httpClient] sends the requests and is not closed by [close]; without it one is created and closed.
  /// * [requestTimeout] bounds the wait for the response of each attempt and each pause while a body is read;
  ///   an attempt that runs over it is retried like a network error.
  /// * [clock], [random] and [delay] are for tests.
  FirebaseStorage(
    this.app, {
    String? bucket,
    this.emulatorHost,
    String? mockUserToken,
    this.retry = const StorageRetryPolicy(),
    http.Client? httpClient,
    Duration requestTimeout = const Duration(minutes: 1),
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting double Function()? random,
    @visibleForTesting Future<void> Function(Duration duration)? delay,
  }) : host = _hostOf(emulatorHost),
       bucket = _bucketOf(
         bucket ?? app.options.storageBucket,
         _hostOf(emulatorHost),
       ) {
    if (mockUserToken != null && emulatorHost == null) {
      throw ArgumentError.value(
        mockUserToken,
        'mockUserToken',
        'Only valid with an emulatorHost',
      );
    }
    requester = Requester(
      app: app,
      client: httpClient ?? http.Client(),
      ownsClient: httpClient == null,
      requestTimeout: requestTimeout,
      mockUserToken: mockUserToken,
      clock: clock,
      random: random,
      delay: delay,
    );
  }

  /// The `host:port` of the Cloud Storage emulator from the `FIREBASE_STORAGE_EMULATOR_HOST` environment
  /// variable, or null when it is not set (always null on the web, which has no environment).
  static String? get emulatorHostFromEnvironment =>
      environmentVariable('FIREBASE_STORAGE_EMULATOR_HOST');

  /// The app whose options and tokens this instance uses.
  final FirebaseApp app;

  /// The name of the bucket, without `gs://`.
  final String bucket;

  /// The `host:port` of the emulator, or null for Google's servers.
  final String? emulatorHost;

  /// How long requests keep being retried.
  final StorageRetryPolicy retry;

  /// The host requests go to: `firebasestorage.googleapis.com`, or [emulatorHost].
  @internal
  final String host;

  /// Sends the requests of this instance; for the upload and download code of the package.
  @internal
  late final Requester requester;

  /// The scheme and host of the REST API: `https://firebasestorage.googleapis.com` or `http://<emulatorHost>`.
  @internal
  String get origin => emulatorHost == null ? 'https://$host' : 'http://$host';

  /// The reference at [path] in [bucket]; the root of the bucket by default. Leading, trailing and repeated
  /// slashes are dropped. A URL is taken as a path; use [refFromUrl] for those.
  Reference ref([String path = '']) =>
      Reference.fromLocation(this, Location(bucket, '')).child(path);

  /// The reference of a `gs://bucket/path` URL, a download URL (`https://firebasestorage.googleapis.com/v0/b/...`,
  /// or the emulator's `http://<emulatorHost>/v0/b/...`) or a Cloud Storage URL
  /// (`https://storage.googleapis.com/bucket/path`). The bucket of the URL is kept, even when it is not [bucket].
  ///
  /// The path of an HTTP URL is percent-decoded and its query (a download token) is dropped; the path of a
  /// `gs://` URL is taken as it is. Throws a `FirebaseStorageException` (`invalid-url`) for anything else, like
  /// the JS SDK.
  Reference refFromUrl(String url) =>
      Reference.fromLocation(this, Location.fromUrl(url, host));

  /// Closes the HTTP client when this instance created it. Later operations throw a [StateError], and so do
  /// those in flight when they would retry.
  void close() => requester.close();

  static String _hostOf(String? emulatorHost) {
    if (emulatorHost == null) {
      return defaultHost;
    }
    Uri? uri;
    try {
      uri = Uri.parse('http://$emulatorHost');
    } on FormatException {
      uri = null;
    }
    if (uri == null ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        emulatorHost,
        'emulatorHost',
        'Expected host:port, for example 127.0.0.1:9199',
      );
    }
    return emulatorHost;
  }

  static String _bucketOf(String? spec, String host) {
    if (spec == null || spec.isEmpty) {
      throw ArgumentError(
        'No bucket: pass one, or set storageBucket in the options of the app.',
      );
    }
    return Location.bucketOf(spec, host);
  }
}
