import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'environment_stub.dart' if (dart.library.io) 'environment_io.dart';
import 'location.dart';
import 'reference.dart';
import 'request/requester.dart';
import 'retry_policy.dart';
import 'upload/upload_slots.dart';

/// Cloud Storage for Firebase over its REST API: the entry point to the objects of one bucket.
///
/// Requests run as the signed-in user of the app: they carry the token of `app.authProvider` (for example a
/// `FirebaseUserAuth` of `package:firebase_auth_providers_dart`), so the security rules see `request.auth`, and the
/// token of `app.appCheckProvider` when the app has one. Nobody signed in means no token. A request answered
/// with 401 is sent once more with a token fetched with `forceRefresh: true`. Tokens are only sent over HTTPS,
/// to the [emulatorHost], or to a loopback host; never in clear text to anybody else.
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
///   final FirebaseStorage storage = FirebaseStorage(app);
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
  ///   [emulatorHostFromEnvironment]. Anything else than a host and a port throws an [ArgumentError]. The
  ///   tokens of the app are sent to it in clear text: set it only for an emulator you run.
  /// * [mockUserToken] is sent as the user token in place of the app's auth provider, like the
  ///   `mockUserToken` string of `connectStorageEmulator` in the JS SDK. Only with [emulatorHost]; an
  ///   [ArgumentError] otherwise.
  /// * [retry] sets how long requests keep being retried.
  /// * [httpClient] sends the requests and is not closed by [close]; without it one is created and closed.
  /// * [requestTimeout] is an idle timeout: an attempt is retried like a network error when no byte of its
  ///   request body is sent for that long, when no response arrives that long after the body was sent, or
  ///   when a response body pauses that long. A long upload or download never times out while bytes flow. On
  ///   the web it bounds the time from the start of a request to its response.
  /// * [maxConcurrentUploads] is how many uploads of this instance run at once (`putBytes`, `putString` and
  ///   upload tasks); the others wait in a first-in, first-out queue. At least 1, else an [ArgumentError].
  /// * [maxUploadChunkSize] caps the size of the requests of a resumable upload. Null (the default) sends the
  ///   rest of an upload of bytes or of a file in one request on the VM, and chunks of up to 16 MiB on the web
  ///   and for streams. A value is rounded down to a multiple of 256 KiB, with 256 KiB as the minimum; zero
  ///   or less is an [ArgumentError].
  /// * [clock], [random] and [delay] are for tests.
  FirebaseStorage(
    this.app, {
    String? bucket,
    this.emulatorHost,
    String? mockUserToken,
    this.retry = const StorageRetryPolicy(),
    http.Client? httpClient,
    Duration requestTimeout = const Duration(minutes: 1),
    this.maxConcurrentUploads = 4,
    int? maxUploadChunkSize,
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting double Function()? random,
    @visibleForTesting Future<void> Function(Duration duration)? delay,
  }) : host = _hostOf(emulatorHost),
       bucket = _bucketOf(
         bucket ?? app.options.storageBucket,
         _hostOf(emulatorHost),
       ),
       maxUploadChunkSize = _chunkSizeOf(maxUploadChunkSize),
       uploadSlots = UploadSlots(_checkConcurrency(maxConcurrentUploads)) {
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
      emulatorHost: emulatorHost,
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

  /// How many uploads run at once; the others wait their turn.
  final int maxConcurrentUploads;

  /// The largest request of a resumable upload, a multiple of 256 KiB; null for one request on the VM (see
  /// the constructor).
  final int? maxUploadChunkSize;

  /// The queue that [maxConcurrentUploads] sets.
  @internal
  final UploadSlots uploadSlots;

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

  static int _checkConcurrency(int value) {
    if (value < 1) {
      throw ArgumentError.value(value, 'maxConcurrentUploads', 'At least 1');
    }
    return value;
  }

  static int? _chunkSizeOf(int? value) {
    if (value == null) {
      return null;
    }
    if (value <= 0) {
      throw ArgumentError.value(
        value,
        'maxUploadChunkSize',
        'Must be positive',
      );
    }
    const int unit = 256 * 1024;
    return value < unit ? unit : value - value % unit;
  }

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
