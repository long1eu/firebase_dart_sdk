library cloud_firestore_dart;

import 'dart:async';

import 'package:cloud_firestore_dart/src/index.dart';
import 'package:cloud_firestore_dart/src/util/database.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as platform;
import 'package:cloud_firestore_vm/cloud_firestore_vm.dart' as dart;
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/firebase_auth_credentials_provider.dart'
    as dart;
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite/sqlite_persistence.dart'
    as dart;
import 'package:firebase_core/firebase_core.dart' as platform;
import 'package:firebase_core_vm/firebase_core_vm.dart' as dart;
import 'package:meta/meta.dart';

// ignore_for_file: implementation_imports
class FirestoreDart extends platform.FirestorePlatform {
  FirestoreDart._({
    @required platform.FirebaseApp app,
    @required dart.Firestore firestore,
  })  : assert(firestore != null),
        _dartFirestore = firestore,
        super(app: app) {
    platform.FieldValueFactoryPlatform.instance = FieldValueFactoryDart();
  }

  static final Map<String, dart.Firestore> _instances =
      <String, dart.Firestore>{};

  dart.Firestore _dartFirestore;

  /// Registers this implementation as default implementation for Firestore
  static Future<void> register({
    dart.FirebaseApp app,
    dart.OpenDatabase openDatabase,
    bool persistenceEnabled,
    String host,
    bool sslEnabled,
    int cacheSizeBytes,
  }) async {
    app ??= dart.FirebaseApp.instance;
    final dart.Firestore firestore = await initialize(
      app: app,
      openDatabase: openDatabase,
      persistenceEnabled: persistenceEnabled,
      host: host,
      sslEnabled: sslEnabled,
      cacheSizeBytes: cacheSizeBytes,
    );

    final platform.FirebaseApp platformApp =
        await platform.FirebaseApp.appNamed(app.name);
    platform.FirestorePlatform.instance =
        FirestoreDart._(app: platformApp, firestore: firestore);
  }

  /// Registers this implementation as default implementation for Firestore
  static Future<dart.Firestore> initialize({
    dart.FirebaseApp app,
    dart.OpenDatabase openDatabase,
    bool persistenceEnabled,
    String host,
    bool sslEnabled,
    int cacheSizeBytes,
  }) async {
    app ??= dart.FirebaseApp.instance;

    if (!_instances.containsKey(app.name)) {
      _instances[app.name] = await dart.Firestore.getInstance(
        app,
        openDatabase: openDatabase ??= Database.create,
        settings: dart.FirestoreSettings().copyWith(
          host: host,
          sslEnabled: sslEnabled,
          persistenceEnabled: persistenceEnabled,
          cacheSizeBytes: cacheSizeBytes,
        ),
      );
    }
    return _instances[app.name];
  }

  @override
  FirestoreDart withApp(platform.FirebaseApp app) {
    final dart.Firestore firestore = _instances[app.name];
    if (firestore == null) {
      throw StateError(
          'The Firestore instance for ${app.name} was not initialized yet. Call [FirestoreDart.initialize] first, or register this instance as the default implementation using [FirestoreDart.register].');
    }

    return FirestoreDart._(app: app, firestore: firestore);
  }

  @override
  platform.CollectionReferencePlatform collection(String path) {
    return CollectionReferenceDart(this, _dartFirestore, path.split('/'));
  }

  @override
  platform.QueryPlatform collectionGroup(String path) {
    return QueryDart(this, path, _dartFirestore.collectionGroup(path),
        isCollectionGroup: true);
  }

  @override
  platform.DocumentReferencePlatform document(String path) =>
      DocumentReferenceDart(_dartFirestore, this, path.split('/'));

  @override
  platform.WriteBatchPlatform batch() => WriteBatchDart(_dartFirestore.batch());

  @override
  Future<void> settings({
    bool persistenceEnabled,
    String host,
    bool sslEnabled,
    int cacheSizeBytes,
  }) async {
    await _dartFirestore.shutdown();

    dart.InternalTokenProvider authProvider;
    if (_dartFirestore.client.credentialsProvider
        is dart.FirebaseAuthCredentialsProvider) {
      final dart.FirebaseAuthCredentialsProvider provider =
          _dartFirestore.client.credentialsProvider;
      authProvider = provider.authProvider;
    }

    dart.OpenDatabase openDatabase;
    if (_dartFirestore.client.persistence is dart.SQLitePersistence) {
      final dart.SQLitePersistence persistence =
          _dartFirestore.client.persistence;
      openDatabase = persistence.openDatabase;
    }

    _dartFirestore = await dart.Firestore.newInstance(
      _dartFirestore.firebaseApp,
      _dartFirestore.databaseId.databaseId,
      authProvider: authProvider,
      openDatabase: openDatabase,
      settings: dart.FirestoreSettings().copyWith(
        host: host,
        sslEnabled: sslEnabled,
        cacheSizeBytes: cacheSizeBytes ?? 40000000,
        persistenceEnabled: persistenceEnabled ?? true,
      ),
    );
  }

  @override
  Future<Map<String, dynamic>> runTransaction(
    platform.TransactionHandler transactionHandler, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    Map<String, dynamic> result;
    await _dartFirestore.runTransaction((dart.Transaction transaction) async {
      result = await transactionHandler(TransactionDart(transaction, this));
    }).timeout(timeout);
    return result is Map<String, dynamic> ? result : <String, dynamic>{};
  }
}
