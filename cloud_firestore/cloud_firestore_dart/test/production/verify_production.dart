// The production verification kit: a command line tool that checks, against a real Firestore database, the
// behaviours that were only ever verified against the emulator.
//
//     dart run test/production/verify_production.dart --backend=production --yes
//     dart run test/production/verify_production.dart --backend=emulator
//
// See tool/verify_production/README.md (repository root) for the commands, the cost and how to read the report.
//
// The kit never reads, creates or prints credentials: in production mode the access tokens come from Application
// Default Credentials through `ApplicationDefaultTokenSource` (test/util/test_backend.dart) and are only handed to
// the transport. It writes only below one root document that is unique to the run, counts its writes against a cap,
// and deletes what it wrote.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/grpc_channel.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/grpc_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/keep_alive_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_channel_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_http_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_v1;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:grpc/grpc.dart'
    show ChannelCredentials, ChannelOptions, ClientTransportConnectorChannel;

import '../unit/firebase/firestore/local/mock/database_mock.dart';
import '../util/chaos_proxy.dart';
import '../util/integration_test_util.dart';
import '../util/io_web_http_client.dart';
import '../util/test_backend.dart';

/// The outcome of a check.
enum Status {
  /// The behaviour was observed and is what the SDK relies on (or the question the check asks was answered and
  /// the SDK stayed consistent; the answer is in the summary).
  pass('PASS'),

  /// The SDK misbehaved, or the backend does something the SDK does not handle.
  fail('FAIL'),

  /// The check could not come to a result (for example a composite index is missing); the explanation says what
  /// to do.
  inconclusive('INCONCLUSIVE'),

  /// The check does not apply to this backend.
  skipped('SKIPPED');

  const Status(this.label);

  final String label;
}

class CheckResult {
  CheckResult(this.status, this.summary,
      {this.details = const <String>[],
      this.observed = const <String, Object?>{}});

  final Status status;

  /// One line: what was observed.
  final String summary;

  /// More lines for the report.
  final List<String> details;

  /// Machine-readable observations (also asserted by the emulator test of the kit).
  final Map<String, Object?> observed;
}

class Check {
  const Check(this.id, this.name, this.run);

  /// The id used with `--only`.
  final String id;
  final String name;
  final Future<CheckResult> Function(Kit kit) run;
}

/// How a client of the kit talks to the backend.
enum Transport { grpc, web }

/// The backend the kit runs against and how to reach it.
class Backend {
  Backend({
    required this.production,
    required this.projectId,
    required this.databaseId,
    required this.host,
    required this.port,
    required this.ssl,
  });

  final bool production;
  final String projectId;
  final String databaseId;
  final String host;
  final int port;
  final bool ssl;

  String get label => production ? 'production' : 'emulator';
}

/// A [WebHttpClient] that records where the requests go (paths and the names of the query parameters, never their
/// values or any header).
class RecordingWebHttpClient implements WebHttpClient {
  RecordingWebHttpClient(this._delegate);

  final WebHttpClient _delegate;

  /// The last path segment of every request, for example `channel` or `documents:commit`.
  final List<String> endpoints = <String>[];

  /// The names of the query parameters seen on the WebChannel requests.
  final Set<String> channelParameters = <String>{};

  @override
  WebHttpRequest send(String method, Uri url,
      {Map<String, String> headers = const <String, String>{}, String? body}) {
    final String last = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
    endpoints.add(last);
    if (last == 'channel') {
      channelParameters.addAll(url.queryParameters.keys);
    }
    return _delegate.send(method, url, headers: headers, body: body);
  }

  @override
  void close() => _delegate.close();
}

/// Thrown before a write that would exceed the cap of the run.
class WriteCapExceeded implements Exception {
  WriteCapExceeded(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the checks share: the clients, the documents of the run, the write budget.
class Kit {
  Kit(this.backend, this.runId, this.maxWrites, this._out);

  final Backend backend;
  final String runId;
  final int maxWrites;
  final StringSink _out;

  /// The fixed id of the root collection. Everything the kit writes is below `$rootCollection/$runId`.
  static const String rootCollection = 'verify_production_kit';

  String get rootPath => '$rootCollection/$runId';

  final ApplicationDefaultTokenSource _tokens = ApplicationDefaultTokenSource();
  final List<Firestore> _clients = <Firestore>[];
  final List<ChaosProxy> _proxies = <ChaosProxy>[];
  final List<FirestoreTransport> _transports = <FirestoreTransport>[];
  final Set<String> _touched = <String>{};
  int _clientIndex = 0;
  Firestore? _direct;

  /// The writes spent so far (deletes of the clean-up not included).
  int writes = 0;

  /// The edition the database behaves like ('standard', 'enterprise' or 'unknown'), set by the edition check.
  String? inferredEdition;

  /// The recorder of the last web client that was created.
  RecordingWebHttpClient? lastWebRecorder;

  void log(String message) => _out.writeln(message);

  DatabaseId get databaseId =>
      DatabaseId.forDatabase(backend.projectId, backend.databaseId);

  MockCredentialsProvider _credentials({bool authenticated = true}) =>
      MockCredentialsProvider(
          tokenSource: backend.production && authenticated ? _tokens : null);

  DatabaseInfo get _databaseInfo => DatabaseInfo(
      databaseId, 'verify-production', backend.host,
      port: backend.port, sslEnabled: backend.ssl);

  FirestoreTransport _grpcTransport(
      ChannelOptionsProvider options, ChaosProxy? via) {
    if (via == null) {
      return createTransport(_databaseInfo, options);
    }
    // Through the proxy: connect to the proxy, but keep the name of the backend for TLS (SNI and certificate) and
    // for the authority of the calls. The proxy only pipes bytes, so TLS passes through it untouched.
    final ChannelCredentials credentials = backend.ssl
        ? ChannelCredentials.secure(authority: backend.host)
        : const ChannelCredentials.insecure();
    final ChannelOptions channelOptions = ChannelOptions(
        credentials: credentials, connectTimeout: defaultConnectTimeout);
    return GrpcTransport(
      ClientTransportConnectorChannel(
        KeepAliveTransportConnector(
          host: via.host,
          port: via.port,
          credentials: credentials,
          pingInterval: defaultKeepAlivePingInterval,
          pingTimeout: defaultKeepAliveTimeout,
          connectTimeout: defaultConnectTimeout,
        ),
        options: channelOptions,
      ),
      options,
    );
  }

  /// A new client with an empty in-memory cache.
  ///
  /// With [via] the gRPC connection goes through that proxy. With `authenticated: false` the client sends no token.
  Future<Firestore> client(
      {Transport transport = Transport.grpc,
      ChaosProxy? via,
      bool authenticated = true}) async {
    final FirestoreSettings settings = FirestoreSettings(
      host: backend.host,
      port: backend.port,
      sslEnabled: backend.ssl,
      // An in-memory cache that keeps the documents, so that the checks can read the cache.
      cacheSettings: MemoryCacheSettings(gcSettings: MemoryLruGcSettings()),
    );
    final String dbName = 'production_kit/${runId}_${_clientIndex++}.db';
    DatabaseMock.deleteDatabaseFiles(dbName);
    final Object? previous = Datastore.transportOverride;
    Datastore.transportOverride =
        (DatabaseInfo databaseInfo, ChannelOptionsProvider options) {
      if (transport == Transport.web) {
        final RecordingWebHttpClient recorder =
            RecordingWebHttpClient(IoWebHttpClient());
        lastWebRecorder = recorder;
        return WebChannelTransport(recorder, databaseInfo, options);
      }
      return _grpcTransport(options, via);
    };
    try {
      final Firestore firestore = await IntegrationTestUtil.forTests(
        databaseId,
        'verify-production-${_clientIndex}',
        _credentials(authenticated: authenticated),
        TaskScheduler(''),
        (String path,
            {int? version,
            OnConfigure? onConfigure,
            OnCreate? onCreate,
            OnVersionChange? onUpgrade,
            OnVersionChange? onDowngrade,
            OnOpen? onOpen}) {
          return DatabaseMock.create(dbName,
              version: version,
              onConfigure: onConfigure,
              onCreate: onCreate,
              onUpgrade: onUpgrade,
              onDowngrade: onDowngrade,
              onOpen: onOpen);
        },
        settings,
      );
      _clients.add(firestore);
      return firestore;
    } finally {
      Datastore.transportOverride = previous as FirestoreTransport Function(
          DatabaseInfo, ChannelOptionsProvider)?;
    }
  }

  /// The client that talks to the backend directly over gRPC, shared by the checks (the oracle of the chaos checks).
  Future<Firestore> get direct async => _direct ??= await client();

  /// A raw gRPC transport, for the checks that speak the protocol themselves.
  FirestoreTransport rawTransport() {
    final FirestoreTransport transport = _grpcTransport(
        ChannelOptionsProvider(
            databaseId: databaseId, credentialsProvider: _credentials()),
        null);
    _transports.add(transport);
    return transport;
  }

  /// A proxy in front of the backend.
  Future<ChaosProxy> proxy() async {
    final ChaosProxy proxy = await ChaosProxy.start(backend.host, backend.port);
    _proxies.add(proxy);
    return proxy;
  }

  /// The path of a collection of the run. [name] is a fixed id (composite indexes are defined per collection id).
  String collectionPath(String name) => '$rootPath/$name';

  /// A document of the run. Every document the kit writes comes from here, so that the clean-up can delete it.
  DocumentReference<Map<String, Object?>> doc(
      Firestore db, String collection, String id) {
    final String path = '${collectionPath(collection)}/$id';
    _touched.add(path);
    return db.doc(path);
  }

  /// The resource name of a document of the run.
  String documentName(String collection, String id) =>
      'projects/${backend.projectId}/databases/${backend.databaseId}/documents/'
      '${collectionPath(collection)}/$id';

  /// Accounts for [count] writes before they are made. Throws when the cap of the run would be exceeded.
  void spend(int count) {
    if (writes + count > maxWrites) {
      throw WriteCapExceeded(
        'The write cap of the run ($maxWrites) would be exceeded: $writes spent, $count more requested.',
      );
    }
    writes += count;
  }

  /// Deletes every document the kit handed out. Returns how many deletes were sent.
  Future<int> cleanUp() async {
    if (_touched.isEmpty) {
      return 0;
    }
    final Firestore db = await direct;
    final List<String> paths = _touched.toList()..sort();
    for (int i = 0; i < paths.length; i += 100) {
      final WriteBatch batch = db.batch();
      for (final String path in paths.skip(i).take(100)) {
        batch.delete(db.doc(path));
      }
      await batch.commit().timeout(const Duration(seconds: 60));
    }
    return paths.length;
  }

  Future<void> close() async {
    for (final ChaosProxy proxy in _proxies) {
      proxy.restore();
    }
    for (final Firestore client in _clients) {
      try {
        await client.terminate().timeout(const Duration(seconds: 20));
      } catch (_) {
        // Nothing to do about a client that does not terminate.
      }
    }
    for (final FirestoreTransport transport in _transports) {
      try {
        await transport.shutdown().timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    for (final ChaosProxy proxy in _proxies) {
      await proxy.close();
    }
  }
}

// ---- helpers of the checks ----

const Duration _patience = Duration(seconds: 30);

Future<void> _eventually(FutureOr<bool> Function() condition, String what,
    {Duration timeout = _patience}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!await condition()) {
    if (watch.elapsed > timeout) {
      throw TimeoutException('Timed out waiting for $what', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

String _describeError(Object error) {
  if (error is FirestoreError) {
    return '${error.code}: ${error.message}';
  }
  return '${error.runtimeType}: $error';
}

/// The console link the backend puts in the error of a query that needs an index, or null.
String? _indexLink(Object error) {
  final RegExpMatch? match =
      RegExp(r'https://console\.[^\s"]+').firstMatch('$error');
  return match?.group(0);
}

List<String> _ids(QuerySnapshot<Object?> snapshot) =>
    snapshot.docs.map((QueryDocumentSnapshot<Object?> d) => d.id).toList();

// ---- the checks ----

Future<CheckResult> _crud(Kit kit) async {
  final Firestore db = await kit.direct;
  final DocumentReference<Map<String, Object?>> ref =
      kit.doc(db, 'vp_crud', 'doc');
  kit.spend(3);
  await ref.set(<String, Object?>{
    's': 'text é \u{1F60A}',
    'n': 1,
    'nested': <String, Object?>{'list': <Object?>[1, 'two', null]},
    'when': FieldValue.serverTimestamp(),
  });
  DocumentSnapshot<Map<String, Object?>> snapshot =
      await ref.get(Source.server);
  if (!snapshot.exists ||
      snapshot.data!['n'] != 1 ||
      snapshot.data!['when'] is! Timestamp) {
    return CheckResult(Status.fail, 'The document read back is not what was written: ${snapshot.data}');
  }
  await ref.update(<String, Object?>{
    'n': FieldValue.increment(2),
    'nested.list': FieldValue.arrayUnion(<Object?>['three']),
  });
  snapshot = await ref.get(Source.server);
  final Object? list = (snapshot.data!['nested']! as Map<String, Object?>)['list'];
  if (snapshot.data!['n'] != 3 || '$list' != '[1, two, null, three]') {
    return CheckResult(Status.fail, 'The update was not applied as expected: ${snapshot.data}');
  }
  await ref.delete();
  snapshot = await ref.get(Source.server);
  if (snapshot.exists) {
    return CheckResult(Status.fail, 'The document still exists after the delete.');
  }
  return CheckResult(Status.pass,
      'set, get, update with transforms, server timestamp and delete work.');
}

Future<CheckResult> _listeners(Kit kit) async {
  final Firestore writer = await kit.direct;
  final Firestore listener = await kit.client();
  final DocumentReference<Map<String, Object?>> a =
      kit.doc(listener, 'vp_listen', 'a');
  final List<DocumentSnapshot<Map<String, Object?>>> docEvents =
      <DocumentSnapshot<Map<String, Object?>>>[];
  final List<QuerySnapshot<Map<String, Object?>>> queryEvents =
      <QuerySnapshot<Map<String, Object?>>>[];
  final List<Object> errors = <Object>[];
  final StreamSubscription<Object?> docSub =
      a.snapshots.listen(docEvents.add, onError: errors.add);
  final StreamSubscription<Object?> querySub = listener
      .collection(kit.collectionPath('vp_listen'))
      .snapshots
      .listen(queryEvents.add, onError: errors.add);
  try {
    await _eventually(
        () => docEvents.isNotEmpty && queryEvents.isNotEmpty || errors.isNotEmpty,
        'the first snapshots');
    kit.spend(4);
    await kit.doc(writer, 'vp_listen', 'a').set(<String, Object?>{'v': 1});
    await kit.doc(writer, 'vp_listen', 'b').set(<String, Object?>{'v': 2});
    await _eventually(
        () =>
            errors.isNotEmpty ||
            (docEvents.last.data?['v'] == 1 &&
                _ids(queryEvents.last).join(',') == 'a,b'),
        'the added documents');
    await kit.doc(writer, 'vp_listen', 'a').update(<String, Object?>{'v': 3});
    await kit.doc(writer, 'vp_listen', 'b').delete();
    await _eventually(
        () =>
            errors.isNotEmpty ||
            (docEvents.last.data?['v'] == 3 &&
                _ids(queryEvents.last).join(',') == 'a'),
        'the update and the delete');
    if (errors.isNotEmpty) {
      return CheckResult(Status.fail, 'A listener failed: ${_describeError(errors.first)}');
    }
    return CheckResult(Status.pass,
        'A document listener and a collection listener see adds, updates and deletes made by another client.',
        observed: <String, Object?>{
          'documentEvents': docEvents.length,
          'queryEvents': queryEvents.length,
        });
  } finally {
    await docSub.cancel();
    await querySub.cancel();
  }
}

Future<CheckResult> _queries(Kit kit) async {
  final Firestore db = await kit.direct;
  // A fixed collection id: a composite index created for it once serves every run.
  const String name = 'vp_queries';
  kit.spend(6);
  final WriteBatch batch = db.batch();
  for (int i = 0; i < 6; i++) {
    batch.set(kit.doc(db, name, 'd$i'), <String, Object?>{
      'a': i % 2,
      'b': i,
      'tags': <Object?>['t${i % 3}'],
    });
  }
  await batch.commit();
  final CollectionReference<Map<String, Object?>> collection =
      db.collection(kit.collectionPath(name));

  final List<String> problems = <String>[];
  Future<void> expectIds(String what, Query<Map<String, Object?>> query,
      List<String> expected) async {
    final List<String> actual = _ids(await query.get(Source.server));
    if (actual.join(',') != expected.join(',')) {
      problems.add('$what: expected $expected, got $actual');
    }
  }

  await expectIds('equality filter', collection.where('a', isEqualTo: 1),
      <String>['d1', 'd3', 'd5']);
  await expectIds('order and limit',
      collection.orderBy('b', Direction.descending).limit(2), <String>['d5', 'd4']);
  await expectIds('range filter', collection.where('b', isGreaterThan: 3),
      <String>['d4', 'd5']);
  await expectIds('array-contains',
      collection.where('tags', arrayContains: 't0'), <String>['d0', 'd3']);
  await expectIds(
      'or filter',
      collection.where(Filter.or(<Filter>[
        Filter.equalTo('b', 0),
        Filter.equalTo('b', 5),
      ])),
      <String>['d0', 'd5']);
  final int count =
      (await collection.where('a', isEqualTo: 0).count().get()).getCount();
  if (count != 3) {
    problems.add('count aggregation: expected 3, got $count');
  }
  if (problems.isNotEmpty) {
    return CheckResult(Status.fail, 'Queries returned unexpected results.',
        details: problems);
  }

  // A query that needs a composite index (a ascending, b descending) on the collection id.
  try {
    await expectIds(
        'composite index query',
        collection.where('a', isEqualTo: 1).orderBy('b', Direction.descending),
        <String>['d5', 'd3', 'd1']);
  } on FirestoreError catch (e) {
    if (e.code == FirestoreErrorCode.failedPrecondition) {
      final String? link = _indexLink(e);
      return CheckResult(Status.inconclusive,
          'Single-field queries work; the composite query needs an index that does not exist yet.',
          details: <String>[
            'Collection id: $name, fields: a ascending, b descending (collection scope).',
            if (link != null)
              'Create it with the link the backend returned, wait until it is built, and run again:'
            else
              'The backend returned no link: ${e.message}',
            if (link != null) '  $link',
          ],
          observed: <String, Object?>{'missingIndex': true, 'link': link});
    }
    rethrow;
  }
  if (problems.isNotEmpty) {
    return CheckResult(Status.fail, 'The composite query returned unexpected results.',
        details: problems);
  }
  return CheckResult(Status.pass,
      'Filters, order, limit, OR, count and a composite-index query return the expected documents.',
      observed: <String, Object?>{'missingIndex': false});
}

Future<CheckResult> _lostAcknowledgement(Kit kit) async {
  final Firestore oracle = await kit.direct;
  final ChaosProxy proxy = await kit.proxy();
  final Firestore db = await kit.client(via: proxy);
  final DocumentReference<Map<String, Object?>> ref =
      kit.doc(db, 'vp_lost_ack', 'counter');
  final DocumentReference<Map<String, Object?>> oracleRef =
      kit.doc(oracle, 'vp_lost_ack', 'counter');
  kit.spend(5);
  try {
    await ref.set(<String, Object?>{'n': 0, 'tag': 'first'}).timeout(_patience);
  } on Object catch (e) {
    return CheckResult(Status.inconclusive,
        'The client could not write through the TCP proxy: ${_describeError(e)}',
        details: <String>[
          'The proxy pipes bytes to ${kit.backend.host}:${kit.backend.port}; TLS is end to end.',
        ]);
  }

  // The backend applies both writes, but its answers are held back and the connection is cut: the client never
  // sees the acknowledgements and sends the writes again.
  proxy.mode = ChaosMode.stallDown;
  final List<Future<void>> writes = <Future<void>>[
    ref.update(<String, Object?>{'n': FieldValue.increment(1)}),
    ref.update(<String, Object?>{'tag': 'second'}),
  ];
  try {
    await _eventually(() async {
      final Map<String, Object?>? data =
          (await oracleRef.get(Source.server)).data;
      return data != null && data['tag'] == 'second';
    }, 'the backend to apply the writes whose answers are held back');
  } on TimeoutException {
    proxy.restore();
    return CheckResult(Status.inconclusive,
        'The writes did not reach the backend while its answers were held back, so no acknowledgement could be lost.');
  }
  final int beforeCut =
      ((await oracleRef.get(Source.server)).data!['n']! as num).toInt();
  proxy
    ..cut()
    ..mode = ChaosMode.forward;
  await Future.wait(writes).timeout(const Duration(seconds: 60));

  final Map<String, Object?> server =
      (await oracleRef.get(Source.server)).data!;
  final DocumentSnapshot<Map<String, Object?>> cached =
      await ref.get(Source.cache);
  final int n = (server['n']! as num).toInt();
  final Map<String, Object?> observed = <String, Object?>{
    'incrementCountedBeforeCut': beforeCut,
    'incrementCounted': n,
    'cacheAgrees': '${cached.data}' == '$server',
    'cachePendingWrites': cached.metadata.hasPendingWrites,
  };
  if (n < 1 || server['tag'] != 'second') {
    return CheckResult(Status.fail, 'A write was lost: the backend has $server.',
        observed: observed);
  }
  if ('${cached.data}' != '$server' || cached.metadata.hasPendingWrites) {
    return CheckResult(Status.fail,
        'After the re-sent writes the cache (${cached.data}, pending writes: '
        '${cached.metadata.hasPendingWrites}) differs from the backend ($server).',
        observed: observed);
  }
  if (n == 1) {
    return CheckResult(Status.pass,
        'DEDUPLICATED: the backend applied the re-sent increment once (n == 1).',
        details: <String>[
          'A write whose acknowledgement is lost is not applied again by this backend.',
        ],
        observed: observed);
  }
  return CheckResult(Status.pass,
      'APPLIED TWICE: the backend applied the re-sent increment again (n == $n). No write was lost and the cache agrees.',
      details: <String>[
        'Writes are delivered at least once: a non-idempotent transform (increment) can be counted again after a',
        'lost acknowledgement (reviews/chaos_findings.md, F1). The emulator behaves this way.',
      ],
      observed: observed);
}

Future<CheckResult> _lostCommitAnswer(Kit kit) async {
  final Firestore oracle = await kit.direct;
  final ChaosProxy proxy = await kit.proxy();
  final Firestore db = await kit.client(via: proxy);
  final DocumentReference<Map<String, Object?>> counter =
      kit.doc(db, 'vp_lost_commit', 'counter');
  final DocumentReference<Map<String, Object?>> marker =
      kit.doc(db, 'vp_lost_commit', 'marker');
  final DocumentReference<Map<String, Object?>> oracleMarker =
      kit.doc(oracle, 'vp_lost_commit', 'marker');
  // The first write, and up to five attempts of two writes.
  kit.spend(11);
  await kit
      .doc(oracle, 'vp_lost_commit', 'counter')
      .set(<String, Object?>{'n': 0});
  try {
    await counter.get(Source.server).timeout(_patience);
  } on Object catch (e) {
    return CheckResult(Status.inconclusive,
        'The client could not read through the TCP proxy: ${_describeError(e)}');
  }

  int attempts = 0;
  bool answerLost = false;
  Object? error;
  try {
    await db.runTransaction<void>((Transaction transaction) async {
      attempts++;
      final DocumentSnapshot<Map<String, Object?>> snapshot =
          await transaction.get(counter);
      transaction
        ..update(counter,
            <String, Object?>{'n': (snapshot.data!['n']! as num).toInt() + 1})
        ..set(marker, <String, Object?>{'attempt': attempts});
      if (attempts == 1) {
        // From now on the answers of the backend are held back. Once the backend has applied the commit, the
        // connection is cut: the answer to the commit is lost.
        proxy.mode = ChaosMode.stallDown;
        unawaited(() async {
          try {
            await _eventually(
                () async => (await oracleMarker.get(Source.server)).exists,
                'the backend to apply the commit');
            answerLost = true;
          } on TimeoutException {
            // Reported below.
          }
          proxy
            ..cut()
            ..mode = ChaosMode.forward;
        }());
      }
    }).timeout(const Duration(seconds: 90));
  } on Object catch (e) {
    error = e;
  }
  proxy.restore();
  if (!answerLost) {
    return CheckResult(Status.inconclusive,
        'The commit did not reach the backend while its answers were held back, so no answer could be lost.');
  }
  final int n = ((await kit
              .doc(oracle, 'vp_lost_commit', 'counter')
              .get(Source.server))
          .data!['n']! as num)
      .toInt();
  final Map<String, Object?> observed = <String, Object?>{
    'attempts': attempts,
    'applied': n,
    'error': error == null ? null : _describeError(error),
  };
  if (n < 1) {
    return CheckResult(Status.fail, 'The transaction was lost (n == 0).',
        observed: observed);
  }
  final String outcome = error == null
      ? 'the transaction reported success after $attempts attempts'
      : 'the transaction reported ${_describeError(error)} after $attempts attempts';
  if (n == 1) {
    return CheckResult(Status.pass,
        'APPLIED ONCE: the commit whose answer was lost was applied once (n == 1); $outcome.',
        observed: observed);
  }
  return CheckResult(Status.pass,
      'APPLIED TWICE: the commit whose answer was lost was applied, and the retry applied the body again (n == $n); $outcome.',
      details: <String>[
        'The client cannot know that the commit was applied: it sees UNAVAILABLE and retries, like the other SDKs',
        '(reviews/chaos_findings.md, F2). No update was lost.',
      ],
      observed: observed);
}

/// Rewrites the read times of a snapshot JSON bundle to [readTime].
Map<String, Object?> _withReadTime(Map<String, Object?> json, DateTime readTime) {
  final String time = readTime.toUtc().toIso8601String();
  final List<int> bytes = utf8.encode(json['bundle']! as String);
  final List<Map<String, Object?>> elements = <Map<String, Object?>>[];
  int position = 0;
  while (position < bytes.length) {
    final int open = bytes.indexOf(0x7B, position);
    final int length = int.parse(utf8.decode(bytes.sublist(position, open)));
    elements.add(jsonDecode(utf8.decode(bytes.sublist(open, open + length)))
        as Map<String, Object?>);
    position = open + length;
  }
  String prefixed(Map<String, Object?> element) {
    final String text = jsonEncode(element);
    return '${utf8.encode(text).length}$text';
  }

  final StringBuffer body = StringBuffer();
  for (final Map<String, Object?> element in elements.skip(1)) {
    for (final String key in <String>['namedQuery', 'documentMetadata']) {
      final Object? value = element[key];
      if (value is Map<String, Object?>) {
        value['readTime'] = time;
      }
    }
    body.write(prefixed(element));
  }
  final Map<String, Object?> metadata =
      elements.first['metadata']! as Map<String, Object?>;
  metadata['createTime'] = time;
  metadata['totalBytes'] = utf8.encode(body.toString()).length;
  return <String, Object?>{
    ...json,
    'bundle': '${prefixed(elements.first)}$body',
  };
}

Future<CheckResult> _resumeOldReadTime(Kit kit) async {
  final Firestore writer = await kit.direct;
  const String name = 'vp_resume';
  final Query<Map<String, Object?>> query = writer
      .collection(kit.collectionPath(name))
      .where('k', isEqualTo: 'match');
  // The snapshot of the (still empty) query, as an application would have serialized it some time ago.
  final Map<String, Object?> fresh = (await query.get(Source.server)).toJson();
  kit.spend(1);
  await kit.doc(writer, name, 'later').set(<String, Object?>{'k': 'match'});

  final Map<String, Object?> observed = <String, Object?>{};
  final List<String> details = <String>[];
  bool failed = false;
  final DateTime now = DateTime.now();
  final Map<String, Duration> ages = <String, Duration>{
    'unchanged': Duration.zero,
    '2 hours': const Duration(hours: 2),
    '8 days': const Duration(days: 8),
  };
  for (final MapEntry<String, Duration> age in ages.entries) {
    final Map<String, Object?> json = age.value == Duration.zero
        ? fresh
        : _withReadTime(fresh, now.subtract(age.value));
    final Firestore db = await kit.client();
    final List<QuerySnapshot<Map<String, Object?>>> events =
        <QuerySnapshot<Map<String, Object?>>>[];
    final List<Object> errors = <Object>[];
    final StreamSubscription<Object?> sub = db
        .querySnapshotsFromJson<Map<String, Object?>>(json,
            options: const SnapshotListenOptions(
                metadataChanges: MetadataChanges.include))
        .listen(events.add, onError: errors.add);
    String outcome;
    try {
      await _eventually(
          () =>
              errors.isNotEmpty ||
              (events.isNotEmpty && !events.last.metadata.isFromCache),
          'the resumed listener',
          timeout: const Duration(seconds: 20));
      if (errors.isNotEmpty) {
        outcome = 'error: ${_describeError(errors.first)}';
        failed = true;
      } else if (_ids(events.last).join(',') != 'later') {
        outcome = 'in sync, but with ${_ids(events.last)} instead of [later]';
        failed = true;
      } else {
        outcome = 'in sync with the document written after the snapshot';
      }
    } on TimeoutException {
      outcome = 'never got in sync (no error either)';
      failed = true;
    } finally {
      await sub.cancel();
    }
    observed[age.key] = outcome;
    details.add('read time ${age.key} old: $outcome');
  }
  if (failed) {
    return CheckResult(Status.fail,
        'Resuming a listener from a serialized snapshot does not work for every read time.',
        details: <String>[
          ...details,
          'querySnapshotsFromJson() sends the read time of the snapshot to the backend. If the backend rejects an',
          'old read time, the SDK needs to fall back to a full listen.',
        ],
        observed: observed);
  }
  return CheckResult(Status.pass,
      'A listener resumed from a serialized snapshot gets in sync, also with a read time of 2 hours and of 8 days ago.',
      details: details, observed: observed);
}

/// Opens a raw Listen stream. Returns the stream of responses and the sink of requests.
({StreamController<proto.ListenRequest> requests, Stream<proto.ListenResponse> responses})
    _rawListen(FirestoreTransport transport) {
  final StreamController<proto.ListenRequest> requests =
      StreamController<proto.ListenRequest>();
  return (
    requests: requests,
    responses: transport.startCall(FirestoreRpc.listen, requests.stream),
  );
}

proto.ListenRequest _addTarget(Kit kit, String documentName, int targetId) {
  return proto.ListenRequest()
    ..database =
        'projects/${kit.backend.projectId}/databases/${kit.backend.databaseId}'
    ..addTarget = (proto_v1.Target()
      ..targetId = targetId
      ..documents =
          (proto.Target_DocumentsTarget()..documents.add(documentName)));
}

proto.ListenRequest _removeTarget(Kit kit, int targetId) {
  return proto.ListenRequest()
    ..database =
        'projects/${kit.backend.projectId}/databases/${kit.backend.databaseId}'
    ..removeTarget = targetId;
}

/// Collects the target changes of a raw Listen stream.
class _TargetChanges {
  _TargetChanges(Stream<proto.ListenResponse> responses) {
    subscription = responses.listen((proto.ListenResponse response) {
      if (response.hasTargetChange()) {
        for (final int id in response.targetChange.targetIds) {
          seen.add('${response.targetChange.targetChangeType.name}:$id');
        }
        if (response.targetChange.hasCause()) {
          errors.add('${response.targetChange.cause.code}: '
              '${response.targetChange.cause.message}');
        }
      }
    }, onError: (Object e) {
      errors.add(_describeError(e));
      if (!done.isCompleted) {
        done.complete();
      }
    }, onDone: () {
      if (!done.isCompleted) {
        done.complete();
      }
    });
  }

  late final StreamSubscription<proto.ListenResponse> subscription;
  final Set<String> seen = <String>{};
  final List<String> errors = <String>[];
  final Completer<void> done = Completer<void>();
}

Future<CheckResult> _targetIds(Kit kit) async {
  final FirestoreTransport transport = kit.rawTransport();
  final String name = kit.documentName('vp_targets', 'none');
  // The ids the SDK uses (it starts at 1002 and 1003) and the largest ones a 32-bit target id allows.
  const List<int> ids = <int>[1002, 1003, 123456789, 2147483646, 2147483647];
  final call = _rawListen(transport);
  final _TargetChanges changes = _TargetChanges(call.responses);
  try {
    for (final int id in ids) {
      call.requests.add(_addTarget(kit, name, id));
    }
    try {
      await _eventually(
          () =>
              changes.errors.isNotEmpty ||
              ids.every((int id) => changes.seen.contains('CURRENT:$id')),
          'the targets to be current',
          timeout: const Duration(seconds: 20));
    } on TimeoutException {
      return CheckResult(Status.fail,
          'Not every target id was acknowledged: ${changes.seen.toList()..sort()}',
          observed: <String, Object?>{'seen': changes.seen.toList()..sort()});
    }
    if (changes.errors.isNotEmpty) {
      return CheckResult(Status.fail,
          'The backend rejected a target id: ${changes.errors.first}',
          observed: <String, Object?>{'errors': changes.errors});
    }
    return CheckResult(Status.pass,
        'The backend accepts the target ids $ids (the SDK sends ids from 1002 up).',
        observed: <String, Object?>{'accepted': ids});
  } finally {
    await call.requests.close();
    await changes.done.future
        .timeout(const Duration(seconds: 15), onTimeout: () {});
    await changes.subscription.cancel();
  }
}

Future<CheckResult> _halfClose(Kit kit) async {
  final FirestoreTransport transport = kit.rawTransport();
  final String name = kit.documentName('vp_targets', 'none');
  final List<int> samples = <int>[];
  final List<String> problems = <String>[];
  // The SDK cancels (resets) a stream that the backend has not finished 10 s after the half-close.
  const Duration grace = Duration(seconds: 10);
  for (int i = 0; i < 3; i++) {
    final call = _rawListen(transport);
    final _TargetChanges changes = _TargetChanges(call.responses);
    final int id = 1002 + 2 * i;
    call.requests.add(_addTarget(kit, name, id));
    try {
      await _eventually(
          () =>
              changes.errors.isNotEmpty || changes.seen.contains('CURRENT:$id'),
          'the target to be current',
          timeout: const Duration(seconds: 20));
      // Unlisten, wait for the backend to confirm it, then half-close like the SDK does when it stops the stream.
      call.requests.add(_removeTarget(kit, id));
      await _eventually(
          () =>
              changes.errors.isNotEmpty || changes.seen.contains('REMOVE:$id'),
          'the removal of the target',
          timeout: const Duration(seconds: 20));
    } on TimeoutException catch (e) {
      problems.add('sample $i: ${e.message}');
      await call.requests.close();
      await changes.subscription.cancel();
      continue;
    }
    final Stopwatch watch = Stopwatch()..start();
    await call.requests.close();
    bool ended = true;
    await changes.done.future.timeout(grace + const Duration(seconds: 5),
        onTimeout: () => ended = false);
    if (!ended) {
      problems.add('sample $i: the backend did not end the stream within '
          '${grace.inSeconds + 5} s of the half-close');
      await changes.subscription.cancel();
    } else {
      samples.add(watch.elapsedMilliseconds);
      if (changes.errors.isNotEmpty) {
        problems.add('sample $i: the stream ended with ${changes.errors.first}');
      }
    }
  }
  final Map<String, Object?> observed = <String, Object?>{
    'millis': samples,
    'problems': problems,
  };
  if (samples.length < 3 ||
      samples.any((int ms) => ms >= grace.inMilliseconds)) {
    return CheckResult(Status.fail,
        'The backend does not end a half-closed Listen stream within the 10 s the SDK waits before it resets the call.',
        details: <String>[
          'times until the stream ended (ms): $samples',
          ...problems,
        ],
        observed: observed);
  }
  if (problems.isNotEmpty) {
    return CheckResult(Status.fail,
        'A half-closed Listen stream did not end cleanly.',
        details: <String>['times (ms): $samples', ...problems],
        observed: observed);
  }
  return CheckResult(Status.pass,
      'After the unlisten, the backend ends a half-closed Listen stream in $samples ms (the SDK waits up to 10 s).',
      observed: observed);
}

/// The same query on another client.
Query<Map<String, Object?>> _rebase(
    Firestore db, Query<Map<String, Object?>> query) {
  // ignore: invalid_use_of_internal_member
  return Query<Map<String, Object?>>(query.query, db);
}

/// Null and NaN in equality filters. The Standard edition never matches them; the Enterprise edition does (as
/// pinned with the emulators in test/integration_enterprise/edition_differences_test.dart).
Future<CheckResult> _editionFilters(Kit kit) async {
  final Firestore db = await kit.direct;
  const String name = 'vp_edition';
  kit.spend(3);
  final WriteBatch batch = db.batch()
    ..set(kit.doc(db, name, 'number'), <String, Object?>{
      'value': 1,
      'array': <Object?>[1],
    })
    ..set(kit.doc(db, name, 'null'), <String, Object?>{
      'value': null,
      'array': <Object?>[null],
    })
    ..set(kit.doc(db, name, 'nan'), <String, Object?>{
      'value': double.nan,
      'array': <Object?>[double.nan],
    });
  await batch.commit();
  final CollectionReference<Map<String, Object?>> collection =
      db.collection(kit.collectionPath(name));
  final Map<String, Query<Map<String, Object?>>> queries =
      <String, Query<Map<String, Object?>>>{
    'array-contains null': collection.whereArrayContains('array', null),
    'array-contains NaN': collection.whereArrayContains('array', double.nan),
    'array-contains-any [null]':
        collection.whereArrayContainsAny('array', <Object?>[null]),
    'array-contains-any [NaN]':
        collection.whereArrayContainsAny('array', <Object?>[double.nan]),
    'in [null]': collection.whereIn('value', <Object?>[null]),
    'in [NaN]': collection.whereIn('value', <Object?>[double.nan]),
  };
  const Map<String, String> enterprise = <String, String>{
    'array-contains null': 'null',
    'array-contains NaN': 'nan',
    'array-contains-any [null]': 'null',
    'array-contains-any [NaN]': 'nan',
    'in [null]': 'null',
    'in [NaN]': 'nan',
  };
  final Map<String, String> server = <String, String>{};
  final Map<String, String> local = <String, String>{};
  // First with a client that has nothing cached: what the backend returns.
  final Firestore cold = await kit.client();
  for (final String key in queries.keys) {
    final Query<Map<String, Object?>> query = _rebase(cold, queries[key]!);
    server[key] = _ids(await query.get(Source.server)).join(',');
  }
  // Then with the documents in the cache: what the SDK alone evaluates, and whether a server read still completes
  // (a cached document that only the SDK matches would stay in limbo).
  final List<String> stuck = <String>[];
  await collection.get(Source.server);
  for (final String key in queries.keys) {
    local[key] = _ids(await queries[key]!.get(Source.cache)).join(',');
  }
  await Future.wait(<Future<void>>[
    for (final String key in queries.keys)
      () async {
        try {
          final String warm = _ids(await queries[key]!
                  .get(Source.server)
                  .timeout(const Duration(seconds: 15)))
              .join(',');
          if (warm != server[key]) {
            stuck.add('$key: with the documents cached, a server read returns [$warm] '
                'instead of [${server[key]}]');
          }
        } on TimeoutException {
          stuck.add('$key: with the documents cached, get(Source.server) does not complete');
        }
      }(),
  ]);
  stuck.sort();
  final bool standardProfile = server.values.every((String ids) => ids.isEmpty);
  final bool enterpriseProfile = server.keys
      .every((String key) => server[key] == enterprise[key]);
  final List<String> localDifferences = <String>[
    for (final String key in server.keys)
      if (server[key] != local[key])
        '$key: the backend returns [${server[key]}], the SDK alone (cache) [${local[key]}]',
  ];
  final Map<String, Object?> observed = <String, Object?>{
    'edition': standardProfile
        ? 'standard'
        : enterpriseProfile
            ? 'enterprise'
            : 'unknown',
    'server': server,
    'localDifferences': localDifferences,
    'stuck': stuck,
  };
  kit.inferredEdition = observed['edition']! as String;
  final List<String> details = <String>[
    for (final String key in server.keys) '$key -> [${server[key]}]',
    if (localDifferences.isNotEmpty)
      'Queries answered from the cache differ from the backend (the SDK evaluates filters like the Standard edition):',
    ...localDifferences.map((String d) => '  $d'),
    ...stuck,
  ];
  if (stuck.isNotEmpty) {
    return CheckResult(Status.fail,
        'The SDK and the backend disagree about null or NaN in a filter, and a server read with cached documents '
        'does not give the result of the backend.',
        details: details, observed: observed);
  }
  if (standardProfile) {
    return CheckResult(Status.pass,
        'STANDARD semantics: equality filters never match null or NaN, as with the Standard edition emulator.',
        details: details, observed: observed);
  }
  if (enterpriseProfile) {
    return CheckResult(Status.pass,
        'ENTERPRISE semantics: equality filters match null and NaN, as with the Enterprise edition emulator.',
        details: details, observed: observed);
  }
  return CheckResult(Status.inconclusive,
      'The results match neither the Standard nor the Enterprise behaviour of the emulators.',
      details: <String>[
        ...details,
        'Update the "Enterprise edition" section of the package README with what the real backend does.',
      ],
      observed: observed);
}

Future<CheckResult> _bsonIncrement(Kit kit) async {
  if (kit.inferredEdition == null) {
    return CheckResult(Status.skipped,
        'The edition of the database is not known: run check 6 (edition) in the same run.');
  }
  if (kit.inferredEdition != 'enterprise') {
    return CheckResult(Status.skipped,
        'The database behaves like the Standard edition (check 6): BSON types need an Enterprise edition database.');
  }
  final Firestore db = await kit.direct;
  final DocumentReference<Map<String, Object?>> ref =
      kit.doc(db, 'vp_bson', 'doc');
  kit.spend(4);
  await ref.set(<String, Object?>{'val': Decimal128Value('10.5')});
  await ref.update(<String, Object?>{'val': FieldValue.increment(5.0)});
  final Object? decimal = (await ref.get(Source.server)).data!['val'];
  await ref.set(<String, Object?>{'val': Int32Value(10)});
  await ref.update(<String, Object?>{'val': FieldValue.increment(5)});
  final Object? int32 = (await ref.get(Source.server)).data!['val'];
  final Map<String, Object?> observed = <String, Object?>{
    'decimal128': '$decimal',
    'int32': '$int32',
  };
  final bool decimalAdded = decimal == Decimal128Value('15.5');
  final bool int32Added = int32 == 15 || int32 == Int32Value(15);
  if (decimalAdded && int32Added) {
    return CheckResult(Status.pass,
        'increment() adds to a Decimal128Value (15.5) and to an Int32Value (15).',
        observed: observed);
  }
  return CheckResult(Status.fail,
      'increment() on BSON numbers did not add: Decimal128(10.5) + 5.0 -> $decimal, Int32(10) + 5 -> $int32.',
      details: <String>[
        'The Enterprise edition emulator (v1.22.0) replaces the field with the operand; the SDK tests of this are',
        'skipped there (test/integration_enterprise/bson_types_test.dart, numericIncrementWithBsonTypes).',
      ],
      observed: observed);
}

Future<CheckResult> _negativeZeroAndEmptyBytes(Kit kit) async {
  final Firestore grpc = await kit.direct;
  final Firestore web = await kit.client(transport: Transport.web);
  final Map<String, Object?> data = <String, Object?>{
    'negativeZero': -0.0,
    'zero': 0.0,
    'emptyBytes': Blob(Uint8List(0)),
    'nested': <Object?>[-0.0, Blob(Uint8List(0))],
  };
  kit.spend(2);
  await kit.doc(grpc, 'vp_values', 'by_grpc').set(data);
  await kit.doc(web, 'vp_values', 'by_web').set(data);

  final List<String> problems = <String>[];
  final Map<String, Firestore> readers = <String, Firestore>{
    'gRPC': grpc,
    'web': web,
  };
  for (final String writer in <String>['by_grpc', 'by_web']) {
    for (final MapEntry<String, Firestore> reader in readers.entries) {
      final Map<String, Object?>? read =
          (await kit.doc(reader.value, 'vp_values', writer).get(Source.server))
              .data;
      final String who = 'written $writer, read over ${reader.key}';
      if (read == null) {
        problems.add('$who: the document is missing');
        continue;
      }
      bool isNegativeZero(Object? v) => v is double && v == 0 && v.isNegative;
      bool isEmptyBlob(Object? v) => v is Blob && v.bytes.isEmpty;
      final Object? nested = read['nested'];
      if (!isNegativeZero(read['negativeZero'])) {
        problems.add('$who: -0.0 came back as ${read['negativeZero']} '
            '(${read['negativeZero'].runtimeType})');
      }
      final Object? zero = read['zero'];
      if (!(zero is double && zero == 0 && !zero.isNegative)) {
        problems.add('$who: 0.0 came back as $zero (${zero.runtimeType})');
      }
      if (!isEmptyBlob(read['emptyBytes'])) {
        problems.add('$who: the empty bytes came back as ${read['emptyBytes']}');
      }
      if (nested is! List ||
          nested.length != 2 ||
          !isNegativeZero(nested[0]) ||
          !isEmptyBlob(nested[1])) {
        problems.add('$who: the nested values came back as $nested');
      }
    }
  }
  if (problems.isNotEmpty) {
    return CheckResult(Status.fail,
        '-0.0 or empty bytes do not survive a round trip.',
        details: <String>[
          ...problems,
          if (problems.every((String p) => p.contains('written by_web')) &&
              !kit.backend.production)
            'Known for the emulator: its JSON front end stores -0 as 0 (also for a plain REST request). What counts is '
                'the result against production.',
        ],
        observed: <String, Object?>{'problems': problems});
  }
  return CheckResult(Status.pass,
      '-0.0, 0.0 and empty bytes round trip over gRPC and over the web transport, in all four combinations.',
      observed: <String, Object?>{'problems': problems});
}

Future<CheckResult> _tokens(Kit kit) async {
  if (!kit.backend.production) {
    return CheckResult(Status.skipped,
        'The emulator needs no token; nothing to verify.');
  }
  final Firestore db = await kit.direct;
  final DocumentReference<Map<String, Object?>> ref =
      kit.doc(db, 'vp_tokens', 'doc');
  kit.spend(1);
  await ref.set(<String, Object?>{'v': 1});
  final bool authenticatedRead = (await ref.get(Source.server)).exists;
  // The same read without a token, to see that the token is what grants access.
  final Firestore anonymous = await kit.client(authenticated: false);
  String anonymousOutcome;
  try {
    final DocumentSnapshot<Map<String, Object?>> snapshot = await kit
        .doc(anonymous, 'vp_tokens', 'doc')
        .get(Source.server)
        .timeout(_patience);
    anonymousOutcome = snapshot.exists
        ? 'allowed (the security rules of the database let anyone read this path)'
        : 'allowed, document not visible';
  } on Object catch (e) {
    anonymousOutcome = 'rejected with ${_describeError(e)}';
  }
  final Map<String, Object?> observed = <String, Object?>{
    'authenticatedRead': authenticatedRead,
    'anonymousRead': anonymousOutcome,
  };
  if (!authenticatedRead) {
    return CheckResult(Status.fail,
        'A request with the access token of the Application Default Credentials was not served.',
        observed: observed);
  }
  return CheckResult(Status.pass,
      'Requests with the OAuth access token (Authorization header) are accepted.',
      details: <String>[
        'The same read without a token: $anonymousOutcome.',
        'App Check: not verified. The kit has no App Check token provider (a token can only come from an app',
        'registered with App Check).',
      ],
      observed: observed);
}

Future<CheckResult> _webTransport(Kit kit) async {
  final Firestore writer = await kit.direct;
  final Firestore web = await kit.client(transport: Transport.web);
  final RecordingWebHttpClient recorder = kit.lastWebRecorder!;
  const String name = 'vp_web';
  final DocumentReference<Map<String, Object?>> ref = kit.doc(web, name, 'a');
  kit.spend(5);

  // Unary calls (REST): a server read, a transaction (lookup and commit), an aggregation.
  await ref.set(<String, Object?>{'n': 1});
  final List<QuerySnapshot<Map<String, Object?>>> events =
      <QuerySnapshot<Map<String, Object?>>>[];
  final List<Object> errors = <Object>[];
  final StreamSubscription<Object?> sub = web
      .collection(kit.collectionPath(name))
      .snapshots
      .listen(events.add, onError: errors.add);
  try {
    await _eventually(
        () => errors.isNotEmpty || (events.isNotEmpty && _ids(events.last).join(',') == 'a'),
        'the first snapshot over WebChannel');
    await web.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, Object?>> snapshot =
          await transaction.get(ref);
      transaction.update(ref,
          <String, Object?>{'n': (snapshot.data!['n']! as num).toInt() + 1});
    });
    final int count =
        (await web.collection(kit.collectionPath(name)).count().get()).getCount();
    final Object? n = (await ref.get(Source.server)).data?['n'];
    // A change made by another client arrives on the WebChannel stream.
    await kit.doc(writer, name, 'b').set(<String, Object?>{'n': 10});
    await _eventually(
        () => errors.isNotEmpty || _ids(events.last).join(',') == 'a,b',
        'a remote change over WebChannel');
    // A batch through the write stream.
    await (web.batch()
          ..set(kit.doc(web, name, 'c'), <String, Object?>{'n': 3})
          ..delete(kit.doc(web, name, 'b')))
        .commit();
    await _eventually(
        () => errors.isNotEmpty || _ids(events.last).join(',') == 'a,c',
        'the batch over WebChannel');

    final Set<String> endpoints = recorder.endpoints.toSet();
    final Map<String, Object?> observed = <String, Object?>{
      'endpoints': endpoints.toList()..sort(),
      'gsessionid': recorder.channelParameters.contains('gsessionid'),
      'channelParameters': recorder.channelParameters.toList()..sort(),
    };
    if (errors.isNotEmpty) {
      return CheckResult(Status.fail,
          'A listener over WebChannel failed: ${_describeError(errors.first)}',
          observed: observed);
    }
    if (n != 2 || count != 1) {
      return CheckResult(Status.fail,
          'The unary calls over REST returned n=$n (expected 2) and count=$count (expected 1).',
          observed: observed);
    }
    return CheckResult(Status.pass,
        'The web transport works: REST unary calls (read, transaction, aggregation) and the WebChannel streams '
        '(listen and write).',
        details: <String>[
          'Endpoints used: ${observed['endpoints']}',
          recorder.channelParameters.contains('gsessionid')
              ? 'The backend asked for session routing: the channel requests carried a gsessionid.'
              : 'The backend did not ask for session routing (no gsessionid on the channel requests).',
        ],
        observed: observed);
  } finally {
    await sub.cancel();
  }
}

/// The checks, in the order they run.
final List<Check> checks = <Check>[
  const Check('1a', 'Basic CRUD', _crud),
  const Check('1b', 'Listeners', _listeners),
  const Check('1c', 'Queries and composite indexes', _queries),
  const Check('2', 'Lost write acknowledgement: is a re-sent write applied twice? (F1)', _lostAcknowledgement),
  const Check('3', 'Lost commit answer in a transaction (F2)', _lostCommitAnswer),
  const Check('4', 'Resume from snapshot JSON with an old read time', _resumeOldReadTime),
  const Check('5', 'Target ids from 1000 up', _targetIds),
  const Check('6', 'Null and NaN in filters: which edition', _editionFilters),
  const Check('7', 'BSON numeric increment (Enterprise edition)', _bsonIncrement),
  const Check('8', '-0.0 and empty bytes over gRPC and the web transport', _negativeZeroAndEmptyBytes),
  const Check('9', 'Half-close timing after unlisten', _halfClose),
  const Check('10', 'Auth token acceptance (App Check: not covered)', _tokens),
  const Check('11', 'Web transport (WebChannel and REST)', _webTransport),
];

/// The most writes a full run can make (the sum of what the checks spend), with some room for retries.
const int defaultMaxWrites = 60;

const String usage = '''
Usage: dart run test/production/verify_production.dart --backend=production|emulator [options]

  --backend=production   A real Firebase project: FIRESTORE_TEST_PROJECT_ID (and optionally
                         FIRESTORE_TEST_DATABASE_ID) must be set, FIRESTORE_EMULATOR_HOST must not.
                         Application Default Credentials are used. Needs --yes.
  --backend=emulator     The emulator of FIRESTORE_EMULATOR_HOST (project demo-test).
  --yes                  Confirms that the kit may write to the real project.
  --only=1a,2,5          Runs only these checks (ids as in the report).
  --max-writes=N         The write cap of the run (default $defaultMaxWrites).
  --keep                 Does not delete the documents of the run at the end.
  --list                 Lists the checks and exits.
''';

/// What a run of the kit produced.
class KitRun {
  KitRun(this.exitCode, this.results, this.writes, this.deletes, this.rootPath);

  final int exitCode;
  final Map<String, CheckResult> results;
  final int writes;
  final int deletes;
  final String? rootPath;
}

/// Runs the kit. [environment] defaults to the environment of the process.
Future<KitRun> runKit(List<String> arguments,
    {StringSink? out, Map<String, String>? environment}) async {
  final StringSink sink = out ?? stdout;
  final Map<String, String> env = environment ?? Platform.environment;
  String? option(String name) {
    for (final String argument in arguments) {
      if (argument.startsWith('--$name=')) {
        return argument.substring(name.length + 3);
      }
    }
    return null;
  }

  KitRun usageError(String message) {
    sink
      ..writeln(message)
      ..writeln(usage);
    return KitRun(2, <String, CheckResult>{}, 0, 0, null);
  }

  const Set<String> flags = <String>{'--yes', '--keep', '--list'};
  const Set<String> options = <String>{'backend', 'only', 'max-writes'};
  for (final String argument in arguments) {
    final bool known = flags.contains(argument) ||
        options.any((String name) => argument.startsWith('--$name='));
    if (!known) {
      return usageError('Unknown argument: $argument');
    }
  }
  if (arguments.contains('--list')) {
    for (final Check check in checks) {
      sink.writeln('${check.id.padRight(3)} ${check.name}');
    }
    return KitRun(0, <String, CheckResult>{}, 0, 0, null);
  }

  final TestBackend testBackend = TestBackend(env);
  final String? backendName = option('backend');
  final Backend backend;
  if (backendName == 'production') {
    if (testBackend.emulatorHost != null) {
      return usageError(
          '${TestBackend.emulatorHostVariable} is set. Unset it for --backend=production, so that it is '
          'unambiguous where the kit writes.');
    }
    final String? projectId = testBackend.realProjectId;
    if (projectId == null) {
      return usageError(
          '${TestBackend.projectIdVariable} is not set: it names the Firebase project to verify.');
    }
    backend = Backend(
      production: true,
      projectId: projectId,
      databaseId: testBackend.realDatabaseId ?? DatabaseId.defaultDatabaseId,
      host: TestBackend.productionHost,
      port: 443,
      ssl: true,
    );
  } else if (backendName == 'emulator') {
    final String? emulator = testBackend.emulatorHost;
    if (emulator == null) {
      return usageError(
          '${TestBackend.emulatorHostVariable} is not set: it is the host:port of the emulator.');
    }
    final EmulatorAddress address = EmulatorAddress.parse(emulator);
    backend = Backend(
      production: false,
      projectId: 'demo-test',
      databaseId: DatabaseId.defaultDatabaseId,
      host: address.host,
      port: address.port,
      ssl: false,
    );
  } else {
    return usageError('--backend=production or --backend=emulator is required.');
  }

  final int maxWrites =
      int.tryParse(option('max-writes') ?? '') ?? defaultMaxWrites;
  final Set<String>? only = option('only')?.split(',').toSet();
  if (only != null) {
    final Set<String> unknown =
        only.difference(checks.map((Check c) => c.id).toSet());
    if (unknown.isNotEmpty) {
      return usageError('Unknown check ids: $unknown');
    }
  }
  final List<Check> selected = <Check>[
    for (final Check check in checks)
      if (only == null || only.contains(check.id)) check,
  ];

  final String runId = 'run_${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp('[^0-9]'), '').substring(0, 14)}'
      '_${DateTime.now().microsecond.toRadixString(36)}';
  final Kit kit = Kit(backend, runId, maxWrites, sink);
  sink
    ..writeln('Firestore production verification kit')
    ..writeln('  backend:   ${backend.label} (${backend.host}:${backend.port})')
    ..writeln('  project:   ${backend.projectId}')
    ..writeln('  database:  ${backend.databaseId}')
    ..writeln('  writes to: ${kit.rootPath}/... (nothing else is written or deleted)')
    ..writeln('  cost:      at most $maxWrites document writes, the same number of deletes to clean up, '
        'and a few hundred document reads')
    ..writeln('  checks:    ${selected.map((Check c) => c.id).join(', ')}');
  if (backend.production && !arguments.contains('--yes')) {
    sink
      ..writeln('')
      ..writeln('Nothing was done. Pass --yes to run this against the real project above.');
    return KitRun(2, <String, CheckResult>{}, 0, 0, kit.rootPath);
  }
  sink.writeln('');

  final Map<String, CheckResult> results = <String, CheckResult>{};
  int deletes = 0;
  try {
    for (final Check check in selected) {
      sink.writeln('[${check.id}] ${check.name} ...');
      CheckResult result;
      try {
        result = await check.run(kit).timeout(const Duration(seconds: 150));
      } on WriteCapExceeded catch (e) {
        result = CheckResult(
          Status.inconclusive,
          'Stopped before writing: ${e.message} Raise --max-writes to run this check.',
        );
      } on TimeoutException catch (e) {
        result = CheckResult(Status.inconclusive,
            'The check did not finish: ${e.message ?? 'timed out after ${e.duration}'}');
      } on FirestoreError catch (e) {
        final bool permission = e.code == FirestoreErrorCode.permissionDenied ||
            e.code == FirestoreErrorCode.unauthenticated;
        result = CheckResult(
            permission ? Status.inconclusive : Status.fail,
            permission
                ? 'The backend refused the request: ${_describeError(e)}'
                : 'Unexpected error: ${_describeError(e)}',
            details: <String>[
              if (permission)
                'Check the credentials (roles/datastore.user), the project id and the database id.',
            ]);
      } on Object catch (e) {
        result = CheckResult(Status.fail, 'Unexpected error: ${_describeError(e)}');
      }
      results[check.id] = result;
      sink.writeln('[${check.id}] ${result.status.label}: ${result.summary}');
      for (final String detail in result.details) {
        sink.writeln('       $detail');
      }
      sink.writeln('');
    }
  } finally {
    if (arguments.contains('--keep')) {
      sink.writeln('--keep: the documents below ${kit.rootPath} were not deleted.');
    } else {
      try {
        deletes = await kit.cleanUp();
        sink.writeln('Clean-up: $deletes documents deleted below ${kit.rootPath} (every document the run could have written).');
      } on Object catch (e) {
        sink
          ..writeln('Clean-up FAILED: ${_describeError(e)}')
          ..writeln('Delete the documents below ${kit.rootPath} by hand (for example in the console).');
      }
    }
    await kit.close();
  }

  sink
    ..writeln('')
    ..writeln('Summary (${backend.label}, project ${backend.projectId}, database ${backend.databaseId}):');
  for (final Check check in selected) {
    final CheckResult result = results[check.id]!;
    sink.writeln('  ${check.id.padRight(3)} ${result.status.label.padRight(12)} ${check.name}');
  }
  sink.writeln('  writes: ${kit.writes} of at most $maxWrites, deletes: $deletes');
  final bool failed =
      results.values.any((CheckResult r) => r.status == Status.fail);
  return KitRun(failed ? 1 : 0, results, kit.writes, deletes, kit.rootPath);
}

Future<void> main(List<String> arguments) async {
  final KitRun run = await runKit(arguments);
  await stdout.flush();
  exit(run.exitCode);
}
