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
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/database_persistence.dart';
import 'package:firebase_database_dart/src/core/persistence/default_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/lru_cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine_opener.dart';
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/util/clock.dart';
import 'package:firebase_database_dart/src/core/util/push_id.dart';
import 'package:firebase_database_dart/src/core/util/validation.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/realtime/server_actions_factories.dart';
import 'package:meta/meta.dart';

/// The environment variable [FirebaseDatabase.emulatorHostFromEnvironment] reads.
const String _emulatorHostVariable = 'FIREBASE_DATABASE_EMULATOR_HOST';

/// A connection to one Realtime Database of a [FirebaseApp].
///
/// Each constructor call makes its own instance with its own connection: there is no global cache, and two
/// instances on one URL are two connections. Settings (emulator, persistence, logging) are constructor
/// parameters; there are no setters. An open instance keeps a CLI or server program alive until [close].
/// Auth and App Check tokens come from [app].
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
  /// [databaseUrl] defaults to the app's `databaseURL`, then to `https://<projectId>-default-rtdb.firebaseio.com`;
  /// with neither and no project id it throws an [ArgumentError].
  ///
  /// [emulatorHost] (`'host:port'` or `'[ipv6]:port'`) connects to the Database emulator over plain
  /// WebSocket, with the database URL's namespace (by default `<projectId>-default-rtdb`). See
  /// [emulatorHostFromEnvironment]. [mockUserToken] is sent to the emulator as it is: build a user's token
  /// with `mockUserTokenFor`. A string that is not such a token (the literal `'owner'` included) is an
  /// admin credential for the emulator and bypasses the rules. Passing it without [emulatorHost], or
  /// empty, throws an [ArgumentError].
  ///
  /// [persistence] turns on disk persistence (memory only when null). [logger] receives log messages
  /// (silent when null).
  ///
  /// The constructor is synchronous, also with persistence: opening the store and restoring writes happen in
  /// the background, and calls made meanwhile wait for it, in call order.
  ///
  /// [clock], [random] and [delay] replace the wall clock, the random source (push ids, backoff) and the
  /// timers, for tests.
  FirebaseDatabase(
    this.app, {
    String? databaseUrl,
    String? emulatorHost,
    String? mockUserToken,
    DatabasePersistence? persistence,
    DatabaseLogger? logger,
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting double Function()? random,
    @visibleForTesting Future<void> Function(Duration)? delay,
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
    DatabasePersistence? persistence,
    DatabaseLogger? logger,
    DateTime Function()? clock,
    double Function()? random,
  }) {
    _setUp(
      _Target.resolve(app),
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
    _connectionFactory = connectionFactory;
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
      _startRepo(null);
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
      manager = DefaultPersistenceManager(
        engine,
        LruCachePolicy(persistence.cacheSizeBytes),
        _clock ?? DateTime.now,
      );
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
    _startRepo(manager);
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
    if (_closed) {
      return;
    }
    final Repo? repo = _repo;
    if (repo != null && _queue.isEmpty) {
      op(repo);
    } else {
      _queue.add(op);
    }
  }

  FirebaseDatabaseException _closedError() => exceptionFromDatabaseError(
    const DatabaseError(
      DatabaseErrorCode.databaseClosed,
      'The FirebaseDatabase instance was closed.',
    ),
  );

  Future<T> _request<T>(void Function(Repo repo, _Pending<T> pending) start) {
    if (_closed) {
      return Future<T>.error(_closedError());
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
    if (_closed) {
      c
        ..addError(_closedError())
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

  /// The URL of the database.
  Uri get databaseUrl => _target.databaseUrl;

  /// The reference at [path]. `''`, `'a/b'` and `'/a/b'` are accepted and empty segments are dropped
  /// (`'a//b'` is `a/b`). The `.info` paths work too, for example `ref('.info/connected').onValue`, but
  /// writes under `.info` throw an [ArgumentError]. Makes no request, and still works after [close].
  DatabaseReference ref([String path = '']) {
    if (path.replaceAll('/', '').isNotEmpty) {
      validateRootPathString('ref', 'path', path);
    }
    return DatabaseReference.internal(this, QuerySpec.defaultAt(Path(path)));
  }

  /// The reference for a full [url] of this database (for example
  /// `https://my-project-default-rtdb.firebaseio.com/a/b`). Throws an [ArgumentError] when [url] names
  /// another database.
  DatabaseReference refFromUrl(String url) {
    final _ParsedUrl parsed = _ParsedUrl.parse(url);
    if (!_target.info.isUsingEmulator && parsed.host != _target.info.host) {
      throw ArgumentError(
        'refFromURL: Host name does not match the current database: '
        '(found ${parsed.host} but expected ${_target.info.host})',
      );
    }
    return ref(parsed.path);
  }

  /// Disconnects from the server and stays offline until [goOnline]. Writes stay queued and listeners
  /// keep their data. Synchronous and idempotent, valid before the first operation; a no-op after [close].
  void goOffline() => _withRepo((Repo repo) => repo.interrupt());

  /// Reconnects after [goOffline]. Synchronous and idempotent, valid before the first operation; a no-op
  /// after [close]. It does not undo a server kill: once the server has killed the connection the
  /// instance stays offline until it is recreated.
  void goOnline() => _withRepo((Repo repo) => repo.resume());

  /// Removes every pending local write, with events reverting them, fails their Futures with
  /// `write-canceled`, and aborts every running transaction with `write-canceled`.
  Future<void> purgeOutstandingWrites() =>
      _request<void>((Repo repo, _Pending<void> pending) {
        repo.purgeOutstandingWrites();
        pending.complete(null);
      });

  /// Whether the client is connected to the server (`.info/connected`). The first event is the current
  /// state.
  Stream<bool> get onConnected => ref(
    '.info/connected',
  ).onValue.map((DatabaseEvent event) => event.snapshot.value == true);

  /// The current value of [onConnected], synchronously.
  bool get isConnected => _infoValue('connected') == true;

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
  /// store is durable. It is false when another owner holds the cache file (after waiting one lease period
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
  /// Every open stream gets the error `database-closed` and ends, then every pending write Future fails with
  /// `database-closed`, then the returned Future completes. Afterwards every asynchronous call fails with
  /// `database-closed`, [ref] still works (it makes no request), and [goOnline] and [goOffline] do nothing.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    _queue.clear();
    final StreamSubscription<String>? deleteSubscription = _deleteSubscription;
    _deleteSubscription = null;
    final FirebaseDatabaseException error = _closedError();
    for (final _Listener listener in List<_Listener>.of(_listeners)) {
      listener.end(error);
    }
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
}

/// A [FirebaseDatabase] of [app] whose connection is built by [connectionFactory] (the testing
/// factories pass a fake server). The database URL comes from the app's options.
@internal
FirebaseDatabase firebaseDatabaseWithConnection(
  FirebaseApp app, {
  required ServerActionsFactory connectionFactory,
  DatabasePersistence? persistence,
  DatabaseLogger? logger,
  DateTime Function()? clock,
  double Function()? random,
}) => FirebaseDatabase._withConnection(
  app,
  connectionFactory: connectionFactory,
  persistence: persistence,
  logger: logger,
  clock: clock,
  random: random,
);

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

  /// Ends the stream with [error] then done; queued events of the registration are dropped.
  void end(Object error) {
    if (ended) {
      return;
    }
    ended = true;
    _owner.remove(this);
    registration.zombify();
    controller
      ..addErrorSync(error)
      ..closeSync();
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

/// The parts of a database URL. JS: `core/util/libs/parser.ts` (`parseDatabaseURL`, `parseRepoInfo`).
final class _ParsedUrl {
  _ParsedUrl(this.host, this.namespace, this.secure, this.path);

  factory _ParsedUrl.parse(String url) {
    final String withScheme = url.contains('://') ? url : 'https://$url';
    final Uri uri;
    try {
      uri = Uri.parse(withScheme);
    } on FormatException {
      throw ArgumentError.value(url, 'url', 'Cannot parse the database URL.');
    }
    if (uri.host.isEmpty) {
      throw ArgumentError.value(
        url,
        'url',
        'Cannot parse Firebase url. Please use https://<YOUR FIREBASE>.firebaseio.com',
      );
    }
    final String hostName = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final String host = uri.hasPort ? '$hostName:${uri.port}' : hostName;
    final String namespace =
        uri.queryParameters['ns'] ?? uri.host.split('.').first.toLowerCase();
    final bool secure = uri.scheme == 'https' || uri.scheme == 'wss';
    final String path = uri.pathSegments
        .where((String s) => s.isNotEmpty)
        .join('/');
    return _ParsedUrl(host, namespace, secure, path);
  }

  final String host;
  final String namespace;
  final bool secure;
  final String path;
}

/// Where an instance connects: its [RepoInfo] and public [databaseUrl].
final class _Target {
  _Target(this.info, this.databaseUrl);

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
    String? url = databaseUrl ?? app.options.databaseURL;
    if (url == null || url.isEmpty) {
      final String? projectId = app.options.projectId;
      if (projectId == null || projectId.isEmpty) {
        throw ArgumentError(
          "Can't determine Firebase Database URL. Be sure to include a Project ID "
          'or a databaseUrl.',
        );
      }
      url = 'https://$projectId-default-rtdb.firebaseio.com';
    }
    final _ParsedUrl parsed = _ParsedUrl.parse(url);
    if (emulatorHost != null) {
      if (emulatorHost.isEmpty) {
        throw ArgumentError.value(
          emulatorHost,
          'emulatorHost',
          'Must be host:port.',
        );
      }
      return _Target(
        RepoInfo(
          host: emulatorHost,
          namespace: parsed.namespace,
          secure: false,
          isUsingEmulator: true,
        ),
        Uri.parse(
          'http://$emulatorHost',
        ).replace(queryParameters: <String, String>{'ns': parsed.namespace}),
      );
    }
    return _Target(
      RepoInfo(
        host: parsed.host,
        namespace: parsed.namespace,
        secure: parsed.secure,
      ),
      Uri.parse('${parsed.secure ? 'https' : 'http'}://${parsed.host}'),
    );
  }

  final RepoInfo info;
  final Uri databaseUrl;
}
