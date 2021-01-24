// File created by
// Lung Razvan <long1eu>
// on 16/01/2021

import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/garbage_collection_scheduler.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/datastore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/async_task.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/database.dart';
import 'package:rxdart/rxdart.dart';

// ignore_for_file: close_sinks

/// Initializes and wires up all core components for Firestore.
///
/// Implementations provide custom components by overriding the `createX()` methods.
abstract class ComponentProvider {
  Persistence _persistence;
  LocalStore _localStore;
  SyncEngine _syncEngine;
  RemoteStore _remoteStore;
  EventManager _eventManager;
  BehaviorSubject<bool> _onNetworkConnected;
  GarbageCollectionScheduler _gargabeCollectionScheduler;

  Persistence get persistence => _persistence;

  LocalStore get localStore => _localStore;

  SyncEngine get syncEngine => _syncEngine;

  RemoteStore get remoteStore => _remoteStore;

  EventManager get eventManager => _eventManager;

  BehaviorSubject<bool> get onNetworkConnected => _onNetworkConnected;

  GarbageCollectionScheduler get gargabeCollectionScheduler => _gargabeCollectionScheduler;

  Future<void> initialize(ComponentProviderConfiguration configuration) async {
    _persistence = await createPersistence(configuration);
    await persistence.start();
    _localStore = createLocalStore(configuration);
    _onNetworkConnected = configuration.onNetworkConnected;
    _remoteStore = createRemoteStore(configuration);
    _syncEngine = createSyncEngine(configuration);
    _eventManager = createEventManager(configuration);
    await localStore.start();
    await remoteStore.start();
    _gargabeCollectionScheduler = createGarbageCollectionScheduler(configuration);
  }

  GarbageCollectionScheduler createGarbageCollectionScheduler(ComponentProviderConfiguration configuration);

  EventManager createEventManager(ComponentProviderConfiguration configuration);

  LocalStore createLocalStore(ComponentProviderConfiguration configuration);

  Future<Persistence> createPersistence(ComponentProviderConfiguration configuration);

  RemoteStore createRemoteStore(ComponentProviderConfiguration configuration);

  SyncEngine createSyncEngine(ComponentProviderConfiguration configuration);
}

class ComponentProviderConfiguration {
  ComponentProviderConfiguration({
    this.asyncQueue,
    this.databaseInfo,
    this.datastore,
    this.initialUser,
    this.maxConcurrentLimboResolutions,
    this.settings,
    this.onNetworkConnected,
    this.openDatabase,
  });

  final AsyncQueue asyncQueue;
  final DatabaseInfo databaseInfo;
  final Datastore datastore;
  final User initialUser;
  final int maxConcurrentLimboResolutions;
  final FirestoreSettings settings;
  final BehaviorSubject<bool> onNetworkConnected;
  final OpenDatabase openDatabase;
}
