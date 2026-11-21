import 'package:meta/meta.dart';

/// How long an operation keeps retrying after network errors and retryable responses (HTTP 5xx, 408 and 429).
///
/// Each request is retried with exponential backoff (2, 4, 8, ... up to 64 seconds between attempts, plus up to a
/// second of jitter, like the JS SDK) until it succeeds, fails with an error that is not retryable, or runs out
/// of its time. When the time is up while waiting between attempts, one last attempt is made right away; when it
/// fails too, the operation throws `retry-limit-exceeded`. An attempt in flight is never cut short by this time
/// (see the `requestTimeout` of `FirebaseStorage` for that).
///
/// ```dart
/// final FirebaseStorage storage = FirebaseStorage(
///   app,
///   retry: const StorageRetryPolicy(operation: Duration(seconds: 30)),
/// );
/// ```
@immutable
class StorageRetryPolicy {
  /// Creates a policy; the defaults are those of the JS SDK and FlutterFire.
  ///
  /// A zero (or negative) duration means a single attempt.
  const StorageRetryPolicy({
    this.operation = const Duration(minutes: 2),
    this.upload = const Duration(minutes: 10),
    this.download = const Duration(minutes: 10),
  });

  /// The retry time of the operations without a payload: metadata, download URL, delete and list.
  final Duration operation;

  /// The retry time of each request of an upload.
  final Duration upload;

  /// The retry time of a download (`getBytes`). The JS SDK uses the operation time here; FlutterFire has a
  /// separate download time.
  final Duration download;

  @override
  bool operator ==(Object other) =>
      other is StorageRetryPolicy &&
      other.operation == operation &&
      other.upload == upload &&
      other.download == download;

  @override
  int get hashCode => Object.hash(operation, upload, download);

  @override
  String toString() =>
      'StorageRetryPolicy(operation: $operation, upload: $upload, download: $download)';
}
