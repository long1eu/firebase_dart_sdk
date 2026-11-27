/// The entry point: one database of one app. JS: `api/Database.ts`; Android: `FirebaseDatabase.java`;
/// iOS: `Api/FIRDatabase.m`.
library;

import 'dart:async';
import 'dart:math';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/src/api/data_snapshot.dart';
import 'package:firebase_database_dart/src/api/database_event.dart';
import 'package:firebase_database_dart/src/api/database_event_type.dart';
import 'package:firebase_database_dart/src/api/database_logger.dart';
import 'package:firebase_database_dart/src/api/database_reference.dart';
import 'package:firebase_database_dart/src/api/environment_stub.dart'
    if (dart.library.io) 'package:firebase_database_dart/src/api/environment_io.dart';
import 'package:firebase_database_dart/src/api/firebase_database_exception.dart';
import 'package:firebase_database_dart/src/api/query.dart';
import 'package:firebase_database_dart/src/core/callback_event_registration.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/database_persistence.dart';
import 'package:firebase_database_dart/src/core/persistence/default_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/lru_cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/writes_only_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine_opener.dart';
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/util/clock.dart';
import 'package:firebase_database_dart/src/core/util/push_id.dart';
import 'package:firebase_database_dart/src/core/util/validation.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/realtime/database_url.dart';
import 'package:firebase_database_dart/src/realtime/server_actions_factories.dart';
import 'package:meta/meta.dart';

/// The environment variable [FirebaseDatabase.emulatorHostFromEnvironment] reads.
const String _emulatorHostVariable = 'FIREBASE_DATABASE_EMULATOR_HOST';

/// A connection to one Realtime Database of a [FirebaseApp].
///
/// Each constructor call makes its own instance with its own connection: there is no global cache, and two
/// instances on one URL are two connections. Settings (emulator, persistence, logging) are constructor
/// parameters; there are no setters. Construction opens no connection: the first operation that
/// needs the server (a read, a listen, `.info` included, a write, a transaction, an onDisconnect
/// request, `keepSynced(true)`) or [goOnline] starts it. While connected or waiting to reconnect,
/// its timers keep a CLI or server program alive until [close]. Auth and App Check tokens come
/// from [app].
///
/// ```dart
/// final FirebaseDatabase db = FirebaseDatabase(app);
/// db.ref('rooms/1/messages').onChildAdded.listen((DatabaseEvent e) => print(e.snapshot.value));
/// await db.ref('rooms/1/messages').push().set(<String, Object?>{'text': 'hello'});
/// await db.close();
/// ```
final class FirebaseDatabase {
  /// Creates the database of [app].
  ///
  /// [databaseUrl] defaults to the app's `databaseURL`, then to
  /// `https://<projectId>-default-rtdb.firebaseio.com`; with neither and no project id it throws an
  /// [ArgumentError]. An empty [databaseUrl] also selects that default, even when the app has a
  /// `databaseURL`. Without [emulatorHost], the URL must be the root of a database over TLS
  /// (`https://` or `wss://`): a plain `http://` URL (the message points to [emulatorHost]), a
  /// path, user info, a port other than 443 on a host that is not loopback, a custom domain
  /// without `?ns=` and an invalid namespace each throw an [ArgumentError] here, with or without
  /// [persistence]. The message does not quote the URL. A namespace given as `?ns=` is
  /// lowercased and valid when it is 1 to 63 letters, digits or `-`, in any position: `?ns=-x-` is
  /// accepted as the namespace `-x-`. The client does not check that the server has it.
  ///
  /// [emulatorHost] (`'host:port'` or `'[ipv6]:port'`) connects to the Database emulator over plain
  /// WebSocket (over TLS for a `*.cloudworkstations.dev` host). The database URL (the argument,
  /// else the app's `databaseURL`) then gives only the namespace: its scheme (`http`, `https`,
  /// `ws` or `wss`), host and port are not used to connect, and the client always sends the
  /// namespace as `ns`. `http://10.0.2.2:9000?ns=demo` and `http://my-mac.local:9000?ns=demo` both
  /// mean namespace `demo`.
  ///
  /// Without `?ns=`, the scheme, host and port choose the namespace by the rule the emulator
  /// applies to a Host header that names none: take the URL's `host:port`, without the port when
  /// it is the scheme's default (80 for `http` and `ws`, 443 for `https` and `wss`), split it on
  /// `.`, and use the first part when it is a valid namespace (lowercase letters, digits, `-`)
  /// and, with four or more parts, not a 32-bit integer; else use `fake-server`. So
  /// `http://my-mac.local:9000` gives `my-mac`, `https://db.example.com` gives `db`,
  /// `http://localhost` gives `localhost`, and `http://localhost:9000`, `http://my-mac:9000` (a
  /// one-label name with a port) and any IP address give `fake-server`. When the argument is
  /// null and the app's `databaseURL` is null or empty, or the argument is empty (which skips the
  /// app's `databaseURL`), the namespace is the
  /// project's default database `<projectId>-default-rtdb`; a production URL of that database or
  /// `?ns=` with that name reach it too. The emulator applies the rules of `firebase.json` only
  /// to the databases `firebase.json` names, by default `<projectId>-default-rtdb`; every other
  /// namespace has open rules. Measured (our emulator probe, one rules file): only the default
  /// namespace got the rules. Read in firebase-tools' code (`getRulesConfig`), not run: the array
  /// form of `"database"` gives rules to each named instance.
  ///
  /// When the namespace came from the host (no `?ns=`) and is not `<projectId>-default-rtdb`, or
  /// the app has no project id, [logger] receives one warning at the first connection of this
  /// instance (not again on a reconnect). It names the namespace and the emulator host and says
  /// to give `?ns=` when `firebase.json` does not name that namespace; the client cannot read
  /// `firebase.json`, so it also warns when it does. A logger that throws does not stop the
  /// connection. A URL with `?ns=`, or a null or empty one as above, logs nothing. User info, a
  /// path, a fragment, a query key other than `ns` and an invalid namespace still throw an
  /// [ArgumentError] whose message does not quote the URL. See
  /// [emulatorHostFromEnvironment]. [mockUserToken] is sent to the emulator as it is: build a
  /// user's token with `mockUserTokenFor`. A string that is not such a token (the literal `'owner'`
  /// included) is an admin credential for the emulator and bypasses the rules. Passing it without
  /// [emulatorHost], or empty, throws an [ArgumentError].
  ///
  /// [persistence] turns on disk persistence (memory only when null). If the store cannot be
  /// opened (its opener throws), nothing is thrown: the instance runs memory only, the client logs
  /// one warning, and [persistenceEnabled] turns false, so writes made then are not kept for a
  /// restart. [logger] receives log messages (silent when null).
  ///
  /// The constructor is synchronous, also with persistence: opening the store and restoring writes
  /// happen in the background, and calls made meanwhile wait for it, and their local effects apply
  /// in call order. The order in which their requests then leave is not the call order across
  /// kinds: a listen or a get may leave before an earlier set. If the start fails after the store
  /// opened, every waiting and later call fails with that error.
  ///
  /// The persisted cache is keyed by the app name and [databaseUrl], which is normalised: every
  /// spelling of one URL with a host name shares one cache, and two namespaces on one host never
  /// do. A loopback host is kept as written (lowercased), so `localhost`, `127.0.0.1` and
  /// `[::1]` give three caches for one server, production or emulator.
  ///
  /// [clock] and [random] replace the wall clock and the random source (push ids, backoff), for tests.
  FirebaseDatabase(
    this.app, {
    String? databaseUrl,
    String? emulatorHost,
    String? mockUserToken,
    DatabasePersistence? persistence,
    DatabaseLogger? logger,
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting double Function()? random,
  }) {
    final _Target target = _Target.resolve(
      app,
      databaseUrl: databaseUrl,
      emulatorHost: emulatorHost,
      mockUserToken: mockUserToken,
    );
    _setUp(
      target,
      connectionFactory: _realtimeConnectionFactory(
        app,
        target.info,
        mockUserToken: mockUserToken,
        clock: clock,
        random: random,
      ),
      persistence: persistence,
      logger: logger,
      clock: clock,
      random: random,
    );
  }

  FirebaseDatabase._withConnection(
    this.app, {
    required ServerActionsFactory connectionFactory,
    String? databaseUrl,
    String? emulatorHost,
    DatabasePersistence? persistence,
    DatabaseLogger? logger,
    DateTime Function()? clock,
    double Function()? random,
  }) {
    _setUp(
      _Target.resolve(
        app,
        databaseUrl: databaseUrl,
        emulatorHost: emulatorHost,
      ),
      connectionFactory: connectionFactory,
      persistence: persistence,
      logger: logger,
      clock: clock,
      random: random,
    );
  }

  /// The `FIREBASE_DATABASE_EMULATOR_HOST` environment variable, or null when it is not set or on the web.
  ///
  /// ```dart
  /// final FirebaseDatabase db = FirebaseDatabase(
  ///   app,
  ///   emulatorHost: FirebaseDatabase.emulatorHostFromEnvironment,
  /// );
  /// ```
  static String? get emulatorHostFromEnvironment =>
      environmentVariable(_emulatorHostVariable);

  /// The app whose options, Auth and App Check this database uses. When the app is deleted, the database
  /// closes itself.
  final FirebaseApp app;

  late final _Target _target;

  /// The name of [app], read at construction: [FirebaseApp.name] throws once the app is deleted.
  late final String _appName;
  late final ServerActionsFactory _connectionFactory;
  late final PushIdGenerator _pushIds;
  DatabasePersistence? _persistence;
  DatabaseLogger? _logger;
  Clock? _clock;

  Repo? _repo;
  final List<void Function(Repo repo)> _queue = <void Function(Repo repo)>[];
  Future<void>? _opening;
  PersistenceStorageEngine? _engine;
  bool _openFailed = false;

  /// The error that stopped the start after persistence opened; every call fails with it.
  Object? _startError;
  StackTrace? _startStackTrace;

  bool _closed = false;
  Future<void>? _closeFuture;
  StreamSubscription<String>? _deleteSubscription;
  final Set<_Listener> _listeners = <_Listener>{};
  final Set<_Pending<Object?>> _pending = <_Pending<Object?>>{};

  void _setUp(
    _Target target, {
    required ServerActionsFactory connectionFactory,
    DatabasePersistence? persistence,
    DatabaseLogger? logger,
    Clock? clock,
    double Function()? random,
  }) {
    _target = target;
    _appName = app.name;
    final String? warning = target.namespaceWarning;
    _connectionFactory = warning == null
        ? connectionFactory
        : _warnAtFirstConnect(connectionFactory, warning);
    _persistence = persistence;
    _logger = logger;
    _clock = clock;
    _pushIds = PushIdGenerator(
      nowMillis: _nowMillis,
      random: random == null ? Random() : _FunctionRandom(random),
    );
    _deleteSubscription = app.onDeleteApp.listen((String _) {
      unawaited(close());
    });
    if (persistence == null) {
      try {
        _startRepo(null);
      } on Object {
        unawaited(_deleteSubscription?.cancel());
        _deleteSubscription = null;
        rethrow;
      }
    } else {
      _opening = _openPersistence(persistence);
    }
  }

  int _nowMillis() {
    final Repo? repo = _repo;
    if (repo != null) {
      return repo.serverTime();
    }
    return (_clock ?? DateTime.now)().millisecondsSinceEpoch;
  }

  Future<void> _openPersistence(DatabasePersistence persistence) async {
    PersistenceManager? manager;
    try {
      final PersistenceStorageEngine engine = await persistence.opener(
        PersistenceKey(appName: app.name, databaseUrl: _target.databaseUrl),
        logger: _logger,
      );
      _engine = engine;
      manager = persistence.cacheServerData
          ? DefaultPersistenceManager(
              engine,
              LruCachePolicy(persistence.cacheSizeBytes),
              _clock ?? DateTime.now,
            )
          : WritesOnlyPersistenceManager(engine);
    } on Object catch (e) {
      _openFailed = true;
      _logger?.call(
        DatabaseLogLevel.warning,
        'Persistence could not be opened (${e.runtimeType}); running memory only.',
      );
    }
    if (_closed) {
      return;
    }
    try {
      _startRepo(manager);
    } on Object catch (error, stackTrace) {
      _failStart(error, stackTrace);
    }
  }

  /// Fails every queued call, open stream and pending Future with [error], and every later call
  /// too.
  void _failStart(Object error, StackTrace stackTrace) {
    _startError = error;
    _startStackTrace = stackTrace;
    _queue.clear();
    _logger?.call(
      DatabaseLogLevel.error,
      'The database could not start (${error.runtimeType}); every call fails with that error.',
    );
    for (final _Listener listener in List<_Listener>.of(_listeners)) {
      listener.end(error);
    }
    for (final _Pending<Object?> pending in List<_Pending<Object?>>.of(
      _pending,
    )) {
      pending.fail(error, stackTrace);
    }
  }

  void _startRepo(PersistenceManager? manager) {
    final Repo repo = Repo(
      repoInfo: _target.info,
      connectionFactory: _connectionFactory,
      persistenceManager: manager,
      clock: _clock,
      logger: _logger,
    );
    _repo = repo;
    while (_queue.isNotEmpty && !_closed) {
      _queue.removeAt(0)(repo);
    }
  }

  /// Runs [op] on the Repo now, or after the Repo started and the calls before it ran.
  void _withRepo(void Function(Repo repo) op) {
    if (_closed || _startError != null) {
      return;
    }
    final Repo? repo = _repo;
    if (repo != null && _queue.isEmpty) {
      op(repo);
    } else {
      _queue.add(op);
    }
  }

  FirebaseDatabaseException _closedError() =>
      exceptionFromDatabaseError(DatabaseError.closed());

  Future<T> _request<T>(void Function(Repo repo, _Pending<T> pending) start) {
    if (_closed) {
      return Future<T>.error(_closedError());
    }
    final Object? startError = _startError;
    if (startError != null) {
      return Future<T>.error(startError, _startStackTrace);
    }
    final _Pending<T> pending = _Pending<T>(_pending);
    _withRepo((Repo repo) => start(repo, pending));
    return pending.completer.future;
  }

  Future<void> _write(
    void Function(Repo repo, WriteCompletion onComplete) send,
  ) => _request<void>(
    (Repo repo, _Pending<void> pending) => send(repo, (DatabaseError? error) {
      if (error == null) {
        pending.complete(null);
      } else {
        pending.fail(exceptionFromDatabaseError(error));
      }
    }),
  );

  Stream<DatabaseEvent> _events(
    Query query,
    Set<EventType> types,
  ) => Stream<DatabaseEvent>.multi((MultiStreamController<DatabaseEvent> c) {
    // After close the stream ends at once with done, as an open stream does at close.
    if (_closed) {
      c.close();
      return;
    }
    final Object? failure = _startError;
    if (failure != null) {
      c
        ..addError(failure)
        ..close();
      return;
    }
    late final _Listener listener;
    final CallbackEventRegistration registration = CallbackEventRegistration(
      query.spec,
      types,
      onEvent: (DataEvent event) {
        if (!listener.ended) {
          c.addSync(_toEvent(query, event));
        }
      },
      onCancel: (DatabaseError error) =>
          listener.end(exceptionFromDatabaseError(error)),
    )..isUserInitiated = true;
    listener = _Listener(registration, c, _listeners);
    _listeners.add(listener);
    _withRepo((Repo repo) {
      if (!listener.ended) {
        repo.addEventCallback(registration);
      }
    });
    c.onCancel = () {
      if (listener.ended) {
        return Future<void>.value();
      }
      listener.ended = true;
      _listeners.remove(listener);
      _withRepo((Repo repo) => repo.removeEventCallback(registration));
      registration.zombify();
      // A future of the caller's zone (the default is a root-zone future, which fake clocks in
      // tests never complete).
      return Future<void>.value();
    };
  });

  DatabaseEvent _toEvent(Query query, DataEvent event) {
    final DatabaseReference ref = DatabaseReference.internal(
      this,
      QuerySpec.defaultAt(event.snapshotPath),
    );
    final DataSnapshot snapshot = DataSnapshot.internal(
      ref,
      event.snapshot,
      query.spec.index,
    );
    final DatabaseEventType type = switch (event.eventType) {
      EventType.value => DatabaseEventType.value,
      EventType.childAdded => DatabaseEventType.childAdded,
      EventType.childChanged => DatabaseEventType.childChanged,
      EventType.childMoved => DatabaseEventType.childMoved,
      EventType.childRemoved => DatabaseEventType.childRemoved,
    };
    final bool hasPrevious =
        type == DatabaseEventType.childAdded ||
        type == DatabaseEventType.childChanged ||
        type == DatabaseEventType.childMoved;
    return DatabaseEvent.internal(
      type,
      snapshot,
      previousChildKey: hasPrevious ? event.previousName?.name : null,
    );
  }

  Uri _urlFor(Path path) => Uri.parse(
    '${_target.info.secure ? 'https' : 'http'}://${_target.info.host}'
    '${path.toUrlEncodedString()}',
  );

  Object? _infoValue(String name) {
    final Repo? repo = _repo;
    if (repo == null) {
      return null;
    }
    Node node = repo.infoData.getNode(Path('.info/$name'));
    if (node.isEmpty) {
      node = repo.infoData.getNode(Path(name));
    }
    return node.value;
  }

  /// The URL of the database, normalised: `https://<host>` with the host in lowercase and without
  /// the default port, followed by `?ns=<namespace>` when the host does not name the namespace (a
  /// custom domain, or a `?ns=` that differs from the first host label). With an emulator it is
  /// `http://<emulatorHost>?ns=<namespace>` (`https` for `*.cloudworkstations.dev`), whatever host
  /// the constructor's `databaseUrl` argument names: with `emulatorHost: '10.0.2.2:9000'`,
  /// `databaseUrl: 'http://localhost:9000?ns=demo'` gives `http://10.0.2.2:9000?ns=demo`. Every
  /// spelling of one production URL with a host name gives the same value. A loopback host and an
  /// emulator host are kept as written (lowercased), so `localhost`, `127.0.0.1`, `[::1]` and
  /// `[0:0:0:0:0:0:0:1]` give four values for one server. Two databases can share one value on a
  /// `*.cloudworkstations.dev` host: a production database with `?ns=` and the emulator at port 443
  /// with that namespace. It keys the persisted cache (pass it to `clearSqlitePersistence`).
  Uri get databaseUrl => _target.databaseUrl;

  /// The reference at [path]. `''`, `'a/b'` and `'/a/b'` are accepted and empty segments are
  /// dropped (`'a//b'` is `a/b`). The `.info` paths work too, for example
  /// `ref('.info/connected').onValue`, but writes under `.info` throw an [ArgumentError]. An
  /// invalid key throws an [ArgumentError]. Makes no request, and still works after [close].
  DatabaseReference ref([String path = '']) {
    if (path.replaceAll('/', '').isNotEmpty) {
      validateRootPathString('ref', 'path', path);
    }
    return DatabaseReference.internal(this, QuerySpec.defaultAt(Path(path)));
  }

  /// The reference for a full [url] of this database (for example
  /// `https://my-project-default-rtdb.firebaseio.com/a/b`). Path segments are percent-decoded.
  ///
  /// Outside an emulator the URL without its path must be accepted by the constructor's
  /// `databaseUrl` rules and name this database: its host, and its namespace (`?ns=` or the first
  /// label of a `firebaseio.com` / `firebasedatabase.app` host). With an emulator the host and
  /// port are not compared, but the URL must still be `http`, `https`, `ws` or `wss` with a valid
  /// host, no user info and no query key but `ns`, and a namespace it names (the same two ways)
  /// must be this database's. Anything else throws an [ArgumentError], as does a path that is not
  /// valid percent-encoded UTF-8 or that [ref] refuses.
  ///
  /// No message quotes the whole URL, its user info or its query. A message may name the URL's
  /// host (another host) and, as [ref] does, a decoded path it refuses.
  DatabaseReference refFromUrl(String url) {
    final ({String root, String path}) parts = _splitPath(url);
    final RepoInfo here = _target.info;
    final String? namespace;
    if (here.isUsingEmulator) {
      namespace = _Target._argument('url', () => namespaceOfUrl(parts.root));
    } else {
      final RepoInfo info = _Target._argument(
        'url',
        () => parseDatabaseUrl(parts.root),
      );
      if (info.host != here.host) {
        throw ArgumentError(
          'refFromUrl: Host name does not match the current database: '
              '(found ${info.host} but expected ${here.host})',
          'url',
        );
      }
      namespace = info.namespace;
    }
    if (namespace != null && namespace != here.namespace) {
      // The URL's ns is not quoted: it is a query value.
      throw ArgumentError(
        'refFromUrl: The URL names another database than this one '
            '(this namespace is ${here.namespace})',
        'url',
      );
    }
    return ref(parts.path);
  }

  /// Disconnects from the server and stays offline until [goOnline]. Writes stay queued and listeners
  /// keep their data. Synchronous and idempotent, valid before the first operation (that operation
  /// then does not connect); a no-op after [close] or after a failed start.
  void goOffline() => _withRepo((Repo repo) => repo.interrupt());

  /// Reconnects after [goOffline]. On an instance that has not connected yet it starts the
  /// connection, as a first read or write would. Synchronous and idempotent; a no-op after [close]
  /// or after a failed start. It does not undo a server kill: once the server has killed the
  /// connection the instance stays offline until it is recreated.
  void goOnline() => _withRepo((Repo repo) => repo.resume());

  /// Cancels every write the server has not acknowledged, and every running transaction.
  ///
  /// Local events revert the writes, and their Futures and the transactions fail with
  /// `write-canceled`. A write that was already sent can still be applied by the server: its
  /// acknowledgement is ignored here. onDisconnect operations still queued locally are cancelled
  /// and their Futures fail with `write-canceled`; those the server has already registered are not
  /// undone. The returned Future completes at once, after the local revert and with no round trip;
  /// after [close] it fails with `database-closed`.
  Future<void> purgeOutstandingWrites() =>
      _request<void>((Repo repo, _Pending<void> pending) {
        repo.purgeOutstandingWrites();
        pending.complete(null);
      });

  /// Whether the client is connected to the server (`.info/connected`). The first event is the current
  /// state.
  ///
  /// [close] (also run when the app is deleted) ends the stream with done and no error; no final
  /// `false` event comes before it.
  Stream<bool> get onConnected => ref(
    '.info/connected',
  ).onValue.map((DatabaseEvent event) => event.snapshot.value == true);

  /// The current value of [onConnected], synchronously. Always false once [close] has been called
  /// or the app deleted (from the moment `app.delete()` is called, before the close it starts has
  /// run), whatever it was before.
  bool get isConnected =>
      !_closed && !_appDeleted && _infoValue('connected') == true;

  /// Whether [app] was deleted; its close runs one event later, through `onDeleteApp`. One map
  /// lookup while the app lives; an app made again with the same name is another object.
  bool get _appDeleted {
    try {
      return !identical(Firebase.app(_appName), app);
    } on FirebaseException {
      return true;
    }
  }

  /// The server's clock minus this device's (`.info/serverTimeOffset`); zero until the first connection.
  Duration get serverTimeOffset {
    final Repo? repo = _repo;
    return repo == null
        ? Duration.zero
        : Duration(milliseconds: repo.serverClock.offsetMillis);
  }

  /// The device's time corrected by [serverTimeOffset].
  DateTime get estimatedServerTime =>
      DateTime.fromMillisecondsSinceEpoch(_nowMillis());

  /// Whether data written now survives a restart.
  ///
  /// It reports what was asked for (a non-null `persistence`) until the store is open, then whether the
  /// store is durable. It is false when the store could not be opened (its opener threw), and when
  /// another owner holds the cache file (after waiting one lease period
  /// the instance runs memory only and logs one warning), and it turns false if the store fails or is
  /// fenced later in the session.
  bool get persistenceEnabled {
    if (_persistence == null || _openFailed) {
      return false;
    }
    return _engine?.isDurable ?? true;
  }

  /// Closes the instance. Idempotent.
  ///
  /// Every open stream ends with done and no error event (a close is not a failure): the events
  /// still queued for it are dropped inside this call, and done comes in a microtask (after
  /// `resume` for a paused subscription, following its buffered events). Every
  /// pending Future (writes, gets, `once`, transactions, onDisconnect operations) fails with
  /// `database-closed`, then the returned Future completes. Writes that were not acknowledged fail
  /// here; with persistence they stay on disk and the next instance sends them. Closing ends the
  /// connection, so the server applies the onDisconnect writes this client registered.
  /// Afterwards every asynchronous call fails with `database-closed`, a stream listened to ends
  /// with done and no error, [ref] still works (it makes no request), and [goOnline] and
  /// [goOffline] do nothing.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    _queue.clear();
    final StreamSubscription<String>? deleteSubscription = _deleteSubscription;
    _deleteSubscription = null;
    for (final _Listener listener in List<_Listener>.of(_listeners)) {
      listener.end(null);
    }
    final FirebaseDatabaseException error = _closedError();
    for (final _Pending<Object?> pending in List<_Pending<Object?>>.of(
      _pending,
    )) {
      pending.fail(error);
    }
    // Not awaited: a broadcast cancel completes with a root-zone future, which a fake clock never runs.
    unawaited(deleteSubscription?.cancel());
    final Repo? repo = _repo;
    if (repo != null) {
      await repo.close();
    } else {
      await _opening;
    }
    _engine?.close();
  }
}

/// The client's view of a [FirebaseDatabase], for `Query`, `DatabaseReference`, `OnDisconnect` and the
/// testing factories. Not exported.
@internal
extension FirebaseDatabaseInternal on FirebaseDatabase {
  /// Whether [FirebaseDatabase.close] was called.
  bool get isClosed => _closed;

  /// The `database-closed` exception that Futures fail with after [FirebaseDatabase.close].
  FirebaseDatabaseException closedError() => _closedError();

  /// The stream of the events of [types] on [query]: one registration per listen.
  Stream<DatabaseEvent> eventStream(Query query, Set<EventType> types) =>
      _events(query, types);

  /// Runs [send] on the Repo (after start-up) and completes with its completion; fails with
  /// `database-closed` after close.
  Future<void> write(
    void Function(Repo repo, WriteCompletion onComplete) send,
  ) => _write(send);

  /// Runs [start] on the Repo (after start-up); [start] completes or fails the pending request.
  Future<T> request<T>(
    void Function(
      Repo repo,
      void Function(T value) complete,
      void Function(Object error, [StackTrace? stackTrace]) fail,
    )
    start,
  ) => _request<T>(
    (Repo repo, _Pending<T> pending) =>
        start(repo, pending.complete, pending.fail),
  );

  /// A new push id, made from the estimated server time.
  String nextPushId() => _pushIds.next();

  /// The URL of [path] in this database.
  Uri urlFor(Path path) => _urlFor(path);

  /// Where the connection goes: the host and namespace the WebSocket URL is built from.
  RepoInfo get repoInfo => _target.info;
}

/// A [FirebaseDatabase] of [app] whose connection is built by [connectionFactory] (the testing
/// factories pass a fake server). [databaseUrl] and [emulatorHost] are resolved as by the
/// constructor; by default the database URL comes from the app's options.
@internal
FirebaseDatabase firebaseDatabaseWithConnection(
  FirebaseApp app, {
  required ServerActionsFactory connectionFactory,
  String? databaseUrl,
  String? emulatorHost,
  DatabasePersistence? persistence,
  DatabaseLogger? logger,
  DateTime Function()? clock,
  double Function()? random,
}) => FirebaseDatabase._withConnection(
  app,
  connectionFactory: connectionFactory,
  databaseUrl: databaseUrl,
  emulatorHost: emulatorHost,
  persistence: persistence,
  logger: logger,
  clock: clock,
  random: random,
);

/// [factory] with [message] logged as a warning when its first connection is up; reconnects and
/// later connections of the same database log nothing. An error thrown by the logger is dropped,
/// so the connect still reaches the Repo.
ServerActionsFactory _warnAtFirstConnect(
  ServerActionsFactory factory,
  String message,
) {
  bool warned = false;
  return (ServerActionsDelegate delegate, DatabaseLogger? logger) => factory(
    _OnConnectDelegate(delegate, () {
      if (!warned) {
        warned = true;
        try {
          logger?.call(DatabaseLogLevel.warning, message);
        } on Object {
          // A throwing logger must not stop the connect that follows.
        }
      }
    }),
    logger,
  );
}

/// A [ServerActionsDelegate] that runs [_onConnect] before passing each connect to [_inner].
final class _OnConnectDelegate implements ServerActionsDelegate {
  _OnConnectDelegate(this._inner, this._onConnect);

  final ServerActionsDelegate _inner;
  final void Function() _onConnect;

  @override
  void onConnect() {
    _onConnect();
    _inner.onConnect();
  }

  @override
  void onDataUpdate(
    String path,
    Object? data, {
    required bool isMerge,
    int? tag,
  }) => _inner.onDataUpdate(path, data, isMerge: isMerge, tag: tag);

  @override
  void onRangeMergeUpdate(
    String path,
    List<WireRangeMerge> merges, {
    int? tag,
  }) => _inner.onRangeMergeUpdate(path, merges, tag: tag);

  @override
  void onDisconnect() => _inner.onDisconnect();

  @override
  void onAuthStatus(String status, {String? explanation}) =>
      _inner.onAuthStatus(status, explanation: explanation);

  @override
  void onAppCheckStatus(String status, {String? explanation}) =>
      _inner.onAppCheckStatus(status, explanation: explanation);

  @override
  void onServerShutdown(String reason) => _inner.onServerShutdown(reason);

  @override
  void onServerInfoUpdate(Map<String, Object?> updates) =>
      _inner.onServerInfoUpdate(updates);
}

ServerActionsFactory _realtimeConnectionFactory(
  FirebaseApp app,
  RepoInfo info, {
  String? mockUserToken,
  DateTime Function()? clock,
  double Function()? random,
}) => persistentConnectionFactory(
  info,
  // With no provider set the app answers as its own provider and throws: that means no user.
  authProvider: mockUserToken != null
      ? _MockUserTokenProvider(mockUserToken)
      : identical(app.authProvider, app)
      ? null
      : app.authProvider,
  appCheckProvider: app.appCheckProvider,
  appId: app.options.appId,
  // The app replays its current state to a new listener: only a change to "connected" is a hint.
  connectivityHints: app.onNetworkConnected
      .distinct()
      .skip(1)
      .where((bool connected) => connected)
      .map((bool _) {}),
  clock: clock,
  random: random,
);

/// The auth provider of an instance created with `mockUserToken`: always that token.
final class _MockUserTokenProvider extends AuthTokenProvider {
  _MockUserTokenProvider(this._token);

  final String _token;

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async =>
      GetTokenResult(_token);

  @override
  String? get uid => null;

  @override
  Stream<AuthTokenChange> get onTokenChanged =>
      const Stream<AuthTokenChange>.empty();
}

/// One open event stream.
final class _Listener {
  _Listener(this.registration, this.controller, this._owner);

  final CallbackEventRegistration registration;
  final MultiStreamController<DatabaseEvent> controller;
  final Set<_Listener> _owner;
  bool ended = false;

  /// Ends the stream with [error], when not null, then done; queued events of the registration
  /// are dropped.
  void end(Object? error) {
    if (ended) {
      return;
    }
    ended = true;
    _owner.remove(this);
    registration.zombify();
    if (error != null) {
      controller.addErrorSync(error);
    }
    controller.closeSync();
  }
}

/// One pending Future of the instance; [FirebaseDatabase.close] fails what is left.
final class _Pending<T> {
  _Pending(this._owner) {
    _owner.add(this);
  }

  final Set<_Pending<Object?>> _owner;
  final Completer<T> completer = Completer<T>();

  void complete(T value) {
    _owner.remove(this);
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  void fail(Object error, [StackTrace? stackTrace]) {
    _owner.remove(this);
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }
}

/// A [Random] over the injected `random` function.
final class _FunctionRandom implements Random {
  _FunctionRandom(this._next);

  final double Function() _next;

  @override
  bool nextBool() => _next() < 0.5;

  @override
  double nextDouble() => _next();

  @override
  int nextInt(int max) => (_next() * max).floor().clamp(0, max - 1);
}

/// Splits [url] into its root (scheme, host, port and query, given to `parseDatabaseUrl`) and its
/// path, percent-decoded, with empty segments dropped. Nothing else is checked here.
({String root, String path}) _splitPath(String url) {
  final int scheme = url.indexOf('://');
  final int start = scheme < 0 ? 0 : scheme + 3;
  int end = url.length;
  for (final String stop in const <String>['?', '#']) {
    final int index = url.indexOf(stop, start);
    if (index >= 0 && index < end) {
      end = index;
    }
  }
  final int slash = url.indexOf('/', start);
  if (slash < 0 || slash > end) {
    return (root: url, path: '');
  }
  final List<String> segments = <String>[];
  for (final String segment in url.substring(slash, end).split('/')) {
    if (segment.isEmpty) {
      continue;
    }
    try {
      segments.add(Uri.decodeComponent(segment));
    } on ArgumentError {
      // Not quoted: the URL can hold user info, and the path user data.
      throw ArgumentError(
        'The path is not valid percent-encoded UTF-8.',
        'url',
      );
    }
  }
  return (
    root: url.substring(0, slash) + url.substring(end),
    path: segments.join('/'),
  );
}

/// Where an instance connects: its [RepoInfo] and public [databaseUrl].
final class _Target {
  _Target(this.info, this.databaseUrl, {this.namespaceWarning});

  /// The target for [app] and the constructor arguments (contract C27). JS: `api/Database.ts`
  /// (`repoManagerDatabaseFromApp`, `connectDatabaseEmulator`).
  factory _Target.resolve(
    FirebaseApp app, {
    String? databaseUrl,
    String? emulatorHost,
    String? mockUserToken,
  }) {
    if (mockUserToken != null && mockUserToken.isEmpty) {
      throw ArgumentError.value(
        mockUserToken,
        'mockUserToken',
        'Must not be empty.',
      );
    }
    if (mockUserToken != null && emulatorHost == null) {
      throw ArgumentError.value(
        mockUserToken,
        'mockUserToken',
        'mockUserToken is only allowed together with emulatorHost.',
      );
    }
    final String? url = databaseUrl ?? app.options.databaseURL;
    if (emulatorHost != null) {
      return _Target._emulator(app, url, emulatorHost);
    }
    final RepoInfo info = url == null || url.isEmpty
        ? _defaultDatabase(app)
        : _argument('databaseUrl', () => parseDatabaseUrl(url));
    // The namespace is in the URL when the host does not name it (a custom domain or `?ns=`).
    return _Target(info, persistenceUrlOf(info));
  }

  /// The target of the emulator at [emulatorHost], with the namespace of [url]
  /// (`emulatorUrlNamespace`: its `?ns=`, else the emulator's own rule for its host) or, without
  /// [url], of the project's default database. The scheme, host and port of [url] are not used to
  /// connect; without `?ns=` they choose the namespace.
  factory _Target._emulator(FirebaseApp app, String? url, String emulatorHost) {
    if (emulatorHost.isEmpty) {
      throw ArgumentError.value(
        emulatorHost,
        'emulatorHost',
        'Must be host:port.',
      );
    }
    final String namespace;
    bool fromHost = false;
    if (url == null || url.isEmpty) {
      namespace = _defaultDatabase(app).namespace;
    } else {
      try {
        namespace = emulatorUrlNamespace(url);
      } on FormatException catch (e) {
        throw ArgumentError(e.message, 'databaseUrl');
      }
      // The URL is valid here, so it parses; without a scheme it was read as https.
      final Uri parsed = Uri.parse(url.contains('://') ? url : 'https://$url');
      // Without a project id the default database is unknown: any namespace from the host warns.
      final String? projectId = app.options.projectId;
      fromHost =
          !parsed.queryParameters.containsKey('ns') &&
          (projectId == null ||
              namespace != '${projectId.toLowerCase()}-default-rtdb');
    }
    final RepoInfo info = _argument('emulatorHost', () {
      final ({String host, int port}) address = parseEmulatorHost(emulatorHost);
      return emulatorDatabase(address.host, address.port, namespace: namespace);
    });
    return _Target(
      info,
      persistenceUrlOf(info),
      namespaceWarning: fromHost
          ? 'Database emulator at ${info.host}: the database URL has no ?ns=, so the '
                'namespace is "${info.namespace}", chosen from the URL host by the emulator\'s '
                'rule (fake-server when the host names none). The emulator applies the rules '
                'of firebase.json only to the databases firebase.json names (by default '
                '<projectId>-default-rtdb); any other namespace has open rules. If '
                '"${info.namespace}" is not named there, give the database with ?ns=<name>.'
          : null,
    );
  }

  /// The warning to log once at the first connection, or null: set when the emulator namespace
  /// came from the URL host (no `?ns=`) and is not the project's default database, or the app
  /// has no project id.
  final String? namespaceWarning;

  /// The default database of the app's project id; throws an [ArgumentError] without one.
  static RepoInfo _defaultDatabase(FirebaseApp app) {
    final String? projectId = app.options.projectId;
    if (projectId == null || projectId.isEmpty) {
      throw ArgumentError(
        "Can't determine Firebase Database URL. Be sure to include a Project ID "
        'or a databaseUrl.',
      );
    }
    return defaultDatabase(projectId);
  }

  /// The value of [parse], with a [FormatException] turned into an [ArgumentError] on [name]. The
  /// message never quotes the URL, which can hold a credential by mistake.
  static T _argument<T>(String name, T Function() parse) {
    try {
      return parse();
    } on FormatException catch (e) {
      throw ArgumentError(e.message, name);
    }
  }

  final RepoInfo info;
  final Uri databaseUrl;
}
