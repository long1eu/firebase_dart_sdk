// The production verification kit of firebase_database_dart: a command line tool that checks,
// against a real Realtime Database, the behaviours the emulator cannot answer, plus a base line
// that runs on both.
//
//     dart run test/production/verify_production.dart --backend=production --create-user --yes
//     dart run test/production/verify_production.dart --backend=emulator --create-user
//
// See tool/verify_production_database/README.md (repository root) for the commands, the rules the
// database needs and how to read the report.
//
// The kit never reads or prints credentials. A throwaway user signs up with a random password that
// lives in memory only; its ID token is only handed to the client and to the kit's own REST calls,
// whose URLs are never printed. It writes only below one path that is unique to the run (and, for
// two checks, the user's own owner path and one refused path), and removes what it wrote.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:http/http.dart' as http;

import 'production_questions.dart';

/// The outcome of a check.
enum Status {
  /// The behaviour was observed and is what the client relies on, or the question the check asks
  /// was answered (the answer is in the summary).
  pass('PASS'),

  /// The client misbehaved, or the backend does something the client does not handle.
  fail('FAIL'),

  /// The check could not come to a result; the explanation says what to do.
  inconclusive('INCONCLUSIVE'),

  /// The check does not apply to this run.
  skipped('SKIPPED');

  const Status(this.label);

  /// The word printed in the report.
  final String label;
}

/// Where a check can tell something.
enum Scope {
  /// The check runs on both backends and its emulator result is pinned by the kit's test.
  both('emulator and production'),

  /// Only production can answer the question; on the emulator the check runs as a base line.
  production('production only');

  const Scope(this.label);

  /// The text printed by `--list`.
  final String label;
}

/// What one check found.
class CheckResult {
  /// A result with a [status] and a one-line [summary].
  CheckResult(
    this.status,
    this.summary, {
    this.details = const <String>[],
    this.observed = const <String, Object?>{},
  });

  /// The outcome.
  final Status status;

  /// One line: what was observed.
  final String summary;

  /// More lines for the report.
  final List<String> details;

  /// Machine-readable observations, asserted by the emulator test of the kit.
  final Map<String, Object?> observed;
}

/// One named check.
class Check {
  /// A check with the [id] used by `--only`.
  const Check(
    this.id,
    this.name,
    this.scope,
    this.run, {
    this.needsUser = true,
    this.wait = checkWait,
  });

  /// The id used with `--only`.
  final String id;

  /// What the check is about.
  final String name;

  /// Where the check can tell something.
  final Scope scope;

  /// Runs the check.
  final Future<CheckResult> Function(Kit kit) run;

  /// How long the whole check may take ([checkWait] unless it waits on purpose for many answers).
  final Duration wait;

  /// Whether the check needs the throwaway user (`--create-user`): the rules of the run's path
  /// refuse requests without one.
  final bool needsUser;
}

/// A wait of the kit that timed out; [what] names the wait.
class KitTimeout implements Exception {
  /// A timeout of the wait [what] after [after].
  KitTimeout(this.what, this.after);

  /// The wait that did not end.
  final String what;

  /// How long the kit waited.
  final Duration after;

  @override
  String toString() => 'timed out after ${after.inSeconds} s waiting for $what';
}

/// The variable naming the project id in production.
const String projectVariable = 'FIREBASE_TEST_PROJECT_ID';

/// The variable naming the database URL in production.
const String databaseUrlVariable = 'FIREBASE_TEST_DATABASE_URL';

/// The variable naming the app id sent with the connection.
const String appIdVariable = 'FIREBASE_TEST_APP_ID';

/// The variable holding the Web API key (needed by `--create-user` in production).
const String webApiKeyVariable = 'FIREBASE_API_KEY';

/// The variable naming the Database emulator.
const String emulatorHostVariable = 'FIREBASE_DATABASE_EMULATOR_HOST';

/// The variable naming the Auth emulator.
const String authEmulatorHostVariable = 'FIREBASE_AUTH_EMULATOR_HOST';

/// The namespace the kit uses on the emulator unless `--database-url` names another.
const String emulatorNamespace = 'verify-database-kit';

/// The top-level key below which every run writes.
const String kitRoot = 'verify_database_kit';

/// The top-level key of the owner rule (`auth.uid === $uid`).
const String ownerRoot = 'verify_database_kit_owner';

/// The top-level key that has no rule, so every request is refused.
const String deniedRoot = 'verify_database_kit_denied';

/// The rules the kit expects; `tool/verify_production_database/rules.json` holds the same (the
/// kit's test compares them). The emulator leg installs them on its namespace.
const Map<String, Object?> kitRules = <String, Object?>{
  'rules': <String, Object?>{
    '.read': false,
    '.write': false,
    kitRoot: <String, Object?>{
      r'$run': <String, Object?>{
        '.read': 'auth != null',
        '.write': 'auth != null',
        'indexed': <String, Object?>{
          '.indexOn': <String>['score'],
        },
        'values': <String, Object?>{'.indexOn': '.value'},
        'validated': <String, Object?>{
          r'$k': <String, Object?>{'.validate': 'newData.isNumber()'},
        },
        'leaf_rule': <String, Object?>{
          'a': <String, Object?>{'.validate': 'false'},
        },
      },
    },
    ownerRoot: <String, Object?>{
      r'$uid': <String, Object?>{
        '.read': r'auth.uid === $uid',
        '.write': r'auth.uid === $uid',
      },
    },
  },
};

/// The default wait for one network step.
const Duration stepWait = Duration(seconds: 20);

/// How long one check may run in total.
const Duration checkWait = Duration(minutes: 3);

/// Waits for [future] at most [timeout]; a timeout throws [KitTimeout] naming [what].
Future<T> within<T>(
  Future<T> future,
  String what, [
  Duration timeout = stepWait,
]) => future.timeout(timeout, onTimeout: () => throw KitTimeout(what, timeout));

/// Gives [future] a listener, so that an error it ends with when nobody awaits it any more (its
/// check gave up, its client was closed) is not an uncaught error. It can still be awaited.
void handled(Future<Object?> future) =>
    unawaited(future.then<void>((_) {}, onError: (Object _) {}));

/// Polls [test] every 10 ms until it holds; throws [KitTimeout] naming [what] after [timeout].
Future<void> until(
  bool Function() test,
  String what, [
  Duration timeout = stepWait,
]) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!test()) {
    if (watch.elapsed > timeout) {
      throw KitTimeout(what, timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Where the kit runs.
class Backend {
  /// A backend; [emulatorHost] is null in production.
  Backend({
    required this.production,
    required this.projectId,
    required this.databaseUrl,
    required this.emulatorHost,
    required this.authEmulatorHost,
    required this.appId,
    required this.apiKey,
  });

  /// Whether this is a real project.
  final bool production;

  /// The project id.
  final String projectId;

  /// The database URL given to the client.
  final String databaseUrl;

  /// The `host:port` of the Database emulator, null in production.
  final String? emulatorHost;

  /// The `host:port` of the Auth emulator, null in production.
  final String? authEmulatorHost;

  /// The app id of the app the kit creates.
  final String appId;

  /// The Web API key.
  final String apiKey;

  /// `production` or `emulator`.
  String get label => production ? 'production' : 'emulator';

  /// The namespace of the database (`ns`, else the first label of the host).
  String get namespace {
    final Uri url = Uri.parse(databaseUrl);
    return url.queryParameters['ns'] ?? url.host.split('.').first;
  }

  /// The REST URL of [path] with [query]; the namespace is in the query on the emulator.
  Uri rest(String path, Map<String, String> query) {
    final Uri url = Uri.parse(databaseUrl);
    final Uri base = production
        ? url
        : Uri.parse(
            'http://$emulatorHost',
          ).replace(queryParameters: <String, String>{'ns': namespace});
    return base.replace(
      path: '/$path.json',
      queryParameters: <String, String>{...base.queryParameters, ...query},
    );
  }
}

/// The log lines of one client, in memory only. Only the host of each connection attempt and the
/// presence of some warnings are ever printed.
class KitLog {
  /// Every line, `<level>: <message>`.
  final List<String> lines = <String>[];

  /// The client's logger callback.
  void add(DatabaseLogLevel level, String message) =>
      lines.add('${level.name}: $message');

  /// The host of every connection attempt, from the debug line `connecting to <host>`.
  List<String> get hosts => <String>[
    for (final String line in lines)
      if (line.startsWith('debug: connecting to '))
        line.substring('debug: connecting to '.length),
  ];

  /// How many lines contain [fragment].
  int count(String fragment) =>
      lines.where((String line) => line.contains(fragment)).length;
}

/// One client of the kit and its log.
class KitDb {
  /// A client [db] of the run whose path is [runPath].
  KitDb(this.db, this.log, this.runPath);

  /// The client.
  final FirebaseDatabase db;

  /// Its log.
  final KitLog log;

  /// The run's path.
  final String runPath;

  /// The reference at [relative] below the run's path.
  DatabaseReference ref(String relative) => db.ref('$runPath/$relative');

  /// Waits until `.info/connected` is true.
  Future<void> connected() => within(
    db.onConnected.firstWhere((bool c) => c),
    'the connection (.info/connected true)',
  );

  /// Waits until `.info/connected` is false.
  Future<void> disconnected() => within(
    db.onConnected.firstWhere((bool c) => !c),
    'the disconnect (.info/connected false)',
  );

  /// The value at [relative], read from the server (this client has no listener there).
  Future<Object?> read(String relative) async =>
      (await within(ref(relative).get(), 'get() of $relative')).value;
}

/// Collects the events and the error of one stream.
class Recorder<T> {
  /// Listens to [stream] at once.
  Recorder(Stream<T> stream) {
    _subscription = stream.listen(items.add, onError: (Object e) => error = e);
  }

  /// The events so far.
  final List<T> items = <T>[];

  /// The error that ended the stream, if any.
  Object? error;
  late final StreamSubscription<T> _subscription;

  /// Stops listening.
  Future<void> cancel() => _subscription.cancel();
}

/// The values of value events.
List<Object?> valuesOf(Recorder<DatabaseEvent> recorder) => <Object?>[
  for (final DatabaseEvent e in recorder.items) e.snapshot.value,
];

/// What a check works with: the run's path, the user, clients and REST.
class Kit {
  /// A kit for one run.
  Kit(
    this.backend,
    this.runId,
    this.auth,
    this.uid,
    this._password, {
    this.expectEmptiedNodeFix = false,
  }) : runPath = '$kitRoot/$runId';

  /// `--expect-emptied-node-fix`: checks 22 and 38 (c), (e), (f) decide. Without it they are
  /// informational, since a client without the emptied-node priority fix keeps the JS SDK's
  /// behaviour there.
  final bool expectEmptiedNodeFix;

  /// Where the kit runs.
  final Backend backend;

  /// `run_<utc>_<suffix>`.
  final String runId;

  /// The only place the kit writes, apart from the owner path and one refused write.
  final String runPath;

  /// The signed-in throwaway user, or null.
  final FirebaseUserAuth? auth;

  /// The uid of the user, or null.
  final String? uid;
  final String? _password;

  /// Whether check 16 wrote below the user's owner path.
  bool ownerWritten = false;

  /// Whether a write may still land after the clean-up (an onDisconnect the server had not run,
  /// a client that did not close in time, a check that timed out); the clean-up then waits and
  /// removes the run's path a second time.
  bool lateWritesPossible = false;

  /// Set when the clean-up starts: a check still running in the background can open no client.
  bool stopped = false;

  final List<OnDisconnect> _onDisconnects = <OnDisconnect>[];

  /// Remembers [ref]'s onDisconnect, so that [closeOpen] cancels it if the check did not end
  /// by firing it, and returns it.
  OnDisconnect onDisconnectOf(DatabaseReference ref) {
    final OnDisconnect operation = ref.onDisconnect;
    _onDisconnects.add(operation);
    return operation;
  }

  final List<FirebaseDatabase> _open = <FirebaseDatabase>[];
  final List<FirebaseUserAuth> _sessions = <FirebaseUserAuth>[];

  /// Called by [closeOpen]: closes what a check opened outside the kit (raw connections).
  final List<Future<void> Function()> closers = <Future<void> Function()>[];
  final http.Client _http = http.Client();
  int _apps = 0;

  /// The email of the throwaway user.
  String get email => 'database-verify-$runId@example.com';

  /// The owner path of the run: `verify_database_kit_owner/<uid>/<run>`.
  String get ownerPath => '$ownerRoot/$uid/$runId';

  /// The refused path of the run: `verify_database_kit_denied/<run>`.
  String get deniedPath => '$deniedRoot/$runId';

  FirebaseApp _newApp() => FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: backend.apiKey,
      appId: backend.appId,
      projectId: backend.projectId,
      databaseURL: backend.databaseUrl,
    ),
    name: 'verify-database-${runId}_${_apps++}',
  );

  KitDb _newDb(
    FirebaseApp app, {
    bool track = true,
    DatabasePersistence? persistence,
  }) {
    final KitLog log = KitLog();
    final FirebaseDatabase db = FirebaseDatabase(
      app,
      databaseUrl: backend.databaseUrl,
      emulatorHost: backend.emulatorHost,
      persistence: persistence,
      logger: log.add,
    );
    if (track) {
      _open.add(db);
    }
    return KitDb(db, log, runPath);
  }

  /// A new client with its own connection, signed in as the user unless [signedIn] is false.
  KitDb open({bool signedIn = true}) => _newDb(_app(signedIn: signedIn));

  FirebaseApp _app({required bool signedIn}) {
    if (stopped) {
      throw StateError('the clean-up has started; no new client');
    }
    final FirebaseApp app = _newApp();
    final FirebaseUserAuth? user = auth;
    if (signedIn && user != null) {
      app.authProvider = user;
    }
    return app;
  }

  /// A new app signed in as the user, for clients that share one app: two clients on one SQLite
  /// cache, one after the other, as an app restart (the cache file is named by the app).
  FirebaseApp signedInApp() => _app(signedIn: true);

  /// A new client on [app] (from [signedInApp]) with [persistence]; [closeOpen] closes it.
  KitDb openOn(FirebaseApp app, {DatabasePersistence? persistence}) =>
      _newDb(app, persistence: persistence);

  /// A client on a second session of the same user (its own `FirebaseUserAuth`), so that a
  /// sign-out leaves the kit's session alone.
  Future<({KitDb db, FirebaseUserAuth session})> openSecondSession() async {
    final FirebaseApp app = _newApp();
    final FirebaseUserAuth session = await FirebaseUserAuth.forApp(
      app,
      emulatorHost: backend.authEmulatorHost,
    );
    _sessions.add(session);
    await within(
      session.signInWithEmailAndPassword(email: email, password: _password!),
      'the sign-in of a second session',
    );
    return (db: _newDb(app), session: session);
  }

  /// A REST request as the user (`?auth=<ID token>`); the URL is never printed.
  Future<http.Response> rest(
    String method,
    String path, {
    Object? body,
    Map<String, String> query = const <String, String>{},
  }) async {
    final String token = (await auth!.getAccessToken(
      forceRefresh: false,
    )).token;
    final http.Request request = http.Request(
      method,
      backend.rest(path, <String, String>{...query, 'auth': token}),
    );
    if (body != null) {
      request.body = jsonEncode(body);
    }
    try {
      return await within(
        _http.send(request).then(http.Response.fromStream),
        'REST $method',
      );
    } on KitTimeout {
      rethrow;
    } on Object catch (e) {
      // The error of the HTTP client quotes the URL, which holds the token: only its type.
      throw StateError('REST $method failed (${e.runtimeType})');
    }
  }

  /// Closes every client and second session opened since the last call.
  Future<void> closeOpen() async {
    for (final OnDisconnect operation in _onDisconnects) {
      try {
        await operation.cancel().timeout(const Duration(seconds: 10));
      } on Object {
        // Its client is closed already (the check fired it) or does not answer; see below.
      }
    }
    _onDisconnects.clear();
    for (final FirebaseDatabase db in _open) {
      try {
        await db.close().timeout(const Duration(seconds: 10));
      } on Object {
        // A client that does not close in time may still fire an onDisconnect write.
        lateWritesPossible = true;
      }
    }
    _open.clear();
    for (final Future<void> Function() closer in closers) {
      await closer();
    }
    closers.clear();
    for (final FirebaseUserAuth session in _sessions) {
      await session.dispose();
    }
    _sessions.clear();
  }

  /// Removes the run's path and, when written, the owner path; returns the paths removed.
  Future<List<String>> cleanUp(StringSink sink) async {
    await closeOpen();
    stopped = true;
    // Not in the list closeOpen closes: a check abandoned by a signal or a timeout still runs and
    // closes the clients of the kit when it ends.
    final FirebaseApp app = _newApp();
    final FirebaseUserAuth? user = auth;
    if (user != null) {
      app.authProvider = user;
    }
    final KitDb db = _newDb(app, track: false);
    final List<String> removed = <String>[];
    if (auth == null) {
      // Without a user the rules refuse the removal, as they refused every write without one;
      // only an accepted write (a FAIL of check 15) left something to remove.
      final FirebaseDatabaseException? refused = await refusal(
        db.db.ref(runPath).remove(),
        'the removal of $runPath',
      );
      await db.db.close();
      return refused == null ? <String>[runPath] : <String>[];
    }
    try {
      await _removeRunPath(db);
      if (lateWritesPossible) {
        sink.writeln(
          'A write may still land (an onDisconnect or a client that did not close): waiting '
          '60 s and removing $runPath again.',
        );
        await Future<void>.delayed(const Duration(seconds: 60));
        await _removeRunPath(db);
      }
      removed.add(runPath);
      if (ownerWritten) {
        final FirebaseDatabaseException? refused = await refusal(
          db.db.ref(ownerPath).remove(),
          'the removal of $ownerPath',
        );
        if (refused == null) {
          removed.add(ownerPath);
        }
      }
    } finally {
      await db.db.close();
      await closeOpen();
    }
    return removed;
  }

  Future<void> _removeRunPath(KitDb db) async {
    await within(db.db.ref(runPath).remove(), 'the removal of $runPath');
    final DataSnapshot left = await within(
      db.db.ref(runPath).get(),
      'the read of $runPath after the removal',
    );
    if (left.exists) {
      throw StateError('$runPath still holds data after the removal');
    }
  }

  /// Closes the kit's HTTP client.
  void close() => _http.close();
}

String _clip(Object? value) {
  final String text = value is String ? value : jsonEncode(value);
  return text.length <= 160 ? text : '${text.substring(0, 160)}...';
}

/// A short description of [error] that never holds a token.
String describe(Object error) {
  if (error is FirebaseDatabaseException) {
    return '${error.code} (${error.serverStatus ?? 'no server status'})';
  }
  if (error is FirebaseAuthException) {
    return 'auth ${error.code}';
  }
  return '${error.runtimeType}: ${_clip('$error')}';
}

/// Null when [write] succeeds, else the [FirebaseDatabaseException] it failed with.
Future<FirebaseDatabaseException?> refusal(
  Future<void> write,
  String what,
) async {
  try {
    await within(write, what);
    return null;
  } on FirebaseDatabaseException catch (e) {
    return e;
  }
}

/// The observations of a refusal: code, message and server status.
Map<String, Object?> refusalFields(
  String prefix,
  FirebaseDatabaseException? e,
) => <String, Object?>{
  '${prefix}Code': e?.code,
  '${prefix}Message': e?.message,
  '${prefix}Status': e?.serverStatus,
};

/// `accepted`, or the refusal [e].
String outcome(FirebaseDatabaseException? e) =>
    e == null ? 'accepted' : 'refused: ${describe(e)}';

/// The code of [error] when it is a [FirebaseDatabaseException], else null.
String? codeOf(Object? error) =>
    error is FirebaseDatabaseException ? error.code : null;

/// The server status of [error] when it is a [FirebaseDatabaseException], else null.
String? statusOf(Object? error) =>
    error is FirebaseDatabaseException ? error.serverStatus : null;

/// The differences between [expected] and [actual], one line each, at most 5.
List<String> differences(Object? expected, Object? actual, [String at = '']) {
  if (expected is Map<String, Object?> && actual is Map<String, Object?>) {
    final List<String> found = <String>[];
    for (final String key in <String>{...expected.keys, ...actual.keys}) {
      found.addAll(differences(expected[key], actual[key], '$at/$key'));
    }
    return found.take(5).toList();
  }
  if (expected is List<Object?> && actual is List<Object?>) {
    if (expected.length != actual.length) {
      return <String>['$at: ${expected.length} items, got ${actual.length}'];
    }
    return <String>[
      for (int i = 0; i < expected.length; i++)
        ...differences(expected[i], actual[i], '$at/$i'),
    ].take(5).toList();
  }
  if (expected == actual) {
    return const <String>[];
  }
  final String shown = at.length > 60 ? '${at.substring(0, 60)}...' : at;
  return <String>['$shown: expected ${_clip(expected)}, got ${_clip(actual)}'];
}

// -----------------------------------------------------------------------------------------------
// Base line: connection, values, server values, listeners, queries.

Future<CheckResult> _connect(Kit kit) async {
  final Stopwatch watch = Stopwatch()..start();
  final KitDb a = kit.open();
  await a.connected();
  final int firstMs = watch.elapsedMilliseconds;
  a.db.goOffline();
  await a.disconnected();
  a.db.goOnline();
  await a.connected();
  final Uri url = a.db.databaseUrl;
  final List<String> hosts = a.log.hosts;
  final Set<String> other = <String>{
    for (final String host in hosts)
      if (host != url.host) host,
  };
  final bool tls = url.scheme == 'https';
  final Map<String, Object?> observed = <String, Object?>{
    'scheme': url.scheme,
    'hosts': hosts,
    'redirected': other.isNotEmpty,
    'firstConnectMs': firstMs,
  };
  if (kit.backend.production && !tls) {
    return CheckResult(
      Status.fail,
      'The database URL is not https: ${url.scheme}',
      observed: observed,
    );
  }
  final String transport = tls
      ? 'wss with TLS (certificate checked by dart:io)'
      : 'plain ws (the emulator)';
  final String redirect = other.isEmpty
      ? 'no connection went to another host'
      : 'the server named ${other.join(', ')} and the next connection went there';
  return CheckResult(
    Status.pass,
    '$transport to ${url.host}, connected in $firstMs ms; $redirect.',
    details: <String>[
      'connection attempts, in order: ${hosts.join(', ')}',
      'Read from the debug line "connecting to <host>". The host of the hello is used from the '
          'second connection on, so the kit reconnects once.',
    ],
    observed: observed,
  );
}

Future<CheckResult> _serverTime(Kit kit) async {
  final KitDb a = kit.open();
  await a.connected();
  final DatabaseEvent info = await within(
    a.db.ref('.info/serverTimeOffset').once(),
    '.info/serverTimeOffset',
  );
  final Object? value = info.snapshot.value;
  final int offset = a.db.serverTimeOffset.inMilliseconds;
  final bool plausible = value is num && offset.abs() < 5 * 60 * 1000;
  return CheckResult(
    plausible ? Status.pass : Status.fail,
    plausible
        ? 'The server clock is $offset ms from this machine (.info/serverTimeOffset $value).'
        : 'Implausible offset: .info/serverTimeOffset is $value, serverTimeOffset $offset ms '
              '(more than 5 minutes, or not a number).',
    observed: <String, Object?>{'offsetMs': offset, 'info': value},
  );
}

/// Every value type, written by one `set`.
Map<String, Object?> allTypes() {
  return <String, Object?>{
    'string': 'hello',
    'unicode': 'ünïcødé 😀 中文',
    'empty_string': '',
    'true': true,
    'false': false,
    'zero': 0,
    'negative': -42,
    'max_safe': 9007199254740991,
    'min_safe': -9007199254740991,
    'double': 3.14159,
    'small_double': 1.5e-10,
    'large_double': 1e300,
    'negative_double': -0.5,
    'list': <Object?>[
      1,
      'two',
      3.5,
      <String, Object?>{'four': 4},
    ],
    'nested': <String, Object?>{
      'a': <String, Object?>{
        'b': <String, Object?>{
          'c': <String, Object?>{'d': 'deep'},
        },
      },
    },
  };
}

/// The keys at the limits, each written by a `set` of its own below the same parent as
/// [allTypes]: a chain of maps as deep as a path may be (32 segments), punctuation, a non-ASCII
/// key and the longest key the parent allows (a 768-byte path).
Map<String, Object?> limitKeys(String parentPath) {
  final int longest = 768 - utf8.encode('/$parentPath').length - 1;
  final int levels = 32 - parentPath.split('/').length - 1;
  Object? deep = 'bottom';
  for (int i = 0; i < levels; i++) {
    deep = <String, Object?>{'d': deep};
  }
  return <String, Object?>{
    'deep': deep,
    "punctuation -_~!*()'@,;:+&= key": 'p',
    'ключ-ü-😀': 'non-ASCII key',
    'k' * longest: 'the longest key this path allows',
  };
}

Future<CheckResult> _valueTypes(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  final DatabaseReference ref = a.ref('types');
  final Map<String, Object?> limits = limitKeys('${kit.runPath}/types');
  final Map<String, Object?> value = <String, Object?>{
    ...allTypes(),
    ...limits,
  };
  String step = 'set';
  final Object? first;
  try {
    await within(ref.set(allTypes()), 'the set of every value type');
    for (final MapEntry<String, Object?> limit in limits.entries) {
      step = 'set of the key ${_clip(limit.key)}';
      await within(ref.child(limit.key).set(limit.value), 'the $step');
    }
    first = await b.read('types');
    step = 'update';
    await within(
      ref.update(<String, Object?>{
        'string': 'changed',
        'nested/a/b/c/d': 'updated',
        'zero': null,
        'added': 7,
      }),
      'the update',
    );
    step = 'remove';
    await within(ref.child('true').remove(), 'the remove');
  } on FirebaseDatabaseException catch (e) {
    // The limit keys are sized to the emulator's limits; production may count differently.
    final bool limit = step.startsWith('set of the key');
    return CheckResult(
      limit ? Status.inconclusive : Status.fail,
      'The $step was refused: ${describe(e)}'
      '${limit ? ' (the server\'s limit differs from the emulator\'s; an observation)' : ''}',
      observed: <String, Object?>{'refusedStep': step},
    );
  }
  final Map<String, Object?> expected = <String, Object?>{...value}
    ..['string'] = 'changed'
    ..['nested'] = <String, Object?>{
      'a': <String, Object?>{
        'b': <String, Object?>{
          'c': <String, Object?>{'d': 'updated'},
        },
      },
    }
    ..remove('zero')
    ..['added'] = 7
    ..remove('true');
  final List<String> setDiff = differences(value, first);
  final List<String> updateDiff = differences(expected, await b.read('types'));
  final Object? maxSafe = first is Map<String, Object?>
      ? first['max_safe']
      : null;
  final bool same = setDiff.isEmpty && updateDiff.isEmpty;
  final String oneSet = await _oneSet(a, kit.runPath);
  return CheckResult(
    same ? Status.pass : Status.fail,
    same
        ? 'A second client read back ${value.length} keys of every type (ints within 2^53 as '
              '${maxSafe.runtimeType}, a 768-byte path, 32 levels), then the update and remove.'
        : 'The value read back differs (${setDiff.length} after set, ${updateDiff.length} after '
              'update and remove).',
    details: <String>[
      ...setDiff,
      ...updateDiff,
      'all of it in one set (informational): $oneSet',
    ],
    observed: <String, Object?>{
      'setDifferences': setDiff.length,
      'updateDifferences': updateDiff.length,
      'maxSafeType': '${maxSafe.runtimeType}',
      'oneSet': oneSet,
    },
  );
}

/// Writes the types and the limit keys in one `set` below `types_one_set`; the emulator (v4.11.2)
/// refused that with `invalid_parameters` (path longer than 768 bytes) although each part alone
/// is accepted. Returns `accepted` or the refusal.
Future<String> _oneSet(KitDb a, String runPath) async {
  final Map<String, Object?> value = <String, Object?>{
    ...allTypes(),
    ...limitKeys('$runPath/types_one_set'),
  };
  final FirebaseDatabaseException? refused = await refusal(
    a.ref('types_one_set').set(value),
    'the set of everything at once',
  );
  return refused == null ? 'accepted' : 'refused, ${describe(refused)}';
}

Future<CheckResult> _timestamp(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  await a.connected();
  final Recorder<DatabaseEvent> local = Recorder<DatabaseEvent>(
    a.ref('time').onValue,
  );
  await until(() => local.items.isNotEmpty, 'the first value event');
  final int before = a.db.estimatedServerTime.millisecondsSinceEpoch;
  await within(a.ref('time').set(ServerValue.timestamp), 'the timestamp');
  final int after = a.db.estimatedServerTime.millisecondsSinceEpoch;
  final Object? value = await b.read('time');
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final List<Object?> events = valuesOf(local).skip(1).toList();
  if (value is! int) {
    return CheckResult(
      Status.fail,
      'The stored timestamp is not an int: ${_clip(value)}',
    );
  }
  const int slack = 2000;
  final bool inside = value >= before - slack && value <= after + slack;
  return CheckResult(
    inside ? Status.pass : Status.fail,
    inside
        ? 'The server wrote $value, ${value - before} ms after the estimate when the set started '
              '(the window was ${after - before} ms, plus $slack ms either side).'
        : 'The server wrote $value, outside $before..$after (estimated server time) by more than '
              '$slack ms.',
    details: <String>[
      'the writer\'s value events after the set: ${events.join(', ')} (the local estimate, then '
          'the server\'s value when it differs)',
    ],
    observed: <String, Object?>{
      'fromStartMs': value - before,
      'windowMs': after - before,
      'localEvents': events.length,
    },
  );
}

Future<CheckResult> _increment(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  final DatabaseReference count = a.ref('increment/count');
  await within(
    Future.wait(<Future<void>>[
      count.set(ServerValue.increment(1)),
      count.set(ServerValue.increment(1)),
    ]),
    'two increments',
  );
  final DatabaseReference half = a.ref('increment/half');
  await within(half.set(5), 'the set of 5');
  await within(half.set(ServerValue.increment(-2.5)), 'an increment of -2.5');
  final Object? counted = await b.read('increment/count');
  final Object? halved = await b.read('increment/half');
  final bool right = counted == 2 && halved == 2.5;
  return CheckResult(
    right ? Status.pass : Status.fail,
    right
        ? 'Two increments of 1 on a missing value gave 2, and 5 incremented by -2.5 gave 2.5.'
        : 'Expected 2 and 2.5, the server holds $counted and $halved.',
    observed: <String, Object?>{'count': counted, 'half': halved},
  );
}

Future<CheckResult> _pushKeys(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  final List<String> keys = <String>[];
  for (int i = 0; i < 20; i++) {
    final DatabaseReference ref = a.ref('pushed').push();
    keys.add(ref.key!);
    await within(ref.set(i), 'push number $i');
  }
  final DataSnapshot server = await within(
    b.ref('pushed').orderByKey().get(),
    'the pushed children',
  );
  final List<String> serverKeys = <String>[
    for (final DataSnapshot child in server.children) child.key!,
  ];
  final List<Object?> values = <Object?>[
    for (final DataSnapshot child in server.children) child.value,
  ];
  final List<String> sorted = <String>[...keys]..sort();
  final bool ordered =
      _sameList(sorted, keys) &&
      _sameList(serverKeys, keys) &&
      _sameList(values, List<int>.generate(20, (int i) => i)) &&
      keys.every((String k) => k.length == 20);
  return CheckResult(
    ordered ? Status.pass : Status.fail,
    ordered
        ? '20 push keys of 20 characters sort in the order they were made, on the server too.'
        : 'Push keys out of order: made ${keys.join(',')}, server ${serverKeys.join(',')}.',
    observed: <String, Object?>{'ordered': ordered},
  );
}

bool _sameList(List<Object?> a, List<Object?> b) =>
    a.length == b.length &&
    <int>[for (int i = 0; i < a.length; i++) i].every((int i) => a[i] == b[i]);

String _event(DatabaseEvent e) => e.type == DatabaseEventType.childRemoved
    ? '${e.type.name} ${e.snapshot.key}'
    : '${e.type.name} ${e.snapshot.key} after ${e.previousChildKey}';

Future<CheckResult> _listeners(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  final Recorder<DatabaseEvent> values = Recorder<DatabaseEvent>(
    a.ref('listen').onValue,
  );
  final Recorder<DatabaseEvent> children = Recorder<DatabaseEvent>(
    a.ref('listen').orderByChild('n').onChildEvents,
  );
  await until(() => values.items.isNotEmpty, 'the first value event');
  for (final String key in <String>['a', 'b', 'c']) {
    await within(
      b.ref('listen/$key').set(<String, Object?>{'n': 'abc'.indexOf(key) + 1}),
      'the write of $key',
    );
  }
  await within(b.ref('listen/a/n').set(4), 'the change of a');
  await within(b.ref('listen/b').remove(), 'the removal of b');
  const List<String> expected = <String>[
    'childAdded a after null',
    'childAdded b after a',
    'childAdded c after b',
    'childMoved a after c',
    'childChanged a after c',
    'childRemoved b',
  ];
  await until(
    () => children.items.length >= expected.length,
    'six child events',
  );
  final List<String> seen = children.items.map(_event).toList();
  final Map<String, Object?> last = <String, Object?>{
    'a': <String, Object?>{'n': 4},
    'c': <String, Object?>{'n': 3},
  };
  await until(
    () => differences(last, values.items.last.snapshot.value).isEmpty,
    'the last value event',
  );
  final bool same = _sameList(seen, expected);
  return CheckResult(
    same ? Status.pass : Status.fail,
    same
        ? 'Writes of a second client gave the six child events in order and '
              '${values.items.length} value events ending at the right value.'
        : 'Child events differ: ${seen.join('; ')}',
    details: <String>['expected: ${expected.join('; ')}'],
    observed: <String, Object?>{
      'events': seen,
      'valueEvents': values.items.length,
    },
  );
}

/// One child for a local query: its key and the value it is ordered by.
typedef Entry = ({String key, Object sort});

int _compare(Entry a, Entry b) {
  final int bySort = a.sort is num && b.sort is num
      ? (a.sort as num).compareTo(b.sort as num)
      : '${a.sort}'.compareTo('${b.sort}');
  return bySort != 0 ? bySort : a.key.compareTo(b.key);
}

int _compareSort(Object a, Object b) =>
    a is num && b is num ? a.compareTo(b) : '$a'.compareTo('$b');

/// The keys a query should return, computed here.
List<String> expectKeys(
  List<Entry> entries, {
  Object? start,
  bool startAfter = false,
  Object? end,
  bool endBefore = false,
  int? first,
  int? last,
}) {
  final List<Entry> sorted = <Entry>[...entries]..sort(_compare);
  final List<Entry> inRange = sorted.where((Entry e) {
    final int fromStart = start == null ? 1 : _compareSort(e.sort, start);
    final int toEnd = end == null ? -1 : _compareSort(e.sort, end);
    return (startAfter ? fromStart > 0 : fromStart >= 0) &&
        (endBefore ? toEnd < 0 : toEnd <= 0);
  }).toList();
  final Iterable<Entry> limited = first != null
      ? inRange.take(first)
      : last != null
      ? inRange.skip(math.max(0, inRange.length - last))
      : inRange;
  return <String>[for (final Entry e in limited) e.key];
}

List<String> _keysOf(DataSnapshot snapshot) => <String>[
  for (final DataSnapshot child in snapshot.children) child.key!,
];

/// The cases of check 8: a name, the query and the keys it should return.
List<({String name, Query query, List<String> expected})> queryCases(
  KitDb db,
  List<Entry> scores,
  List<Entry> values,
) {
  final Query byScore = db.ref('indexed').orderByChild('score');
  final Query byKey = db.ref('indexed').orderByKey();
  final Query byValue = db.ref('values').orderByValue();
  final List<Entry> keys = <Entry>[
    for (final Entry e in scores) (key: e.key, sort: e.key),
  ];
  return <({String name, Query query, List<String> expected})>[
    (
      name: 'orderByChild(score).startAt(3).endAt(6)',
      query: byScore.startAt(3).endAt(6),
      expected: expectKeys(scores, start: 3, end: 6),
    ),
    (
      name: 'orderByChild(score).limitToFirst(4)',
      query: byScore.limitToFirst(4),
      expected: expectKeys(scores, first: 4),
    ),
    (
      name: 'orderByChild(score).limitToLast(4)',
      query: byScore.limitToLast(4),
      expected: expectKeys(scores, last: 4),
    ),
    (
      name: 'orderByChild(score).equalTo(7)',
      query: byScore.equalTo(7),
      expected: expectKeys(scores, start: 7, end: 7),
    ),
    (
      name: 'orderByChild(score).startAfter(2).limitToFirst(3)',
      query: byScore.startAfter(2).limitToFirst(3),
      expected: expectKeys(scores, start: 2, startAfter: true, first: 3),
    ),
    (
      name: 'orderByKey().startAt(p03).endAt(p07)',
      query: byKey.startAt('p03').endAt('p07'),
      expected: expectKeys(keys, start: 'p03', end: 'p07'),
    ),
    (
      name: 'orderByKey().limitToLast(3)',
      query: byKey.limitToLast(3),
      expected: expectKeys(keys, last: 3),
    ),
    (
      name: 'orderByValue().startAt(20).endAt(60)',
      query: byValue.startAt(20).endAt(60),
      expected: expectKeys(values, start: 20, end: 60),
    ),
    (
      name: 'orderByValue().endBefore(50).limitToLast(2)',
      query: byValue.endBefore(50).limitToLast(2),
      expected: expectKeys(values, end: 50, endBefore: true, last: 2),
    ),
  ];
}

Future<CheckResult> _queries(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  final List<Entry> scores = <Entry>[
    for (int i = 0; i < 15; i++)
      (key: 'p${i.toString().padLeft(2, '0')}', sort: (i * 7) % 10),
  ];
  final List<Entry> values = <Entry>[
    for (int i = 0; i < 12; i++)
      (key: 'v${i.toString().padLeft(2, '0')}', sort: (i * 37) % 100),
  ];
  await within(
    a.ref('indexed').set(<String, Object?>{
      for (final Entry e in scores)
        e.key: <String, Object?>{'score': e.sort, 'name': 'player ${e.key}'},
    }),
    'the indexed data',
  );
  await within(
    a.ref('values').set(<String, Object?>{
      for (final Entry e in values) e.key: e.sort,
    }),
    'the values',
  );
  final List<String> wrong = <String>[];
  final List<({String name, Query query, List<String> expected})> cases =
      queryCases(b, scores, values);
  for (final (:String name, :Query query, :List<String> expected) in cases) {
    final List<String> got = _keysOf(await within(query.get(), 'get() $name'));
    final List<String> heard = _keysOf(
      (await within(query.once(), 'once() $name')).snapshot,
    );
    if (!_sameList(got, expected) || !_sameList(heard, expected)) {
      wrong.add(
        '$name: expected ${expected.join(',')}, get() ${got.join(',')}, '
        'once() ${heard.join(',')}',
      );
    }
  }
  return CheckResult(
    wrong.isEmpty ? Status.pass : Status.fail,
    wrong.isEmpty
        ? '${cases.length} queries, each by get() (server, with the declared indexes) and once(), '
              'match the order and window computed here.'
        : '${wrong.length} of ${cases.length} queries differ from the local expectation.',
    details: wrong,
    observed: <String, Object?>{'cases': cases.length, 'wrong': wrong.length},
  );
}

Future<CheckResult> _undeclaredIndex(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  final List<Entry> entries = <Entry>[
    for (int i = 0; i < 8; i++) (key: 'u$i', sort: (i * 3) % 7),
  ];
  await within(
    a.ref('unindexed').set(<String, Object?>{
      for (final Entry e in entries) e.key: <String, Object?>{'other': e.sort},
    }),
    'the unindexed data',
  );
  final Query query = b.ref('unindexed').orderByChild('other').limitToFirst(3);
  final List<String> expected = expectKeys(entries, first: 3);
  String getAnswer;
  try {
    getAnswer = _keysOf(await within(query.get(), 'get()')).join(',');
  } on FirebaseDatabaseException catch (e) {
    getAnswer = e.code;
  }
  final List<String> heard = _keysOf(
    (await within(query.once(), 'once()')).snapshot,
  );
  // The warning comes with the listen's answer, which can follow the data that ended once().
  bool warned = true;
  try {
    await until(
      () => b.log.count('Using an unspecified index') > 0,
      'the no_index warning',
      const Duration(seconds: 3),
    );
  } on KitTimeout {
    warned = false;
  }
  final bool right = _sameList(heard, expected);
  return CheckResult(
    right ? Status.pass : Status.fail,
    right
        ? 'once() without an index matches (${heard.join(',')}); the no_index warning was '
              '${warned ? '' : 'NOT '}sent; a filtered get() answered $getAnswer.'
        : 'once() without an index returned ${heard.join(',')}, expected ${expected.join(',')}.',
    observed: <String, Object?>{'warning': warned, 'get': getAnswer},
  );
}

// -----------------------------------------------------------------------------------------------
// Transactions, onDisconnect, offline.

Future<CheckResult> _transactionConflict(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  await within(b.ref('tx').set(10), "the second client's write");
  final List<Object?> seen = <Object?>[];
  final TransactionResult result = await within(
    a.ref('tx').runTransaction((Object? current) {
      seen.add(current);
      return Transaction.success(current == null ? 1 : (current as num) + 1);
    }),
    'the transaction',
  );
  final Object? server = await b.read('tx');
  final bool right =
      result.committed && result.snapshot.value == 11 && server == 11;
  return CheckResult(
    right ? Status.pass : Status.fail,
    right
        ? 'Committed 11 after ${seen.length} runs of the handler (it saw ${seen.join(', ')}); '
              'the server held 10 from the second client.'
        : 'committed ${result.committed}, value ${result.snapshot.value}, server $server, '
              'runs saw ${seen.join(', ')}',
    observed: <String, Object?>{'runs': seen.length, 'value': server},
  );
}

Future<CheckResult> _transactionAbort(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  await within(b.ref('tx_abort').set(11), "the second client's write");
  final Recorder<DatabaseEvent> listen = Recorder<DatabaseEvent>(
    a.ref('tx_abort').onValue,
  );
  await until(
    () => valuesOf(listen).contains(11),
    'the value 11 at the writer',
  );
  final TransactionResult result = await within(
    a.ref('tx_abort').runTransaction((Object? current) {
      return const Transaction.abort();
    }),
    'the transaction',
  );
  final Object? server = await b.read('tx_abort');
  final bool right =
      !result.committed && result.snapshot.value == 11 && server == 11;
  return CheckResult(
    right ? Status.pass : Status.fail,
    right
        ? 'The abort completed with committed: false and the value 11; the server kept 11.'
        : 'committed ${result.committed}, snapshot ${result.snapshot.value}, server $server',
    observed: <String, Object?>{'committed': result.committed},
  );
}

Future<CheckResult> _onDisconnect(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  DatabaseReference at(String key) => a.ref('presence/$key');
  await within(kit.onDisconnectOf(at('a')).set('gone'), 'onDisconnect.set');
  await within(
    kit.onDisconnectOf(at('b')).set('gone'),
    'onDisconnect.set of b',
  );
  await within(kit.onDisconnectOf(at('b')).cancel(), 'onDisconnect.cancel');
  await within(kit.onDisconnectOf(at('c')).remove(), 'onDisconnect.remove');
  await within(
    kit.onDisconnectOf(at('d')).update(<String, Object?>{'state': 'offline'}),
    'onDisconnect.update',
  );
  for (final String key in <String>['a', 'b', 'c']) {
    await within(at(key).set('here'), 'the write of $key');
  }
  await within(
    at('d').set(<String, Object?>{'state': 'online', 'x': 1}),
    'the write of d',
  );
  final Recorder<DatabaseEvent> seen = Recorder<DatabaseEvent>(
    b.ref('presence').onValue,
  );
  await until(
    () => seen.items.isNotEmpty && seen.items.last.snapshot.childrenCount == 4,
    'the four children at the observer',
  );
  final Stopwatch watch = Stopwatch()..start();
  await within(a.db.close(), 'the close of the first client');
  const Map<String, Object?> expected = <String, Object?>{
    'a': 'gone',
    'b': 'here',
    'd': <String, Object?>{'state': 'offline', 'x': 1},
  };
  try {
    await until(
      () => differences(expected, seen.items.last.snapshot.value).isEmpty,
      'the onDisconnect writes at the observer',
    );
  } on KitTimeout {
    return CheckResult(
      Status.fail,
      'The observer holds ${_clip(seen.items.last.snapshot.value)} 20 s after the close; '
      'expected ${_clip(expected)}.',
    );
  }
  return CheckResult(
    Status.pass,
    'After the close a second client saw set, remove and update fire and the cancelled one '
    'not, ${watch.elapsedMilliseconds} ms after the close.',
    observed: <String, Object?>{'afterCloseMs': watch.elapsedMilliseconds},
  );
}

Future<CheckResult> _queuedOffline(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  final KitDb c = kit.open();
  final Recorder<DatabaseEvent> root = Recorder<DatabaseEvent>(
    b.ref('queue').onValue,
  );
  final Recorder<DatabaseEvent> added = Recorder<DatabaseEvent>(
    b.ref('queue/items').onChildAdded,
  );
  await until(() => root.items.isNotEmpty, 'the observer');
  await a.connected();
  a.db.goOffline();
  await a.disconnected();
  final Future<void> push = a.ref('queue/items').push().set('written offline');
  final Future<void> count = a.ref('queue/count').set(ServerValue.increment(1));
  a.db.goOnline();
  await within(
    Future.wait(<Future<void>>[push, count]),
    'the acknowledgement of the queued writes',
  );
  await until(() => added.items.isNotEmpty, 'the child at the observer');
  await Future<void>.delayed(const Duration(seconds: 2));
  final Object? counted = await c.read('queue/count');
  final DataSnapshot items = await within(
    c.ref('queue/items').get(),
    'the items',
  );
  final bool once =
      added.items.length == 1 && counted == 1 && items.childrenCount == 1;
  return CheckResult(
    once ? Status.pass : Status.fail,
    once
        ? 'A push and an increment queued offline were delivered once after goOnline.'
        : 'Observer saw ${added.items.length} children, count $counted, '
              '${items.childrenCount} items on the server.',
    observed: <String, Object?>{'added': added.items.length, 'count': counted},
  );
}

Future<CheckResult> _keepSynced(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  const Map<String, Object?> value = <String, Object?>{
    'x': 1,
    'y': 'two',
    'z': <String, Object?>{'w': true},
  };
  await within(b.ref('synced').set(value), 'the data');
  await within(a.ref('synced').keepSynced(true), 'keepSynced(true)');
  await within(a.ref('synced').once(), 'the first value');
  a.db.goOffline();
  await a.disconnected();
  final Stopwatch watch = Stopwatch()..start();
  final DataSnapshot cached;
  try {
    cached = await within(a.ref('synced').get(), 'get() while offline');
  } on FirebaseDatabaseException catch (e) {
    return CheckResult(
      Status.fail,
      'get() while offline failed with ${describe(e)} although keepSynced held the value.',
    );
  }
  final int ms = watch.elapsedMilliseconds;
  await within(a.ref('synced').keepSynced(false), 'keepSynced(false)');
  a.db.goOnline();
  final List<String> diff = differences(value, cached.value);
  return CheckResult(
    diff.isEmpty ? Status.pass : Status.fail,
    diff.isEmpty
        ? 'Offline, get() answered from the complete cache after $ms ms.'
        : 'Offline get() answered a different value.',
    details: diff,
    observed: <String, Object?>{'offlineGetMs': ms},
  );
}

// -----------------------------------------------------------------------------------------------
// Auth and rules.

Future<CheckResult> _withoutUser(Kit kit) async {
  final KitDb none = kit.open(signedIn: false);
  final FirebaseDatabaseException? anonymous = await refusal(
    none.ref('nouser').set(1),
    'the write without a user',
  );
  FirebaseDatabaseException? asUser;
  KitDb writer = none;
  if (kit.auth != null) {
    writer = kit.open();
    asUser = await refusal(writer.ref('withuser').set(1), 'the user write');
  }
  final FirebaseDatabaseException? denied = await refusal(
    writer.db.ref(kit.deniedPath).set(1),
    'the write at $deniedRoot',
  );
  if (denied == null) {
    await within(writer.db.ref(kit.deniedPath).remove(), 'the removal');
  }
  final bool userAccepted = writer != none && asUser == null;
  final bool right =
      anonymous?.code == 'permission-denied' &&
      asUser == null &&
      denied?.code == 'permission-denied';
  return CheckResult(
    right ? Status.pass : Status.fail,
    'Without a user the write was ${outcome(anonymous)}; as the user '
    '${writer == none ? 'not tried (--create-user)' : outcome(asUser)}; at $deniedRoot '
    '${outcome(denied)}.',
    details: <String>['message without a user: ${anonymous?.message}'],
    observed: <String, Object?>{
      ...refusalFields('anonymous', anonymous),
      ...refusalFields('denied', denied),
      'userAccepted': userAccepted,
    },
  );
}

Future<CheckResult> _owner(Kit kit) async {
  final KitDb a = kit.open();
  kit.ownerWritten = true;
  final FirebaseDatabaseException? own = await refusal(
    a.db.ref(kit.ownerPath).set(<String, Object?>{'ok': true}),
    'the write below the own uid',
  );
  final String other = '$ownerRoot/not-${kit.uid}/${kit.runId}';
  final FirebaseDatabaseException? foreign = await refusal(
    a.db.ref(other).set(1),
    'the write below another uid',
  );
  if (foreign == null) {
    await within(a.db.ref(other).remove(), 'the removal');
  }
  final bool right = own == null && foreign?.code == 'permission-denied';
  return CheckResult(
    right ? Status.pass : Status.fail,
    right
        ? 'The owner rule accepted the own uid and refused another: ${describe(foreign!)}.'
        : 'own uid: ${own == null ? 'accepted' : describe(own)}; another uid: '
              '${foreign == null ? 'ACCEPTED (removed again)' : describe(foreign)}',
    observed: refusalFields('foreign', foreign),
  );
}

Future<CheckResult> _validate(Kit kit) async {
  final KitDb a = kit.open();
  final DatabaseReference ref = a.ref('validated/k');
  final Recorder<DatabaseEvent> seen = Recorder<DatabaseEvent>(ref.onValue);
  await until(() => seen.items.isNotEmpty, 'the first value event');
  await within(ref.set(5), 'the write of 5');
  final FirebaseDatabaseException? refused = await refusal(
    ref.set('not-a-number'),
    'the refused write',
  );
  await until(() => valuesOf(seen).last == 5, 'the listener to return to 5');
  final List<Object?> values = valuesOf(seen);
  final bool showed = values.contains('not-a-number');
  final Object? server = await kit.open().read('validated/k');
  final bool right =
      refused?.code == 'permission-denied' && showed && server == 5;
  return CheckResult(
    right ? Status.pass : Status.fail,
    right
        ? 'The .validate refusal (${describe(refused!)}) reverted the local value: the listener '
              'saw ${values.map(_clip).join(', ')}.'
        : 'refusal: ${refused == null ? 'none' : describe(refused)}; listener: '
              '${values.map(_clip).join(', ')}; server: $server',
    observed: <String, Object?>{
      'values': values,
      ...refusalFields('validate', refused),
    },
  );
}

Future<CheckResult> _tokenRefresh(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  final Recorder<DatabaseEvent> seen = Recorder<DatabaseEvent>(
    a.ref('refresh').onValue,
  );
  await a.connected();
  await until(() => seen.items.isNotEmpty, 'the first value event');
  final Recorder<bool> connection = Recorder<bool>(a.db.onConnected);
  final int authSends = a.log.count('auth (contents hidden)');
  final int attempts = a.log.hosts.length;
  await within(
    kit.auth!.getAccessToken(forceRefresh: true),
    'the forced refresh of the ID token',
  );
  try {
    await until(
      () => a.log.count('auth (contents hidden)') > authSends,
      'the client to send the new token',
    );
  } on KitTimeout {
    return CheckResult(
      Status.fail,
      'The client did not send the refreshed token within 20 s.',
    );
  }
  await within(b.ref('refresh').set('after refresh'), 'the write by B');
  await until(
    () => valuesOf(seen).contains('after refresh'),
    'the listener to see the write after the refresh',
  );
  await within(a.ref('refresh_own').set(1), 'a write after the refresh');
  final bool dropped =
      connection.items.contains(false) || a.log.hosts.length != attempts;
  return CheckResult(
    Status.pass,
    dropped
        ? 'The connection DROPPED after the refresh (${a.log.hosts.length - attempts} new '
              'connection attempts), and listening and writing went on after it.'
        : 'A forced refresh sent the new token on the live connection; no disconnect, and '
              'listening and writing went on.',
    observed: <String, Object?>{'dropped': dropped},
  );
}

Future<CheckResult> _signOut(Kit kit) async {
  final KitDb b = kit.open();
  final ({KitDb db, FirebaseUserAuth session}) second = await kit
      .openSecondSession();
  await within(b.ref('signout').set(1), 'the data');
  final Recorder<DatabaseEvent> seen = Recorder<DatabaseEvent>(
    second.db.ref('signout').onValue,
  );
  await until(() => seen.items.isNotEmpty, 'the first value event');
  await within(second.session.signOut(), 'the sign-out');
  bool cancelled = true;
  try {
    await until(() => seen.error != null, 'the cancel of the listener');
  } on KitTimeout {
    cancelled = false;
  }
  final FirebaseDatabaseException? write = await refusal(
    second.db.ref('signout_after').set(1),
    'a write after the sign-out',
  );
  final Object? error = seen.error;
  final bool right =
      codeOf(error) == 'permission-denied' &&
      write?.code == 'permission-denied';
  final Status status = right
      ? Status.pass
      : (cancelled ? Status.fail : Status.inconclusive);
  return CheckResult(
    status,
    'After the sign-out the listener was '
    '${cancelled ? 'cancelled with ${describe(error!)}' : 'not cancelled within 20 s'}; '
    'a write was ${outcome(write)}.',
    observed: <String, Object?>{
      'cancel': codeOf(error),
      'cancelStatus': statusOf(error),
      'writeCode': write?.code,
    },
  );
}

Future<CheckResult> _deniedListener(Kit kit) async {
  final KitDb a = kit.open(signedIn: kit.auth != null);
  final Recorder<DatabaseEvent> seen = Recorder<DatabaseEvent>(
    a.db.ref(kit.deniedPath).onValue,
  );
  await until(() => seen.error != null, 'the cancel event');
  FirebaseDatabaseException? got;
  try {
    await within(a.db.ref(kit.deniedPath).get(), 'get() at $deniedRoot');
  } on FirebaseDatabaseException catch (e) {
    got = e;
  }
  final Object error = seen.error!;
  final bool right =
      codeOf(error) == 'permission-denied' && got?.code == 'permission-denied';
  return CheckResult(
    right ? Status.pass : Status.fail,
    'A listener at $deniedRoot was cancelled with ${describe(error)}; get() was '
    '${got == null ? 'ANSWERED' : 'refused: ${describe(got)}'}.',
    observed: <String, Object?>{
      'cancel': codeOf(error),
      'cancelStatus': statusOf(error),
      'getCode': got?.code,
    },
  );
}

// -----------------------------------------------------------------------------------------------
// Protocol questions: priorities and a write below a primitive.

/// Whether a REST export shows a priority at its top level.
bool hasPriority(String export) {
  try {
    final Object? json = jsonDecode(export);
    return json is Map<String, Object?> && json.containsKey('.priority');
  } on FormatException {
    return false;
  }
}

Future<CheckResult> _priorityRest(Kit kit) async {
  final String r = '${kit.runPath}/priority_rest';
  final List<String> steps = <String>[];
  final List<String> exports = <String>[];
  Future<void> step(
    String label,
    String method,
    String path,
    Object? body,
  ) async {
    final http.Response response = await kit.rest(method, path, body: body);
    steps.add('$label: HTTP ${response.statusCode}');
    final http.Response export = await kit.rest(
      'GET',
      r,
      query: const <String, String>{'format': 'export'},
    );
    steps.add('GET r.json?format=export: HTTP ${export.statusCode}');
    exports.add(export.body);
  }

  await step('PUT r {"a":1,".priority":0}', 'PUT', r, <String, Object?>{
    'a': 1,
    '.priority': 0,
  });
  await step('DELETE r/a', 'DELETE', '$r/a', null);
  await step('PUT r/b 1', 'PUT', '$r/b', 1);
  final bool worked = steps.every((String s) => s.contains('HTTP 200'));
  final bool kept = hasPriority(exports.last);
  return CheckResult(
    worked ? Status.pass : Status.fail,
    worked
        ? 'After DELETE r/a and PUT r/b the priority was ${kept ? 'KEPT' : 'DROPPED'}: '
              '${exports.join(' -> ')}'
        : 'A REST call failed: ${steps.join('; ')}',
    details: <String>[
      ...steps,
      'export after PUT r: ${exports[0]}',
      'export after DELETE r/a: ${exports[1]}',
      'export after PUT r/b: ${exports[2]}',
    ],
    observed: <String, Object?>{'exports': exports, 'kept': kept},
  );
}

Future<CheckResult> _priorityClient(Kit kit) async {
  final KitDb a = kit.open();
  final DatabaseReference r = a.ref('priority_client/r');
  final Recorder<DatabaseEvent> writer = Recorder<DatabaseEvent>(r.onValue);
  await until(() => writer.items.isNotEmpty, 'the first value event');
  await within(
    r.set(<String, Object?>{'a': 1}, priority: 0),
    'set with a priority',
  );
  await within(r.child('a').remove(), 'the removal of r/a');
  await within(r.child('b').set(1), 'the write of r/b');
  await until(
    () => differences(<String, Object?>{'b': 1}, valuesOf(writer).last).isEmpty,
    'the writer to see {b: 1}',
  );
  final DataSnapshot twoWrites = await within(
    kit.open().ref('priority_client/r').get(),
    'a fresh read of r',
  );
  final DatabaseReference r2 = a.ref('priority_client/r2');
  final Recorder<DatabaseEvent> writer2 = Recorder<DatabaseEvent>(r2.onValue);
  await until(() => writer2.items.isNotEmpty, 'the first value event of r2');
  await within(r2.set(<String, Object?>{'a': 1}, priority: 0), 'set of r2');
  await within(
    r2.update(<String, Object?>{'a': null, 'b': 1}),
    'the update of r2',
  );
  final Stopwatch sinceUpdate = Stopwatch()..start();
  final DataSnapshot oneUpdate = await within(
    kit.open().ref('priority_client/r2').get(),
    'a fresh read of r2',
  );
  final List<({int at, Object? listener, Object? own})> update =
      <({int at, Object? listener, Object? own})>[];
  for (final int at in checkpointsMs) {
    await reach(sinceUpdate, at);
    final DataSnapshot own = await within(
      r2.get(),
      'get() of r2 by the writer',
    );
    update.add((
      at: at,
      listener: writer2.items.last.snapshot.priority,
      own: own.priority,
    ));
  }
  final Object? writerPriority = writer.items.last.snapshot.priority;
  // Deciding with --expect-emptied-node-fix: in the update form the writer's listener and its
  // get() show at the last checkpoint the priority a fresh client reads.
  final bool writerRight =
      update.last.listener == oneUpdate.priority &&
      update.last.own == oneUpdate.priority;
  final String verdict = kit.expectEmptiedNodeFix
      ? ''
      : writerRight
      ? ' Informational (no --expect-emptied-node-fix).'
      : ' Informational (no --expect-emptied-node-fix): the client keeps the JS SDK\'s '
            'behaviour here, it drops the priority of a node emptied by its own write.';
  return CheckResult(
    writerRight || !kit.expectEmptiedNodeFix ? Status.pass : Status.fail,
    'Priority read by a fresh client: after two writes ${twoWrites.priority}, after one '
    'update ${oneUpdate.priority}; the writer\'s listener shows $writerPriority after two '
    'writes, ${update.last.listener} after one update (get() ${update.last.own}, at '
    '+${update.last.at ~/ 1000} s); after one update the writer '
    '${writerRight ? 'matches' : 'DIFFERS FROM'} the fresh client.$verdict',
    details: <String>[
      'two writes: value ${_clip(twoWrites.value)}, priority ${twoWrites.priority}',
      'one update: value ${_clip(oneUpdate.value)}, priority ${oneUpdate.priority}',
      for (final ({int at, Object? listener, Object? own}) row in update)
        'one update, the writer at +${row.at ~/ 1000} s: listener priority '
            '${row.listener}, get() priority ${row.own}',
      'one update, the writer\'s listener values: '
          '${writer2.items.map((DatabaseEvent e) => '${_clip(e.snapshot.value)} '
              '(priority ${e.snapshot.priority})').join(', ')}',
    ],
    observed: <String, Object?>{
      'twoWrites': twoWrites.priority,
      'oneUpdate': oneUpdate.priority,
      'writer': writerPriority,
      'writerUpdateListener': <Object?>[
        for (final ({int at, Object? listener, Object? own}) row in update)
          row.listener,
      ],
      'writerUpdateGet': <Object?>[
        for (final ({int at, Object? listener, Object? own}) row in update)
          row.own,
      ],
    },
  );
}

/// The checkpoints, in milliseconds after the last write, at which checks 22 and 30 read the
/// writer's listener, its get() and the server.
const List<int> checkpointsMs = <int>[0, 5000];

/// Waits until [watch] reaches [ms] milliseconds.
Future<void> reach(Stopwatch watch, int ms) async {
  final int left = ms - watch.elapsedMilliseconds;
  if (left > 0) {
    await Future<void>.delayed(Duration(milliseconds: left));
  }
}

Future<CheckResult> _belowPrimitive(Kit kit) async {
  final KitDb a = kit.open();
  final KitDb b = kit.open();
  await within(b.ref('primitive').set(1), 'the primitive 1');
  final DatabaseReference r = a.ref('primitive');
  final Recorder<DatabaseEvent> seen = Recorder<DatabaseEvent>(r.onValue);
  await until(() => valuesOf(seen).contains(1), 'the listener to see 1');
  a.db.goOffline();
  await a.disconnected();
  final Future<void> first = r.child('c').set(<String, Object?>{'v': 1});
  final Future<void> second = r.child('c').set(null);
  a.db.goOnline();
  await within(
    Future.wait(<Future<void>>[first, second]),
    'the acknowledgement of both writes',
  );
  await Future<void>.delayed(const Duration(seconds: 1));
  final Object? listener = valuesOf(seen).last;
  final Object? own = (await within(r.get(), 'get() by the writer')).value;
  final Object? fresh = await kit.open().read('primitive');
  final bool right = listener == null && own == null && fresh == null;
  return CheckResult(
    right ? Status.pass : Status.fail,
    right
        ? 'The listener, get() and a fresh client all end at null.'
        : 'listener ${_clip(listener)}, get() ${_clip(own)}, fresh client ${_clip(fresh)}',
    details: <String>[
      'listener values: ${valuesOf(seen).map(_clip).join(', ')}',
    ],
    observed: <String, Object?>{
      'listener': listener,
      'get': own,
      'fresh': fresh,
    },
  );
}

// -----------------------------------------------------------------------------------------------
// Timing, informational.

Future<CheckResult> _coldConnect(Kit kit) async {
  await within(kit.open().ref('timing').set('x'), 'the data');
  await kit.closeOpen();
  final Stopwatch watch = Stopwatch()..start();
  final KitDb c = kit.open();
  final Future<void> connected = c.connected();
  handled(connected);
  await within(c.ref('timing').onValue.first, 'the first value');
  final int value = watch.elapsedMilliseconds;
  await connected;
  return CheckResult(
    Status.pass,
    'A new client had its first value $value ms after it was created.',
    observed: <String, Object?>{'firstValueMs': value},
  );
}

int _median(List<int> values) => (<int>[...values]..sort())[values.length ~/ 2];

Future<CheckResult> _ackRoundTrip(Kit kit) async {
  final KitDb a = kit.open();
  await a.connected();
  final List<int> times = <int>[];
  for (int i = 0; i < 20; i++) {
    final Stopwatch watch = Stopwatch()..start();
    await within(a.ref('rtt').set(i), 'set number $i');
    times.add(watch.elapsedMicroseconds);
  }
  final List<int> sorted = <int>[...times]..sort();
  String ms(int micros) => (micros / 1000).toStringAsFixed(1);
  return CheckResult(
    Status.pass,
    'set() to acknowledgement: median ${ms(_median(times))} ms, min ${ms(sorted.first)}, max '
    '${ms(sorted.last)} (20 writes).',
    observed: <String, Object?>{'medianUs': _median(times)},
  );
}

Future<CheckResult> _reconnect(Kit kit) async {
  final KitDb a = kit.open();
  await a.connected();
  final List<int> times = <int>[];
  for (int i = 0; i < 3; i++) {
    a.db.goOffline();
    await a.disconnected();
    final Stopwatch watch = Stopwatch()..start();
    a.db.goOnline();
    await a.connected();
    times.add(watch.elapsedMilliseconds);
  }
  await within(a.ref('reconnected').set(true), 'a write after the reconnects');
  return CheckResult(
    Status.pass,
    'goOnline to .info/connected: median ${_median(times)} ms (${times.join(', ')}); hosts: '
    '${a.log.hosts.join(', ')}.',
    observed: <String, Object?>{'reconnectMs': times},
  );
}

/// The checks, in the order they run.
const List<Check> checks = <Check>[
  Check('1', 'Connect, TLS and the server host', Scope.production, _connect),
  Check('2', 'Server time offset', Scope.both, _serverTime),
  Check(
    '3',
    'Every value type: set, get, update, remove',
    Scope.both,
    _valueTypes,
  ),
  Check('4', 'ServerValue.timestamp', Scope.both, _timestamp),
  Check('5', 'ServerValue.increment', Scope.both, _increment),
  Check('6', 'Push keys in order', Scope.both, _pushKeys),
  Check('7', 'Value and child listeners', Scope.both, _listeners),
  Check('8', 'Queries against a local expectation', Scope.both, _queries),
  Check(
    '9',
    'Query on an undeclared index',
    Scope.production,
    _undeclaredIndex,
  ),
  Check(
    '10',
    'Transaction against a second client',
    Scope.both,
    _transactionConflict,
  ),
  Check('11', 'Transaction abort', Scope.both, _transactionAbort),
  Check(
    '12',
    'onDisconnect set, cancel, remove, update',
    Scope.both,
    _onDisconnect,
  ),
  Check(
    '13',
    'Writes queued offline, delivered once',
    Scope.both,
    _queuedOffline,
  ),
  Check('14', 'keepSynced, then get() offline', Scope.both, _keepSynced),
  Check(
    '15',
    'Refused without a user, accepted with one',
    Scope.both,
    _withoutUser,
    needsUser: false,
  ),
  Check('16', 'Owner rule (auth.uid)', Scope.both, _owner),
  Check(
    '17',
    '.validate refusal reverts the local value',
    Scope.both,
    _validate,
  ),
  Check(
    '18',
    'Token refresh on a live connection',
    Scope.production,
    _tokenRefresh,
  ),
  Check(
    '19',
    'Sign-out cancels an auth-only listener',
    Scope.production,
    _signOut,
  ),
  Check(
    '20',
    'Listener at a refused path',
    Scope.both,
    _deniedListener,
    needsUser: false,
  ),
  Check(
    '21',
    'Priority after emptying a node, over REST',
    Scope.production,
    _priorityRest,
  ),
  Check(
    '22',
    'Priority after emptying a node, by the client',
    Scope.production,
    _priorityClient,
  ),
  Check('23', 'Write below a primitive, offline', Scope.both, _belowPrimitive),
  Check(
    '24',
    'Timing: cold connect to first value',
    Scope.production,
    _coldConnect,
  ),
  Check('25', 'Timing: set() acknowledgement', Scope.production, _ackRoundTrip),
  Check('26', 'Timing: reconnect after goOnline', Scope.production, _reconnect),
  ...questionChecks,
];

// -----------------------------------------------------------------------------------------------
// The command line.

/// The options of the kit. `--name=value` and `--name value` both work.
final ArgParser parser = ArgParser(usageLineLength: 100)
  ..addOption(
    'backend',
    help:
        'production: a real database; needs $projectVariable and $databaseUrlVariable (or '
        '--database-url). Prints the plan and does nothing without --yes.\n'
        'emulator: the emulator at $emulatorHostVariable (project demo-test); the kit installs '
        'its rules on the namespace $emulatorNamespace.',
    valueHelp: 'production|emulator',
  )
  ..addFlag('yes', negatable: false, help: 'Confirms a run against production.')
  ..addOption(
    'database-url',
    help:
        'The database (default: $databaseUrlVariable; on the emulator '
        'http://<host>?ns=$emulatorNamespace).',
    valueHelp: 'url',
  )
  ..addOption(
    'api-key',
    help: 'The Web API key of the project (default: $webApiKeyVariable).',
    valueHelp: 'key',
  )
  ..addFlag(
    'create-user',
    negatable: false,
    help:
        'Signs up a throwaway user database-verify-<run>@example.com with a random password '
        'kept in memory, runs the checks as that user and deletes it at the end. Needs the API '
        'key and the Email/Password provider (on the emulator $authEmulatorHostVariable). '
        'Without it only checks 15 and 20 run.',
  )
  ..addOption('only', help: 'Runs only these checks.', valueHelp: '1,2')
  ..addFlag(
    'expect-emptied-node-fix',
    negatable: false,
    help:
        'Checks 22 and 38 (c), (e), (f) decide (FAIL when the client loses the priority of an '
        'emptied node). Pass it for a client with the emptied-node priority fix; without it they '
        'print what they observe.',
  )
  ..addFlag(
    'keep',
    negatable: false,
    help: 'Does not remove the data of the run at the end.',
  )
  ..addFlag('list', negatable: false, help: 'Lists the checks and exits.')
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Prints this text.');

/// The text printed by `--help` and after a usage error.
String get usage =>
    'Usage: dart run test/production/verify_production.dart '
    '--backend=production|emulator [options]\n\n${parser.usage}';

/// What a run of the kit produced.
class KitRun {
  /// A run that ended with [exitCode].
  KitRun(this.exitCode, this.results, this.runPath, {this.removed = const []});

  /// 0 when no check failed, 1 when one did, 2 for a usage error, a missing `--yes` or refused
  /// rules, 3 when the clean-up or the deletion of the user failed, 130 when a signal stopped the
  /// run, 64 for an unknown flag.
  final int exitCode;

  /// The result of each check that ran, by id.
  final Map<String, CheckResult> results;

  /// The run's path, null when the run stopped before choosing it.
  final String? runPath;

  /// The paths the clean-up removed.
  final List<String> removed;
}

KitRun _stopped(int code) => KitRun(code, <String, CheckResult>{}, null);

/// The settings of one run, read from the arguments and the environment.
class _Settings {
  _Settings(
    this.backend,
    this.selected,
    this.createUser,
    this.keep,
    this.expectEmptiedNodeFix,
  );

  final Backend backend;
  final List<Check> selected;
  final bool createUser;
  final bool keep;
  final bool expectEmptiedNodeFix;
}

String? _setting(Map<String, String> env, String name) {
  final String? value = env[name]?.trim();
  return value == null || value.isEmpty ? null : value;
}

/// The production backend, or the reason it cannot be used.
Object _production(ArgResults args, Map<String, String> env) {
  if (_setting(env, emulatorHostVariable) != null) {
    return '$emulatorHostVariable is set. Unset it for --backend=production, so that it is '
        'unambiguous where the kit writes.';
  }
  final String? project = _setting(env, projectVariable);
  final String? url =
      args.option('database-url') ?? _setting(env, databaseUrlVariable);
  if (project == null || url == null) {
    return '$projectVariable and $databaseUrlVariable (or --database-url=) name the project '
        'and the database to verify.';
  }
  final Uri? parsed = Uri.tryParse(url);
  if (parsed == null || parsed.scheme != 'https') {
    return 'The database URL must start with https://.';
  }
  if (parsed.userInfo.isNotEmpty ||
      parsed.queryParameters.keys.any((String k) => k != 'ns')) {
    return 'The database URL may carry only ?ns=: no user info and no other query, which could '
        'hold a credential.';
  }
  return Backend(
    production: true,
    projectId: project,
    databaseUrl: url,
    emulatorHost: null,
    authEmulatorHost: null,
    appId: _setting(env, appIdVariable) ?? '1:0:dart:verify-database-kit',
    apiKey: args.option('api-key') ?? _setting(env, webApiKeyVariable) ?? '',
  );
}

/// The emulator backend, or the reason it cannot be used.
Object _emulator(ArgResults args, Map<String, String> env) {
  final String? host = _setting(env, emulatorHostVariable);
  if (host == null) {
    return '$emulatorHostVariable is not set: it is the host:port of the Database emulator.';
  }
  return Backend(
    production: false,
    projectId: 'demo-test',
    databaseUrl:
        args.option('database-url') ?? 'http://$host?ns=$emulatorNamespace',
    emulatorHost: host,
    authEmulatorHost: _setting(env, authEmulatorHostVariable),
    appId: '1:0:dart:verify-database-kit',
    apiKey:
        args.option('api-key') ??
        _setting(env, webApiKeyVariable) ??
        'fake-api-key',
  );
}

/// Why `--create-user` cannot work with [backend], or null.
String? _userProblem(Backend backend) {
  if (backend.production && backend.apiKey.isEmpty) {
    return '--create-user needs the Web API key: $webApiKeyVariable or --api-key=.';
  }
  if (!backend.production && backend.authEmulatorHost == null) {
    return '--create-user on the emulator needs $authEmulatorHostVariable '
        '(tool/start_auth_emulators.sh).';
  }
  return null;
}

/// The settings, or the message of a usage error.
Object _settings(ArgResults args, Map<String, String> env) {
  final Object backend = switch (args.option('backend')) {
    'production' => _production(args, env),
    'emulator' => _emulator(args, env),
    _ => '--backend=production or --backend=emulator is required.',
  };
  if (backend is! Backend) {
    return backend;
  }
  final bool createUser = args.flag('create-user');
  final String? userProblem = createUser ? _userProblem(backend) : null;
  if (userProblem != null) {
    return userProblem;
  }
  final Object selected = _selected(args.option('only'));
  if (selected is! List<Check>) {
    return selected;
  }
  return _Settings(
    backend,
    selected,
    createUser,
    args.flag('keep'),
    args.flag('expect-emptied-node-fix'),
  );
}

/// The checks `--only` names (all of them without it), or the message of a usage error.
Object _selected(String? only) {
  if (only == null) {
    return checks;
  }
  final Set<String> ids = only.split(',').toSet();
  final Set<String> unknown = ids.difference(<String>{
    for (final Check c in checks) c.id,
  });
  if (unknown.isNotEmpty) {
    return 'Unknown check ids: ${unknown.join(', ')}';
  }
  return <Check>[
    for (final Check check in checks)
      if (ids.contains(check.id)) check,
  ];
}

String _newRunId() {
  final DateTime now = DateTime.now().toUtc();
  final String stamp = now
      .toIso8601String()
      .replaceAll(RegExp('[^0-9]'), '')
      .substring(0, 14);
  final math.Random random = math.Random.secure();
  final String suffix = <String>[
    for (int i = 0; i < 6; i++)
      'abcdefghijklmnopqrstuvwxyz0123456789'[random.nextInt(36)],
  ].join();
  return 'run_${stamp}_$suffix';
}

void _printPlan(StringSink sink, _Settings settings, String runId) {
  final Backend backend = settings.backend;
  final String user = settings.createUser
      ? 'a throwaway user database-verify-$runId@example.com is signed up with a random '
            'password and deleted at the end'
      : 'none: only checks 15 and 20 run, the others are SKIPPED (--create-user)';
  sink
    ..writeln('Realtime Database production verification kit')
    ..writeln('  backend:   ${backend.label}')
    ..writeln('  project:   ${backend.projectId}')
    ..writeln('  database:  ${backend.databaseUrl}')
    ..writeln(
      '  run path:  $kitRoot/$runId (the only place written and removed)',
    )
    ..writeln(
      '  also:      $ownerRoot/<uid>/$runId (check 16, removed too) and one refused write '
      'at $deniedRoot/$runId (removed if it was wrongly accepted)',
    )
    ..writeln('  user:      $user')
    ..writeln(
      '  size:      about 1.1 MB in total (one 1 MB string in check 32, the rest at most '
      '1.4 KB per write), at most three connections at a time (five in check 30); check '
      '38 keeps a SQLite cache in a new temporary directory and deletes it',
    )
    ..writeln(
      '  checks:    ${settings.selected.map((Check c) => c.id).join(', ')}',
    )
    ..writeln(
      settings.expectEmptiedNodeFix
          ? '  client:    --expect-emptied-node-fix: checks 22 and 38 (c), (e), (f) decide'
          : '  client:    checks 22 and 38 (c), (e), (f) are informational (pass '
                '--expect-emptied-node-fix for a client with the emptied-node priority fix)',
    );
}

/// Installs [kitRules] on the emulator's namespace; null when it worked, else why not.
Future<String?> _installEmulatorRules(Backend backend) async {
  final Uri url = Uri.parse(
    'http://${backend.emulatorHost}/.settings/rules.json',
  ).replace(queryParameters: <String, String>{'ns': backend.namespace});
  try {
    final http.Response response = await http
        .put(
          url,
          headers: const <String, String>{'Authorization': 'Bearer owner'},
          body: jsonEncode(kitRules),
        )
        .timeout(const Duration(seconds: 10));
    return response.statusCode == 200
        ? null
        : 'Installing the rules answered HTTP ${response.statusCode}: ${_clip(response.body)}';
  } on Object catch (e) {
    return 'The Database emulator at ${backend.emulatorHost} did not answer: ${describe(e)}';
  }
}

/// Signs up the throwaway user; returns the kit, or null when the sign-up failed.
Future<Kit?> _newKit(StringSink sink, _Settings settings, String runId) async {
  final Backend backend = settings.backend;
  if (!settings.createUser) {
    return Kit(
      backend,
      runId,
      null,
      null,
      null,
      expectEmptiedNodeFix: settings.expectEmptiedNodeFix,
    );
  }
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: backend.apiKey,
      appId: backend.appId,
      projectId: backend.projectId,
    ),
    name: 'verify-database-auth-$runId',
  );
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(
    app,
    emulatorHost: backend.authEmulatorHost,
  );
  final math.Random secure = math.Random.secure();
  const String alphabet =
      'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final String password = <String>[
    for (int i = 0; i < 32; i++) alphabet[secure.nextInt(alphabet.length)],
  ].join();
  try {
    final UserCredential created = await within(
      auth.createUserWithEmailAndPassword(
        email: 'database-verify-$runId@example.com',
        password: password,
      ),
      'the sign-up of the throwaway user',
    );
    return Kit(
      backend,
      runId,
      auth,
      created.user?.uid,
      password,
      expectEmptiedNodeFix: settings.expectEmptiedNodeFix,
    );
  } on Object catch (e) {
    sink.writeln(
      'Signing up the throwaway user failed: ${describe(e)}. No data was written; if the '
      'sign-up reached the server, delete the user database-verify-$runId@example.com by hand.',
    );
    return null;
  }
}

Future<CheckResult> _runOne(Kit kit, Check check) async {
  if (check.needsUser && kit.auth == null) {
    return CheckResult(
      Status.skipped,
      'Needs the throwaway user: the rules refuse requests without one (--create-user).',
    );
  }
  try {
    return await check
        .run(kit)
        .timeout(
          check.wait,
          onTimeout: () => throw KitTimeout('the whole check', check.wait),
        );
  } on KitTimeout catch (e) {
    kit.lateWritesPossible = true;
    return CheckResult(Status.inconclusive, 'The check did not finish: $e.');
  } on FirebaseDatabaseException catch (e) {
    // With a user, the preflight showed that the rules are installed: a refusal now is the
    // client's or the server's answer to this check, not missing rules.
    return CheckResult(Status.fail, 'Unexpected error: ${describe(e)}');
  } on Object catch (e) {
    return CheckResult(Status.fail, 'Unexpected error: ${describe(e)}');
  } finally {
    await kit.closeOpen();
  }
}

/// Deletes the throwaway user: [signIn] first, then [delete]. Auth refuses a deletion with
/// `requires-recent-login` when the sign-in is more than five minutes old, and a whole run takes
/// longer than that, so the user is signed in again right before. Writes the result to [sink]
/// (on failure the uid [uid] to delete by hand) and returns whether the user was deleted. When
/// [signIn] fails, [delete] is not called.
Future<bool> deleteThrowawayUser(
  StringSink sink, {
  required String? uid,
  required Future<void> Function() signIn,
  required Future<void> Function() delete,
}) async {
  try {
    await signIn();
    await delete();
    sink.writeln('The throwaway user was deleted.');
    return true;
  } on Object catch (e) {
    sink.writeln(
      'Deleting the throwaway user FAILED: ${describe(e)}. Delete the user with uid '
      '$uid by hand (Authentication > Users in the console).',
    );
    return false;
  }
}

/// What the clean-up removed, and whether it removed everything (the user included).
typedef CleanUp = ({List<String> removed, bool complete});

Future<CleanUp> _cleanUp(StringSink sink, Kit kit, bool keep) async {
  final List<String> removed = <String>[];
  bool complete = true;
  if (keep) {
    sink.writeln(
      '--keep: ${kit.runPath}${kit.ownerWritten ? ' and ${kit.ownerPath}' : ''} '
      'were not removed.',
    );
  } else {
    try {
      removed.addAll(await kit.cleanUp(sink));
      sink.writeln(
        removed.isEmpty
            ? 'Clean-up: nothing to remove (without a user the rules refused every write).'
            : 'Clean-up: removed ${removed.join(' and ')}.',
      );
      if (kit.ownerWritten && !removed.contains(kit.ownerPath)) {
        complete = false;
        sink.writeln('Clean-up INCOMPLETE: remove ${kit.ownerPath} by hand.');
      }
    } on Object catch (e) {
      complete = false;
      sink
        ..writeln('Clean-up FAILED: ${describe(e)}')
        ..writeln(
          'Remove ${kit.runPath}${kit.ownerWritten ? ' and ${kit.ownerPath}' : ''} by hand '
          '(for example in the console).',
        );
    }
  }
  final FirebaseUserAuth? auth = kit.auth;
  if (auth != null) {
    final bool deleted = await deleteThrowawayUser(
      sink,
      uid: kit.uid,
      signIn: () => within(
        auth.signInWithEmailAndPassword(
          email: kit.email,
          password: kit._password!,
        ),
        'the sign-in before the deletion of the user',
      ),
      delete: () =>
          within(auth.deleteCurrentUser(), 'the deletion of the user'),
    );
    complete = complete && deleted;
    await auth.dispose();
  }
  kit.close();
  return (removed: removed, complete: complete);
}

void _printSummary(
  StringSink sink,
  _Settings settings,
  Map<String, CheckResult> results,
) {
  final Backend backend = settings.backend;
  sink
    ..writeln('')
    ..writeln(
      'Summary (${backend.label}, project ${backend.projectId}, ${backend.databaseUrl}):',
    );
  for (final Check check in settings.selected) {
    final String label = results[check.id]?.status.label ?? 'NOT RUN';
    sink.writeln(
      '  ${check.id.padRight(3)} ${label.padRight(12)} ${check.name}',
    );
  }
}

Future<KitRun> _execute(
  StringSink sink,
  _Settings settings,
  ArgResults args,
  Future<void>? stop,
) async {
  final String runId = _newRunId();
  final String runPath = '$kitRoot/$runId';
  _printPlan(sink, settings, runId);
  if (settings.backend.production && !args.flag('yes')) {
    sink
      ..writeln('')
      ..writeln(
        'Nothing was done. Pass --yes to run this against the real database above.',
      );
    return KitRun(2, <String, CheckResult>{}, runPath);
  }
  sink.writeln('');
  if (!settings.backend.production) {
    final String? failure = await _installEmulatorRules(settings.backend);
    if (failure != null) {
      sink.writeln(failure);
      return KitRun(2, <String, CheckResult>{}, runPath);
    }
  }
  final Kit? kit = await _newKit(sink, settings, runId);
  if (kit == null) {
    return KitRun(2, <String, CheckResult>{}, runPath);
  }
  manualCleanUp =
      'Remove ${kit.runPath} (and ${kit.ownerPath} if it exists) by hand, and delete the user '
      '${kit.email} (uid ${kit.uid}).';
  final Map<String, CheckResult> results = <String, CheckResult>{};
  CleanUp cleanUp = (removed: <String>[], complete: true);
  bool interrupted = false;
  bool rulesMissing = false;
  try {
    rulesMissing = !await _preflight(sink, kit);
    for (final Check check in settings.selected) {
      if (rulesMissing || interrupted) {
        break;
      }
      sink.writeln('[${check.id}] ${check.name} ...');
      final CheckResult result = await Future.any(<Future<CheckResult>>[
        _runOne(kit, check),
        if (stop != null)
          stop.then((_) {
            interrupted = true;
            kit.lateWritesPossible = true;
            return CheckResult(Status.inconclusive, 'Stopped by a signal.');
          }),
      ]);
      results[check.id] = result;
      sink.writeln('[${check.id}] ${result.status.label}: ${result.summary}');
      for (final String detail in result.details) {
        sink.writeln('       $detail');
      }
      sink.writeln('');
    }
  } finally {
    cleanUp = await _cleanUp(sink, kit, settings.keep);
    manualCleanUp = null;
  }
  _printSummary(sink, settings, results);
  final bool failed = results.values.any(
    (CheckResult r) => r.status == Status.fail,
  );
  final int code = !cleanUp.complete
      ? 3
      : interrupted
      ? 130
      : rulesMissing
      ? 2
      : (failed ? 1 : 0);
  return KitRun(code, results, runPath, removed: cleanUp.removed);
}

/// While a run holds data or a user: what to remove by hand. A second signal prints it.
String? manualCleanUp;

/// One write and read as the user below the run's path; false (and a message) when the rules
/// refuse it. Without a user there is nothing to try.
Future<bool> _preflight(StringSink sink, Kit kit) async {
  if (kit.auth == null) {
    return true;
  }
  final KitDb db = kit.open();
  try {
    await within(db.ref('preflight').set(true), 'the preflight write');
    await db.read('preflight');
    return true;
  } on FirebaseDatabaseException catch (e) {
    sink.writeln(
      'The database refused the preflight write as the user: ${describe(e)}. Install the rules '
      'of tool/verify_production_database/rules.json (see its README); no check ran.',
    );
    return false;
  } finally {
    await kit.closeOpen();
  }
}

/// Runs the kit. [environment] defaults to the environment of the process.
///
/// When [stop] completes (a signal, in [main]) the running check is abandoned, the clean-up runs
/// and the exit code is 130. An error of a future nobody awaits is printed, not fatal, so the
/// clean-up always runs.
Future<KitRun> runKit(
  List<String> arguments, {
  StringSink? out,
  Map<String, String>? environment,
  Future<void>? stop,
}) async {
  final StringSink sink = out ?? stdout;
  final ArgResults args;
  try {
    args = parser.parse(arguments);
    if (args.rest.isNotEmpty) {
      throw FormatException('Unexpected argument: ${args.rest.first}');
    }
  } on FormatException catch (e) {
    sink
      ..writeln(e.message)
      ..writeln(usage);
    return _stopped(64);
  }
  if (args.flag('help')) {
    sink.writeln(usage);
    return _stopped(0);
  }
  if (args.flag('list')) {
    for (final Check check in checks) {
      sink.writeln(
        '${check.id.padRight(3)} ${check.scope.label.padRight(24)} ${check.name}',
      );
    }
    return _stopped(0);
  }
  final Object settings = _settings(args, environment ?? Platform.environment);
  if (settings is! _Settings) {
    sink
      ..writeln(settings)
      ..writeln(usage);
    return _stopped(2);
  }
  final Completer<KitRun> done = Completer<KitRun>();
  runZonedGuarded<void>(
    () => unawaited(
      _execute(
        sink,
        settings,
        args,
        stop,
      ).then(done.complete, onError: done.completeError),
    ),
    (Object error, StackTrace _) => sink.writeln(
      '  (an error nothing awaited, ignored: ${describe(error)})',
    ),
  );
  return done.future;
}

/// Runs the kit. The first SIGINT or SIGTERM stops the run after its clean-up; a second one
/// exits at once and prints what to remove by hand.
Future<void> main(List<String> arguments) async {
  final Completer<void> stop = Completer<void>();
  final List<ProcessSignal> signals = <ProcessSignal>[
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ];
  for (final ProcessSignal signal in signals) {
    signal.watch().listen((_) {
      if (!stop.isCompleted) {
        stdout.writeln('\nStopping: abandoning the check, then cleaning up.');
        stop.complete();
        return;
      }
      stdout.writeln(
        '\nStopped again before the clean-up ended. ${manualCleanUp ?? ''}',
      );
      exit(130);
    });
  }
  final KitRun run = await runKit(arguments, stop: stop.future);
  await stdout.flush();
  exit(run.exitCode);
}
