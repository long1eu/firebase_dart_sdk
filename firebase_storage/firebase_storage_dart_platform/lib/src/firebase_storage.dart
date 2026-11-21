import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart' as fs;
import 'package:firebase_storage_platform_interface/firebase_storage_platform_interface.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'reference.dart';

/// What `FirebaseStorageDart.use` configures; read when an instance creates
/// its client.
class DartStorageConfig {
  const DartStorageConfig({this.tokenProviderFor, this.httpClient});

  final TokenProviderFactory? tokenProviderFor;
  final http.Client? httpClient;
}

/// The implementation of [FirebaseStoragePlatform] on top of
/// `firebase_storage_dart`: one instance per FlutterFire app and bucket.
///
/// The instance registered as [FirebaseStoragePlatform.instance] has no app;
/// the official `firebase_storage` asks it for the instance of each app and
/// bucket ([delegateFor]).
///
/// The client of `firebase_storage_dart` is immutable, so the setters
/// (`useStorageEmulator`, `setMax*RetryTime`) make the next operation use a
/// new client with the new configuration. Operations and tasks already started
/// keep the client they started with. All clients share one `http.Client`.
class DartFirebaseStorage extends FirebaseStoragePlatform {
  /// The instance without an app, for [FirebaseStoragePlatform.instance].
  DartFirebaseStorage() : super(bucket: '');

  DartFirebaseStorage._(FirebaseApp app, String bucket)
    : _emulator = fs.FirebaseStorage.emulatorHostFromEnvironment,
      super(appInstance: app, bucket: bucket);

  /// The configuration of the clients created from now on.
  static DartStorageConfig config = const DartStorageConfig();

  static final Map<String, DartFirebaseStorage> _instances =
      <String, DartFirebaseStorage>{};

  static http.Client? _sharedHttpClient;

  /// Whether an instance has created its client, after which [config] no
  /// longer changes anything for it.
  static bool get anyStarted =>
      _instances.values.any((DartFirebaseStorage it) => it._client != null);

  /// The instance of [app] and [bucket] (a name, without `gs://`), created on
  /// first use.
  static DartFirebaseStorage forApp(FirebaseApp app, String bucket) =>
      _instances.putIfAbsent(
        '${app.name}|$bucket',
        () => DartFirebaseStorage._(app, bucket),
      );

  static const Duration _defaultOperationRetry = Duration(minutes: 2);
  static const Duration _defaultTransferRetry = Duration(minutes: 10);

  Duration _operationRetry = _defaultOperationRetry;
  Duration _uploadRetry = _defaultTransferRetry;
  Duration _downloadRetry = _defaultTransferRetry;

  /// The `host:port` of the emulator, or null for Google's servers.
  String? _emulator;

  fs.FirebaseStorage? _client;

  /// The client of this instance's app and bucket with the current settings,
  /// created on first use.
  fs.FirebaseStorage get client {
    if (appInstance == null) {
      throw StateError(
        'This is the registered instance of firebase_storage_dart_platform, '
        'which has no app: use FirebaseStorage.instanceFor(app: ...).',
      );
    }
    return _client ??= fs.FirebaseStorage(
      dartAppFor(app, config.tokenProviderFor),
      bucket: bucket,
      emulatorHost: _emulator,
      retry: fs.StorageRetryPolicy(
        operation: _operationRetry,
        upload: _uploadRetry,
        download: _downloadRetry,
      ),
      httpClient: config.httpClient ?? (_sharedHttpClient ??= http.Client()),
    );
  }

  /// The `firebase_app_dart` app behind the client, for its token providers.
  dart_app.FirebaseApp get dartApp => client.app;

  /// Makes the next operation create a new client. The old one is not closed:
  /// it does not own the HTTP client, and tasks may still be using it.
  void _reconfigure() => _client = null;

  @override
  FirebaseStoragePlatform delegateFor({
    required FirebaseApp app,
    required String bucket,
  }) => forApp(app, bucket);

  @override
  int get maxOperationRetryTime => _operationRetry.inMilliseconds;

  @override
  int get maxUploadRetryTime => _uploadRetry.inMilliseconds;

  @override
  int get maxDownloadRetryTime => _downloadRetry.inMilliseconds;

  @override
  void setMaxOperationRetryTime(int time) {
    _operationRetry = Duration(milliseconds: time);
    _reconfigure();
  }

  @override
  void setMaxUploadRetryTime(int time) {
    _uploadRetry = Duration(milliseconds: time);
    _reconfigure();
  }

  @override
  void setMaxDownloadRetryTime(int time) {
    _downloadRetry = Duration(milliseconds: time);
    _reconfigure();
  }

  /// Sends the requests of this instance to the emulator at [host] and
  /// [port], over plain HTTP. Unlike Android and iOS, it may be called at any
  /// time; operations started before keep their target.
  @override
  Future<void> useStorageEmulator(String host, int port) async {
    emulatorHost = host;
    emulatorPort = port;
    _emulator = host.contains(':') && !host.startsWith('[')
        ? '[$host]:$port'
        : '$host:$port';
    _reconfigure();
  }

  @override
  ReferencePlatform ref(String path) => DartReference(this, path);
}
