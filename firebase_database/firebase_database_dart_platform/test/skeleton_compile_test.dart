// Every public symbol of the package, with its signature pinned by a typed
// tear-off or closure: a signature that changes breaks analysis here before it
// breaks another builder's file. Nothing is called, so it passes while the
// bodies throw. Owner: builder A (see lib/src/OWNERS.md); update it with any
// signature change.

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    show FirebasePlatform;
import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:firebase_database_dart_platform/src/app.dart';
import 'package:firebase_database_dart_platform/src/core.dart';
import 'package:firebase_database_dart_platform/src/data_snapshot.dart';
import 'package:firebase_database_dart_platform/src/errors.dart';
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:firebase_database_dart_platform/src/on_disconnect.dart';
import 'package:firebase_database_dart_platform/src/query.dart';
import 'package:firebase_database_dart_platform/src/reference.dart';
import 'package:firebase_database_dart_platform/src/transaction.dart';
import 'package:firebase_database_dart_platform/src/values.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart' as harness;

// lib/firebase_database_dart_platform.dart
final List<Object> _entry = <Object>[
  () => FirebaseDatabaseDart.isRegistered,
  FirebaseDatabaseDart.registerWith,
  _use,
  _clientFor,
];
const void Function({
  TokenProviderFactory? tokenProviderFor,
  AppCheckProviderFactory? appCheckProviderFor,
  DatabasePersistenceFactory? persistenceFor,
  bool? useDartCore,
})
_use = FirebaseDatabaseDart.use;
const fs.FirebaseDatabase Function(FirebaseApp app, {String? databaseURL})
_clientFor = FirebaseDatabaseDart.clientFor;

// lib/src/app.dart
final List<Object> _app = <Object>[
  TokenProviderFactory,
  AppCheckProviderFactory,
  _dartOptionsOf,
  _dartAppFor,
];
const dart_app.FirebaseOptions Function(FirebaseOptions options)
_dartOptionsOf = dartOptionsOf;
const dart_app.FirebaseApp Function(
  FirebaseApp app, {
  TokenProviderFactory? tokenProviderFor,
  AppCheckProviderFactory? appCheckProviderFor,
})
_dartAppFor = dartAppFor;

// lib/src/core.dart
final List<Object> _core = <Object>[_installCoreIfNeeded, _linuxCore];
const void Function({bool? force}) _installCoreIfNeeded = installCoreIfNeeded;
const FirebasePlatform Function() _linuxCore = LinuxFirebaseCore.new;

// lib/src/errors.dart
final List<Object> _errors = <Object>[
  databasePlugin,
  flutterFireCodes,
  _flutterFireCode,
  _convertError,
  _guard,
  _guardStream,
];
const String Function(String code) _flutterFireCode = flutterFireCode;
const Object Function(Object error, [StackTrace? stackTrace]) _convertError =
    convertError;
const Future<int> Function(Future<int> Function() body) _guard = guard<int>;
const Stream<int> Function(Stream<int> stream) _guardStream = guardStream<int>;

// lib/src/firebase_database.dart
final List<Object> _database = <Object>[
  DatabasePersistenceFactory,
  DatabaseClientFactory,
  _config,
  _settings,
  _createClient,
  _registered,
  () => DartFirebaseDatabase.config,
  () => DartFirebaseDatabase.clientFactory,
  () => DartFirebaseDatabase.anyStarted,
  _forApp,
  (DartFirebaseDatabase d) => d.started,
  _client,
  _delegateFor,
  _ref,
  (DartFirebaseDatabase d) => d.useDatabaseEmulator('localhost', 9000),
  (DartFirebaseDatabase d) => d.setPersistenceEnabled(true),
  (DartFirebaseDatabase d) => d.setPersistenceCacheSizeBytes(1),
  (DartFirebaseDatabase d) => d.setLoggingEnabled(true),
  _goOnline,
  _goOffline,
  _purge,
];
const DartDatabaseConfig Function({
  TokenProviderFactory? tokenProviderFor,
  AppCheckProviderFactory? appCheckProviderFor,
  DatabasePersistenceFactory? persistenceFor,
})
_config = DartDatabaseConfig.new;
const DatabaseClientSettings Function({
  required fs.DatabaseLogger logger,
  String? databaseUrl,
  String? emulatorHost,
  fs.DatabasePersistence? persistence,
})
_settings = DatabaseClientSettings.new;
const DatabaseClientFactory _createClient = createClient;
const DartFirebaseDatabase Function() _registered = DartFirebaseDatabase.new;
const DartFirebaseDatabase Function(FirebaseApp app, String? databaseURL)
_forApp = DartFirebaseDatabase.forApp;
fs.FirebaseDatabase _client(DartFirebaseDatabase d) => d.client;
DatabasePlatform _delegateFor(DartFirebaseDatabase d, FirebaseApp app) =>
    d.delegateFor(app: app, databaseURL: null);
DatabaseReferencePlatform _ref(DartFirebaseDatabase d) => d.ref('a');
Future<void> _goOnline(DartFirebaseDatabase d) => d.goOnline();
Future<void> _goOffline(DartFirebaseDatabase d) => d.goOffline();
Future<void> _purge(DartFirebaseDatabase d) => d.purgeOutstandingWrites();

// lib/src/values.dart
final List<Object> _values = <Object>[_transformValue, _mutableCopy];
const Object? Function(Object? value) _transformValue = transformValue;
const Object? Function(Object? value) _mutableCopy = mutableCopy;

// lib/src/query.dart
final List<Object> _query = <Object>[
  _pathSegments,
  _newQuery,
  (DartQuery q) => q.segments,
  _queryDatabase,
  _clientRef,
  _clientQuery,
  (DartQuery q) => q.path,
  _queryRef,
  _observe,
  _get,
  _keepSynced,
];
const List<String> Function(String? path) _pathSegments = pathSegments;
const DartQuery Function(DartFirebaseDatabase database, List<String> segments)
_newQuery = DartQuery.new;
DartFirebaseDatabase _queryDatabase(DartQuery q) => q.database;
fs.DatabaseReference _clientRef(DartQuery q) => q.clientRef;
fs.Query _clientQuery(DartQuery q, QueryModifiers m) => q.clientQuery(m);
DartReference _queryRef(DartQuery q) => q.ref;
Stream<DatabaseEventPlatform> _observe(
  DartQuery q,
  QueryModifiers m,
  DatabaseEventType t,
) => q.observe(m, t);
Future<DataSnapshotPlatform> _get(DartQuery q, QueryModifiers m) => q.get(m);
Future<void> _keepSynced(DartQuery q, QueryModifiers m) =>
    q.keepSynced(m, true);

// lib/src/reference.dart
final List<Object> _reference = <Object>[
  _newReference,
  _ofClient,
  _child,
  _parent,
  _root,
  (DartReference r) => r.key,
  _push,
  (DartReference r) => r.set(1),
  (DartReference r) => r.setWithPriority(1, 2),
  (DartReference r) => r.update(<String, Object?>{}),
  (DartReference r) => r.setPriority(1),
  (DartReference r) => r.remove(),
  _runTransaction,
  _onDisconnect,
];
const DartReference Function(DartFirebaseDatabase database, String? path)
_newReference = DartReference.new;
const DartReference Function(
  DartFirebaseDatabase database,
  fs.DatabaseReference clientRef,
)
_ofClient = DartReference.ofClient;
DartReference _child(DartReference r) => r.child('a');
DartReference? _parent(DartReference r) => r.parent;
DartReference _root(DartReference r) => r.root();
DartReference _push(DartReference r) => r.push();
Future<TransactionResultPlatform> _runTransaction(
  DartReference r,
  TransactionHandler h,
) => r.runTransaction(h, applyLocally: false);
DartOnDisconnect _onDisconnect(DartReference r) => r.onDisconnect();

// lib/src/data_snapshot.dart
final List<Object> _snapshot = <Object>[
  _clientEventType,
  _flutterFireEventType,
  _newSnapshot,
  (DartDataSnapshot s) => s.clientSnapshot,
  _snapshotRef,
  (DartDataSnapshot s) => s.key,
  (DartDataSnapshot s) => s.exists,
  (DartDataSnapshot s) => s.value,
  (DartDataSnapshot s) => s.priority,
  (DartDataSnapshot s) => s.hasChild('a'),
  _snapshotChild,
  _snapshotChildren,
  _newEvent,
  (DartDatabaseEvent e) => e.database,
  (DartDatabaseEvent e) => e.clientEvent,
  _eventSnapshot,
  (DartDatabaseEvent e) => e.previousChildKey,
  (DartDatabaseEvent e) => e.type,
];
const fs.DatabaseEventType Function(DatabaseEventType type) _clientEventType =
    clientEventType;
const DatabaseEventType Function(fs.DatabaseEventType type)
_flutterFireEventType = flutterFireEventType;
const DartDataSnapshot Function(
  DartFirebaseDatabase database,
  fs.DataSnapshot clientSnapshot,
)
_newSnapshot = DartDataSnapshot.new;
DartReference _snapshotRef(DartDataSnapshot s) => s.ref;
DartDataSnapshot _snapshotChild(DartDataSnapshot s) => s.child('a');
Iterable<DartDataSnapshot> _snapshotChildren(DartDataSnapshot s) => s.children;
const DartDatabaseEvent Function(
  DartFirebaseDatabase database,
  fs.DatabaseEvent clientEvent,
)
_newEvent = DartDatabaseEvent.new;
DartDataSnapshot _eventSnapshot(DartDatabaseEvent e) => e.snapshot;

// lib/src/transaction.dart
final List<Object> _transaction = <Object>[
  _clientHandler,
  _runDartTransaction,
  _newResult,
  (DartTransactionResult r) => r.committed,
  _resultSnapshot,
];
const fs.TransactionHandler Function(TransactionHandler handler)
_clientHandler = clientHandler;
Future<DartTransactionResult> _runDartTransaction(
  DartReference r,
  TransactionHandler h,
) => runDartTransaction(r, h, applyLocally: true);
const DartTransactionResult Function(bool committed, DartDataSnapshot snapshot)
_newResult = DartTransactionResult.new;
DartDataSnapshot _resultSnapshot(DartTransactionResult r) => r.snapshot;

// lib/src/on_disconnect.dart
final List<Object> _onDisconnectMembers = <Object>[
  _newOnDisconnect,
  _onDisconnectRef,
  (DartOnDisconnect o) => o.set(1),
  (DartOnDisconnect o) => o.setWithPriority(1, 2),
  (DartOnDisconnect o) => o.update(<String, Object?>{}),
  (DartOnDisconnect o) => o.cancel(),
  (DartOnDisconnect o) => o.remove(),
];
const DartOnDisconnect Function(
  DartFirebaseDatabase database,
  DartReference ref,
)
_newOnDisconnect = DartOnDisconnect.new;
DartReference _onDisconnectRef(DartOnDisconnect o) => o.ref;

// test/harness.dart
final List<Object> _harness = <Object>[
  harness.databaseUrl,
  harness.options,
  harness.reconnectDelay,
  () => harness.server,
  harness.createdClients,
  harness.tokens,
  _newApp,
  _registerForTests,
  _settle,
  _throwsDatabaseCode,
  _isDatabaseCode,
  _fixedToken,
];
const Future<FirebaseApp> Function({FirebaseOptions appOptions}) _newApp =
    harness.newApp;
const void Function({DatabasePersistenceFactory? persistenceFor})
_registerForTests = harness.registerForTests;
const Future<void> Function() _settle = harness.settle;
const Matcher Function(String code) _throwsDatabaseCode =
    harness.throwsDatabaseCode;
const Matcher Function(String code) _isDatabaseCode = harness.isDatabaseCode;
const dart_app.AuthTokenProvider Function(String token) _fixedToken =
    harness.FixedToken.new;

void main() {
  test('every public symbol is declared with its signature', () {
    final List<List<Object>> groups = <List<Object>>[
      _entry,
      _app,
      _core,
      _errors,
      _database,
      _values,
      _query,
      _reference,
      _snapshot,
      _transaction,
      _onDisconnectMembers,
      _harness,
    ];
    expect(groups.expand((List<Object> group) => group), hasLength(106));
  });
}
