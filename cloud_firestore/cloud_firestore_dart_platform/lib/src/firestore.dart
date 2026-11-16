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
  /// `FirebaseFirestore.instanceFor(openDatabase:)` of `cloud_firestore_dart`.
  final fs.OpenDatabase? openDatabase;

  /// The token provider of an app; see [TokenProviderFactory].
  final TokenProviderFactory? tokenProviderFor;
}

/// A [FirebaseFirestorePlatform] backed by `cloud_firestore_dart`.
///
/// Each instance stands for one FlutterFire app and database. The
/// `cloud_firestore_dart` instance behind it ([delegate]) is created on the
/// first operation: `cloud_firestore_dart` takes the opener of the disk cache
/// when an instance is created, and whether to pass it depends on the
/// [settings] the app sets before that.
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
  static final Map<fs.FirebaseFirestore, DartFirebaseFirestore> _byDelegate =
      <fs.FirebaseFirestore, DartFirebaseFirestore>{};

  /// Whether any instance has created its `cloud_firestore_dart` instance.
  static bool get anyStarted => _byDelegate.isNotEmpty;

  /// The platform instance whose [delegate] is [firestore], if any.
  static DartFirebaseFirestore? forDelegate(fs.FirebaseFirestore firestore) =>
      _byDelegate[firestore];

  Settings _settings = const Settings();
  fs.FirebaseFirestore? _delegate;
  fs.FirebaseFirestore? _terminated;

  /// The `cloud_firestore_dart` instance, created on the first call.
  fs.FirebaseFirestore get delegate => _delegate ??= _start();

  fs.FirebaseFirestore _start() {
    final fs.FirebaseFirestore firestore = fs.FirebaseFirestore.instanceFor(
      app: dartAppFor(app, config.tokenProviderFor),
      databaseId: databaseId,
      openDatabase: _settings.persistenceEnabled == false
          ? null
          : config.openDatabase,
    );
    final fs.Settings settings = dartSettingsOf(_settings);
    if (firestore.settings != settings) {
      // Throws failed-precondition when another package started this
      // instance already with other settings.
      guardSync(() => firestore.settings = settings);
    }
    _byDelegate[firestore] = this;
    return firestore;
  }

  /// The `cloud_firestore_dart` settings for the FlutterFire [settings].
  ///
  /// `host` may carry a port (`'127.0.0.1:8080'`, as `useFirestoreEmulator`
  /// of `cloud_firestore` sets it); `cloud_firestore_dart` keeps the port
  /// apart. The disk cache is used when an `openDatabase` function was
  /// configured and `persistenceEnabled` is not false. The web-only settings
  /// are ignored.
  @visibleForTesting
  static fs.Settings dartSettingsOf(Settings settings) {
    String host = fs.Settings.defaultHost;
    int port = fs.Settings.defaultPort;
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
    return fs.Settings(
      host: host,
      port: port,
      sslEnabled: settings.sslEnabled ?? true,
      persistenceEnabled: settings.persistenceEnabled ?? true,
      // Both use -1 for an unlimited cache.
      cacheSizeBytes: cacheSizeBytes ?? fs.Settings.defaultCacheSizeBytes,
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
      guardStream(lazyStream(() => delegate.snapshotsInSync()));

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
    return guard(
      () async => querySnapshotOf(
        this,
        await delegate.namedQueryGet(name, options: getOptionsOf(options)),
        behavior: options.serverTimestampBehavior,
      ),
    );
  }

  /// Runs [transactionHandler] in a `cloud_firestore_dart` transaction.
  ///
  /// When [timeout] passes first, the returned future fails with a
  /// `deadline-exceeded` [FirebaseException] and no new attempt starts; an
  /// attempt that is committing is not cancelled and may still take effect.
  @override
  Future<T?> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    return guard(() async {
      T? result;
      await delegate.runTransaction<void>(
        (fs.Transaction transaction) async {
          result = await transactionHandler(DartTransaction(this, transaction));
        },
        timeout: timeout,
        maxAttempts: maxAttempts,
      );
      return result;
    });
  }

  @override
  Settings get settings => _settings;

  /// Sets the settings of the `cloud_firestore_dart` instance. Throws a
  /// `failed-precondition` [FirebaseException] when it has started already
  /// (after the first operation) and [settings] differ.
  @override
  set settings(Settings settings) {
    if (settings == _settings) {
      return;
    }
    final fs.FirebaseFirestore? running = _delegate;
    if (running != null) {
      guardSync(() => running.settings = dartSettingsOf(settings));
    }
    _settings = settings;
  }

  /// Terminates the `cloud_firestore_dart` instance. The next operation
  /// starts a new one, with the [settings] set by then; [clearPersistence]
  /// clears the cache of the terminated one until then.
  @override
  Future<void> terminate() {
    final fs.FirebaseFirestore? running = _delegate;
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
    return guard(
      // ignore: deprecated_member_use
      () => delegate.setIndexConfigurationFromJSON(indexConfiguration),
    );
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
    fs.FirebaseFirestore.setLoggingEnabled(enabled);
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
