import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'app.dart';
import 'collection_reference.dart';
import 'document_reference.dart';
import 'errors.dart';
import 'load_bundle_task.dart';
import 'persistent_cache_index_manager.dart';
import 'query.dart';
import 'snapshots.dart';
import 'transaction.dart';
import 'write_batch.dart';

/// How the instances of [DartFirebaseFirestore] are created. Set by
/// `CloudFirestoreDart.use`.
class DartFirestoreConfig {
  /// The configuration: [openDatabase] for the disk cache (memory cache when
  /// null) and [tokenProviderFor] for the signed-in user.
  const DartFirestoreConfig({this.openDatabase, this.tokenProviderFor});

  /// Opens the SQLite database of the offline cache; see
  /// `Firestore.instanceFor(openDatabase:)` of `cloud_firestore_dart`.
  final fs.OpenDatabase? openDatabase;

  /// The token provider of an app; see [TokenProviderFactory].
  final TokenProviderFactory? tokenProviderFor;
}

/// A [FirebaseFirestorePlatform] backed by `cloud_firestore_dart`.
///
/// Each instance stands for one FlutterFire app and database. The
/// `cloud_firestore_dart` instance behind it ([delegate]) is created on the
/// first operation, with the [settings] set until then, as the native SDKs do.
class DartFirebaseFirestore extends FirebaseFirestorePlatform {
  /// The instance for [app] and [databaseId]. Without [app] it is the factory
  /// that `FirebaseFirestorePlatform.instance` holds: `cloud_firestore` asks it
  /// for the instance of each app through [delegateFor].
  DartFirebaseFirestore({FirebaseApp? app, String databaseId = '(default)'})
    : super(appInstance: app, databaseChoice: databaseId);

  /// The configuration read when an instance starts.
  static DartFirestoreConfig config = const DartFirestoreConfig();

  static final Map<String, DartFirebaseFirestore> _instances =
      <String, DartFirebaseFirestore>{};
  static final Map<fs.Firestore, DartFirebaseFirestore> _byDelegate =
      <fs.Firestore, DartFirebaseFirestore>{};

  /// Whether any instance has created its `cloud_firestore_dart` instance.
  static bool get anyStarted => _byDelegate.isNotEmpty;

  /// The platform instance whose [delegate] is [firestore], if any.
  static DartFirebaseFirestore? forDelegate(fs.Firestore firestore) =>
      _byDelegate[firestore];

  Settings _settings = const Settings();
  fs.Firestore? _delegate;
  fs.Firestore? _terminated;

  /// The `cloud_firestore_dart` instance, created on the first call.
  fs.Firestore get delegate => _delegate ??= _start();

  fs.Firestore _start() {
    final fs.Firestore firestore = fs.Firestore.instanceFor(
      app: dartAppFor(app, config.tokenProviderFor),
      database: databaseId,
      settings: dartSettingsOf(_settings),
      openDatabase: _settings.persistenceEnabled == false
          ? null
          : config.openDatabase,
    );
    _byDelegate[firestore] = this;
    return firestore;
  }

  /// The `cloud_firestore_dart` settings for the FlutterFire [settings].
  ///
  /// `host` may carry a port (`'127.0.0.1:8080'`, as `useFirestoreEmulator`
  /// sets it). `persistenceEnabled` is left to the instance: the disk cache is
  /// used when an `openDatabase` function was configured. The web-only
  /// settings are ignored.
  @visibleForTesting
  static fs.FirestoreSettings dartSettingsOf(Settings settings) {
    String host = fs.FirestoreSettings.defaultHost;
    int port = fs.FirestoreSettings.defaultPort;
    final String? hostAndPort = settings.host;
    if (hostAndPort != null && hostAndPort.isNotEmpty) {
      final int colon = hostAndPort.lastIndexOf(':');
      final int? parsed = colon > 0
          ? int.tryParse(hostAndPort.substring(colon + 1))
          : null;
      if (parsed != null && !hostAndPort.endsWith(']')) {
        host = hostAndPort.substring(0, colon);
        port = parsed;
      } else {
        host = hostAndPort;
      }
    }
    final int? cacheSizeBytes = settings.cacheSizeBytes;
    return fs.FirestoreSettings(
      host: host,
      port: port,
      sslEnabled: settings.sslEnabled ?? true,
      cacheSizeBytes: cacheSizeBytes == null
          ? fs.FirestoreSettings.defaultCacheSizeBytes
          : cacheSizeBytes == Settings.CACHE_SIZE_UNLIMITED
          ? fs.FirestoreSettings.cacheSizeUnlimited
          : cacheSizeBytes,
    );
  }

  /// Runs [create] when the returned broadcast stream gets its first listener,
  /// and cancels the subscription when the last listener leaves, like the
  /// method channel implementation.
  Stream<T> lazyStream<T>(Stream<T> Function() create) {
    late final StreamController<T> controller;
    StreamSubscription<T>? subscription;
    controller = StreamController<T>.broadcast(
      onListen: () {
        try {
          subscription = create().listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
        } catch (error, stackTrace) {
          controller.addError(convertError(error, stackTrace), stackTrace);
        }
      },
      onCancel: () {
        subscription?.cancel();
        subscription = null;
      },
    );
    return controller.stream;
  }

  @override
  FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) {
    return _instances.putIfAbsent(
      '${app.name}|$databaseId',
      () => DartFirebaseFirestore(app: app, databaseId: databaseId),
    );
  }

  @override
  void useEmulator(String host, int port) {
    settings = settings.copyWith(host: '$host:$port', sslEnabled: false);
  }

  @override
  WriteBatchPlatform batch() => guardSync(() => DartWriteBatch(this));

  @override
  Future<void> clearPersistence() {
    return guard(
      () => (_delegate ?? _terminated ?? delegate).clearPersistence(),
    );
  }

  @override
  CollectionReferencePlatform collection(String collectionPath) =>
      DartCollectionReference(this, collectionPath);

  @override
  QueryPlatform collectionGroup(String collectionPath) =>
      DartQuery(this, collectionPath, isCollectionGroupQuery: true);

  @override
  Future<void> disableNetwork() => guard(() => delegate.disableNetwork());

  @override
  DocumentReferencePlatform doc(String documentPath) =>
      DartDocumentReference(this, documentPath);

  @override
  Future<void> enableNetwork() => guard(() => delegate.enableNetwork());

  @override
  Stream<void> snapshotsInSync() =>
      guardStream(lazyStream(() => delegate.snapshotsInSync));

  @override
  LoadBundleTaskPlatform<LoadBundleTaskSnapshotPlatform> loadBundle(
    Uint8List bundle,
  ) {
    return DartLoadBundleTask(guardSync(() => delegate.loadBundle(bundle)));
  }

  @override
  Future<QuerySnapshotPlatform> namedQueryGet(
    String name, {
    GetOptions options = const GetOptions(),
  }) {
    return guard(() async {
      final fs.Query<Map<String, Object?>>? query = await delegate
          .getNamedQuery(name);
      if (query == null) {
        throw FirebaseException(
          plugin: firestorePlugin,
          code: 'not-found',
          message:
              'Named query "$name" has not been found. Please check it has '
              'been loaded properly via loadBundle().',
        );
      }
      return querySnapshotOf(
        this,
        await query.get(sourceOf(options.source)),
        behavior: options.serverTimestampBehavior,
      );
    });
  }

  /// Runs [transactionHandler] in a `cloud_firestore_dart` transaction with
  /// [maxAttempts] attempts.
  ///
  /// When [timeout] passes first, the returned future fails with a
  /// `deadline-exceeded` [FirebaseException]; the attempt that is running is
  /// not cancelled and may still commit.
  @override
  Future<T?> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    return guard(() async {
      T? result;
      await delegate
          .runTransaction<void>((fs.Transaction transaction) async {
            result = await transactionHandler(
              DartTransaction(this, transaction),
            );
          }, options: fs.TransactionOptions(maxAttempts: maxAttempts))
          .timeout(
            timeout,
            onTimeout: () => throw FirebaseException(
              plugin: firestorePlugin,
              code: 'deadline-exceeded',
              message: 'The transaction did not finish within $timeout.',
            ),
          );
      return result;
    });
  }

  @override
  Settings get settings => _settings;

  /// Sets the settings used when the `cloud_firestore_dart` instance is
  /// created. Throws a `failed-precondition` [FirebaseException] when it was
  /// created already (after the first operation) and [settings] differ.
  @override
  set settings(Settings settings) {
    if (_delegate != null && settings != _settings) {
      throw FirebaseException(
        plugin: firestorePlugin,
        code: 'failed-precondition',
        message:
            'Firestore has already been started and its settings can no '
            'longer be changed. Set the settings before any other call.',
      );
    }
    _settings = settings;
  }

  /// Terminates the `cloud_firestore_dart` instance. The next operation
  /// starts a new one, with the [settings] set by then; [clearPersistence]
  /// clears the cache of the terminated one until then.
  @override
  Future<void> terminate() {
    final fs.Firestore? running = _delegate;
    if (running == null) {
      return Future<void>.value();
    }
    _delegate = null;
    _terminated = running;
    _byDelegate.remove(running);
    return guard(running.terminate);
  }

  @override
  Future<void> waitForPendingWrites() =>
      guard(() => delegate.waitForPendingWrites());

  @override
  // ignore: deprecated_member_use
  Future<void> setIndexConfiguration(String indexConfiguration) {
    // ignore: deprecated_member_use
    return guard(() => delegate.setIndexConfiguration(indexConfiguration));
  }

  @override
  PersistentCacheIndexManagerPlatform? persistentCacheIndexManager() {
    final fs.PersistentCacheIndexManager? manager = guardSync(
      () => delegate.persistentCacheIndexManager,
    );
    return manager == null ? null : DartPersistentCacheIndexManager(manager);
  }

  @override
  Future<void> setLoggingEnabled(bool enabled) async {
    fs.Firestore.setLoggingEnabled(loggingEnabled: enabled);
  }

  @override
  PipelinePlatform pipeline(List<Map<String, dynamic>> initialStages) {
    throw UnimplementedError(
      'Pipelines are not implemented by cloud_firestore_dart_platform. Use '
      'package:cloud_firestore_dart/pipelines.dart directly.',
    );
  }

  @override
  Future<PipelineSnapshotPlatform> executePipeline(
    List<Map<String, dynamic>> stages, {
    Map<String, dynamic>? options,
  }) {
    throw UnimplementedError(
      'Pipelines are not implemented by cloud_firestore_dart_platform. Use '
      'package:cloud_firestore_dart/pipelines.dart directly.',
    );
  }
}
