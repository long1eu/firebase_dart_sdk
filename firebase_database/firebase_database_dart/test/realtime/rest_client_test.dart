// Owner R. RestClient over a MockClient: the read-only seam (test plan B-9.2, B-10.1, B-10.2,
// B-6.4) and the answers of the REST API (rtdb_protocol.md 10, ReadonlyRestClient.ts).
import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/realtime/rest_client.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../contract/server_actions_contract.dart';
import '../util/rest_client_fakes.dart';

/// A limited query at `/people` ordered by `age`, starting at 25.
const ListenSpec ageQuery = ListenSpec(
  path: '/people',
  queryObject: <String, Object?>{'i': 'age', 'sp': 25, 'l': 2, 'vf': 'l'},
  queryIdentifier: '{"i":"age","l":2,"sp":25,"vf":"l"}',
  isDefault: false,
  loadsAllData: false,
  indexName: 'age',
  restParams: <String, String>{
    'orderBy': '"age"',
    'startAt': '25',
    'limitToFirst': '2',
  },
);

void main() {
  late RecordingServerActionsDelegate delegate;

  setUp(() {
    delegate = RecordingServerActionsDelegate();
  });

  Future<ListenResult> listenOnce(
    RestClient client,
    ListenSpec spec, {
    int? tag,
  }) async {
    final ListenResult result = ListenResult();
    client.listen(
      spec,
      hashProvider: FixedHash(''),
      tag: tag,
      onComplete: result.call,
    );
    await pumpUntil(() => result.completion != null);
    return result;
  }

  group('listen', () {
    test('is one GET, then onDataUpdate at /a/b, then ok', () async {
      final ScriptedServer server = ScriptedServer.always(200, '{"x":1}');
      final RestClient client = restClientFor(server, delegate: delegate);
      final ListenResult result = ListenResult();
      bool updateBeforeOk = false;
      client.listen(
        defaultSpecAt('/a/b'),
        hashProvider: FixedHash('h'),
        onComplete: (String status, Object? data) {
          updateBeforeOk = delegate.methods.contains('dataUpdate');
          result(status, data);
        },
      );
      expect(server.received, isEmpty, reason: 'nothing is sent synchronously');
      await pumpUntil(() => result.completion != null);

      expect(server.received, hasLength(1));
      expect(server.received.single.request.method, 'GET');
      expect(server.received.single.url.path, '/a/b.json');
      expect(delegate.calls, hasLength(1));
      final DelegateCall update = delegate.calls.single;
      expect(update.method, 'dataUpdate');
      expect(update.path, '/a/b');
      expect(update.data, <String, Object?>{'x': 1});
      expect(update.isMerge, isFalse);
      expect(update.tag, isNull);
      expect(updateBeforeOk, isTrue);
      expect(result.completion, (status: statusOk, data: null));
    });

    test('of the root reads /.json', () async {
      final ScriptedServer server = ScriptedServer.always(200, '5');
      final RestClient client = restClientFor(server, delegate: delegate);
      await listenOnce(client, defaultSpecAt('/'));
      expect(server.received.single.url.path, '/.json');
      expect(delegate.calls.single.path, '/');
      expect(delegate.calls.single.data, 5);
    });

    test('sends ns first, the query parameters in order, then format=export '
        '(B-6.4, B-10.1)', () async {
      final ScriptedServer server = ScriptedServer.always(200, '{}');
      final RestClient client = restClientFor(server, delegate: delegate);
      await listenOnce(client, ageQuery, tag: 3);
      final Uri url = server.received.single.url;
      expect(url.queryParametersAll.keys.toList(), <String>[
        'ns',
        'orderBy',
        'startAt',
        'limitToFirst',
        'format',
      ]);
      expect(url.queryParameters['ns'], 'demo-test-default-rtdb');
      expect(url.queryParameters['orderBy'], '"age"');
      expect(url.queryParameters['format'], 'export');
      expect(url.query, contains('orderBy=%22age%22'));
    });

    test('hands the tag of a query to onDataUpdate', () async {
      final ScriptedServer server = ScriptedServer.always(200, '{"a":1}');
      final RestClient client = restClientFor(server, delegate: delegate);
      await listenOnce(client, ageQuery, tag: 3);
      expect(delegate.calls.single.tag, 3);
    });

    test('404 is null data and ok (B-9.2)', () async {
      final RestClient client = restClientFor(
        ScriptedServer.always(404, '{"error" : "Not found"}'),
        delegate: delegate,
      );
      final ListenResult result = await listenOnce(client, defaultSpecAt('/a'));
      expect(delegate.calls.single.method, 'dataUpdate');
      expect(delegate.calls.single.data, isNull);
      expect(result.completion?.status, statusOk);
    });

    test('401 is permission_denied with the server reason and no data, '
        'without a warning (B-9.2)', () async {
      final RecordingLogger logger = RecordingLogger();
      final RestClient client = restClientFor(
        ScriptedServer.always(401, '{\n  "error" : "Permission denied"\n}'),
        delegate: delegate,
        logger: logger,
      );
      final ListenResult result = await listenOnce(client, defaultSpecAt('/a'));
      expect(delegate.calls, isEmpty);
      expect(result.completion, (
        status: 'permission_denied',
        data: 'Permission denied',
      ));
      expect(logger.warnings, isEmpty);
    });

    test('another status is rest_error:N with a warning (B-9.2)', () async {
      final RecordingLogger logger = RecordingLogger();
      final RestClient client = restClientFor(
        ScriptedServer.always(400, '{"error" : "Index not defined"}'),
        delegate: delegate,
        logger: logger,
      );
      final ListenResult result = await listenOnce(client, ageQuery, tag: 1);
      expect(delegate.calls, isEmpty);
      expect(result.completion, (
        status: 'rest_error:400',
        data: 'Index not defined',
      ));
      expect(logger.warnings.single, contains('HTTP 400'));
    });

    test('a failed listen is removed: listening again is allowed', () async {
      final RestClient client = restClientFor(
        ScriptedServer.always(500, ''),
        delegate: delegate,
      );
      final ListenResult first = await listenOnce(client, defaultSpecAt('/a'));
      expect(first.completion?.status, 'rest_error:500');
      expect(first.completion?.data, isNull);
      final ListenResult second = await listenOnce(client, defaultSpecAt('/a'));
      expect(second.completion?.status, 'rest_error:500');
    });

    test('listening twice to the same spec is an error', () async {
      final RestClient client = restClientFor(
        ScriptedServer.always(200, 'null'),
        delegate: delegate,
      );
      await listenOnce(client, defaultSpecAt('/a'));
      expect(
        () => client.listen(
          defaultSpecAt('/a'),
          hashProvider: FixedHash(''),
          onComplete: (String _, Object? _) {},
        ),
        throwsStateError,
      );
    });

    test(
      'a body that is not JSON reads as null with a warning (B-10.2)',
      () async {
        final RecordingLogger logger = RecordingLogger();
        final RestClient client = restClientFor(
          ScriptedServer.always(200, '{"x":'),
          delegate: delegate,
          logger: logger,
        );
        final ListenResult result = await listenOnce(
          client,
          defaultSpecAt('/a'),
        );
        expect(delegate.calls.single.data, isNull);
        expect(result.completion?.status, statusOk);
        expect(logger.warnings.single, contains('not JSON'));
      },
    );

    test('a body nested deeper than maxJsonDepth reads as null', () async {
      final RecordingLogger logger = RecordingLogger();
      final RestClient client = restClientFor(
        ScriptedServer.always(200, '${'{"a":' * 5}1${'}' * 5}'),
        delegate: delegate,
        logger: logger,
        maxJsonDepth: 4,
      );
      await listenOnce(client, defaultSpecAt('/a'));
      expect(delegate.calls.single.data, isNull);
      expect(logger.warnings.single, contains('deeper than 4'));
    });

    test('a body nested exactly maxJsonDepth deep is kept', () async {
      final RestClient client = restClientFor(
        ScriptedServer.always(200, '${'[' * 4}1${']' * 4}'),
        delegate: delegate,
        maxJsonDepth: 4,
      );
      await listenOnce(client, defaultSpecAt('/a'));
      expect(delegate.calls.single.data, <Object?>[
        <Object?>[
          <Object?>[
            <Object?>[1],
          ],
        ],
      ]);
    });

    test('a number that is not finite reads as null', () async {
      final RecordingLogger logger = RecordingLogger();
      final RestClient client = restClientFor(
        ScriptedServer.always(200, '{"x":[1e400]}'),
        delegate: delegate,
        logger: logger,
      );
      await listenOnce(client, defaultSpecAt('/a'));
      expect(delegate.calls.single.data, isNull);
      expect(logger.warnings.single, contains('not finite'));
    });

    test('a body over maxResponseBytes is too_big without data', () async {
      final CountingBody body = CountingBody(chunks: 1000, chunkSize: 100);
      final ScriptedServer server = ScriptedServer(
        (http.BaseRequest _) async => http.StreamedResponse(body.stream, 200),
      );
      final RestClient client = restClientFor(
        server,
        delegate: delegate,
        maxResponseBytes: 1000,
      );
      final ListenResult result = await listenOnce(client, defaultSpecAt('/a'));
      expect(result.completion?.status, 'too_big');
      expect(delegate.calls, isEmpty);
      expect(body.produced, lessThan(20), reason: 'reading stops at the cap');
    });

    test(
      'a Content-Length over maxResponseBytes is too_big before reading',
      () async {
        final CountingBody body = CountingBody(chunks: 10, chunkSize: 1000);
        final RestClient client = restClientFor(
          ScriptedServer(
            (http.BaseRequest _) async =>
                http.StreamedResponse(body.stream, 200, contentLength: 10000),
          ),
          delegate: delegate,
          maxResponseBytes: 1000,
        );
        final ListenResult result = await listenOnce(
          client,
          defaultSpecAt('/a'),
        );
        expect(result.completion?.status, 'too_big');
        expect(body.produced, lessThanOrEqualTo(1));
      },
    );

    test('unlisten drops a read in flight and aborts its request', () async {
      final Completer<http.StreamedResponse> answer =
          Completer<http.StreamedResponse>();
      final ScriptedServer server = ScriptedServer(
        (http.BaseRequest _) => answer.future,
      );
      final RestClient client = restClientFor(server, delegate: delegate);
      final ListenResult result = ListenResult();
      client.listen(
        defaultSpecAt('/a'),
        hashProvider: FixedHash(''),
        onComplete: result.call,
      );
      await pumpUntil(() => server.received.isNotEmpty);
      final http.Abortable request =
          server.received.single.request as http.Abortable;
      bool aborted = false;
      unawaited(request.abortTrigger!.then((_) => aborted = true));

      client.unlisten(defaultSpecAt('/a'));
      answer.complete(respond(200, '1'));
      await pumpEventQueue();

      expect(aborted, isTrue);
      expect(result.completion, isNull);
      expect(delegate.calls, isEmpty);
    });

    test('unlisten after the answer forgets the listen', () async {
      final RestClient client = restClientFor(
        ScriptedServer.always(200, '1'),
        delegate: delegate,
      );
      await listenOnce(client, defaultSpecAt('/a'));
      client.unlisten(defaultSpecAt('/a'));
      final ListenResult again = await listenOnce(client, defaultSpecAt('/a'));
      expect(again.completion?.status, statusOk);
    });
  });

  group('get', () {
    test('is one GET that completes with the data and does not call the '
        'delegate', () async {
      final ScriptedServer server = ScriptedServer.always(200, '{"n":"A"}');
      final RestClient client = restClientFor(server, delegate: delegate);
      expect(await client.get(ageQuery), <String, Object?>{'n': 'A'});
      expect(server.received, hasLength(1));
      expect(server.received.single.url.queryParameters['orderBy'], '"age"');
      expect(delegate.calls, isEmpty);
    });

    test('404 completes with null', () async {
      final RestClient client = restClientFor(
        ScriptedServer.always(404, ''),
        delegate: delegate,
      );
      expect(await client.get(defaultSpecAt('/a')), isNull);
    });

    test('401 throws ServerActionsException(permission_denied) with the '
        'reason', () async {
      final RestClient client = restClientFor(
        ScriptedServer.always(401, '{"error" : "Permission denied"}'),
        delegate: delegate,
      );
      await expectLater(
        client.get(defaultSpecAt('/a')),
        throwsA(
          isA<ServerActionsException>()
              .having(
                (ServerActionsException e) => e.status,
                'status',
                'permission_denied',
              )
              .having(
                (ServerActionsException e) => e.reason,
                'reason',
                'Permission denied',
              ),
        ),
      );
    });

    test(
      'another status throws ServerActionsException(rest_error:N)',
      () async {
        final RestClient client = restClientFor(
          ScriptedServer.always(503, 'down'),
          delegate: delegate,
        );
        await expectLater(
          client.get(defaultSpecAt('/a')),
          throwsA(
            isA<ServerActionsException>()
                .having(
                  (ServerActionsException e) => e.status,
                  'status',
                  'rest_error:503',
                )
                .having(
                  (ServerActionsException e) => e.reason,
                  'reason',
                  'down',
                ),
          ),
        );
      },
    );

    test('a body over maxResponseBytes throws too_big', () async {
      final RestClient client = restClientFor(
        ScriptedServer.always(200, '"${'x' * 100}"'),
        delegate: delegate,
        maxResponseBytes: 50,
      );
      await expectLater(
        client.get(defaultSpecAt('/a')),
        throwsA(
          isA<ServerActionsException>().having(
            (ServerActionsException e) => e.status,
            'status',
            'too_big',
          ),
        ),
      );
    });
  });

  group('failures without an answer', () {
    test('no headers within requestTimeout is network_error', () async {
      final RestClient client = restClientFor(
        ScriptedServer(
          (http.BaseRequest _) => Completer<http.StreamedResponse>().future,
        ),
        delegate: delegate,
        requestTimeout: const Duration(milliseconds: 50),
      );
      final ListenResult result = ListenResult();
      client.listen(
        defaultSpecAt('/a'),
        hashProvider: FixedHash(''),
        onComplete: result.call,
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(result.completion?.status, 'network_error');
      expect(delegate.calls, isEmpty);
    });

    test(
      'a body that pauses longer than requestTimeout is network_error',
      () async {
        final StreamController<List<int>> body = StreamController<List<int>>();
        addTearDown(body.close);
        final RestClient client = restClientFor(
          ScriptedServer((http.BaseRequest _) async {
            body.add(<int>[0x7b]);
            return http.StreamedResponse(body.stream, 200);
          }),
          delegate: delegate,
          requestTimeout: const Duration(milliseconds: 50),
        );
        await expectLater(
          client.get(defaultSpecAt('/a')),
          throwsA(
            isA<ServerActionsException>().having(
              (ServerActionsException e) => e.status,
              'status',
              'network_error',
            ),
          ),
        );
      },
    );

    test('a ClientException is network_error', () async {
      final RestClient client = restClientFor(
        ScriptedServer(
          (http.BaseRequest request) async =>
              throw http.ClientException('Connection refused', request.url),
        ),
        delegate: delegate,
      );
      final ListenResult result = await listenOnce(client, defaultSpecAt('/a'));
      expect(result.completion?.status, 'network_error');
      expect(result.completion?.data, contains('Connection refused'));
    });

    test(
      'a failed auth token fetch sends nothing and is network_error',
      () async {
        final ScriptedServer server = ScriptedServer.always(200, '1');
        final RestClient client = restClientFor(
          server,
          delegate: delegate,
          tokens: FixedTokenSource(authError: Exception(authMarker)),
        );
        final ListenResult result = await listenOnce(
          client,
          defaultSpecAt('/a'),
        );
        expect(result.completion?.status, 'network_error');
        expect(server.received, isEmpty);
      },
    );

    test('a failed App Check fetch reads without App Check', () async {
      final ScriptedServer server = ScriptedServer.always(200, '1');
      final RestClient client = restClientFor(
        server,
        delegate: delegate,
        tokens: FixedTokenSource(appCheckError: Exception('no')),
      );
      expect(await client.get(defaultSpecAt('/a')), 1);
      expect(
        server.received.single.request.headers.keys.map(
          (String key) => key.toLowerCase(),
        ),
        isNot(contains('x-firebase-appcheck')),
      );
    });
  });

  group('tokens', () {
    test('are fetched without forcing on each read', () async {
      final FixedTokenSource tokens = FixedTokenSource(
        auth: 't',
        appCheck: 'a',
      );
      final RestClient client = restClientFor(
        ScriptedServer.always(200, '1'),
        delegate: delegate,
        tokens: tokens,
      );
      await client.get(defaultSpecAt('/a'));
      await client.get(defaultSpecAt('/a'));
      expect(tokens.authCalls, <bool>[false, false]);
      expect(tokens.appCheckCalls, <bool>[false, false]);
    });
  });

  group('interrupt and resume', () {
    test('a read waits while interrupted and is sent on resume', () async {
      final ScriptedServer server = ScriptedServer.always(200, '1');
      final RestClient client = restClientFor(server, delegate: delegate);
      client.interrupt('repo_interrupt');
      expect(client.isInterrupted('repo_interrupt'), isTrue);
      final Future<Object?> read = client.get(defaultSpecAt('/a'));
      await pumpEventQueue();
      expect(server.received, isEmpty);

      client.resume('repo_interrupt');
      expect(client.isInterrupted('repo_interrupt'), isFalse);
      expect(await read, 1);
      expect(server.received, hasLength(1));
    });

    test('a read waits until every reason is removed', () async {
      final ScriptedServer server = ScriptedServer.always(200, '1');
      final RestClient client = restClientFor(server, delegate: delegate);
      client
        ..interrupt('a')
        ..interrupt('b');
      unawaited(client.get(defaultSpecAt('/a')));
      client.resume('a');
      await pumpEventQueue();
      expect(server.received, isEmpty);
      client.resume('b');
      await pumpEventQueue();
      expect(server.received, hasLength(1));
    });

    test('unlisten while interrupted drops the read', () async {
      final ScriptedServer server = ScriptedServer.always(200, '1');
      final RestClient client = restClientFor(server, delegate: delegate);
      client.interrupt('repo_interrupt');
      final ListenResult result = ListenResult();
      client.listen(
        defaultSpecAt('/a'),
        hashProvider: FixedHash(''),
        onComplete: result.call,
      );
      client.unlisten(defaultSpecAt('/a'));
      client.resume('repo_interrupt');
      await pumpEventQueue();
      expect(server.received, isEmpty);
      expect(result.completion, isNull);
    });
  });

  group('shutdown', () {
    test('drops the callbacks of reads in flight', () async {
      final Completer<http.StreamedResponse> answer =
          Completer<http.StreamedResponse>();
      final ScriptedServer server = ScriptedServer(
        (http.BaseRequest _) => answer.future,
      );
      final RestClient client = restClientFor(server, delegate: delegate);
      final ListenResult result = ListenResult();
      client.listen(
        defaultSpecAt('/a'),
        hashProvider: FixedHash(''),
        onComplete: result.call,
      );
      bool getCompleted = false;
      unawaited(
        client.get(defaultSpecAt('/b')).whenComplete(() => getCompleted = true),
      );
      await pumpUntil(() => server.received.length == 2);

      await client.shutdown();
      answer.complete(respond(200, '1'));
      await pumpEventQueue();

      expect(result.completion, isNull);
      expect(getCompleted, isFalse);
      expect(delegate.calls, isEmpty);
    });

    test('later reads and writes complete nothing and send nothing', () async {
      final ScriptedServer server = ScriptedServer.always(200, '1');
      final RestClient client = restClientFor(server, delegate: delegate);
      await client.shutdown();
      final ListenResult result = ListenResult();
      client
        ..listen(
          defaultSpecAt('/a'),
          hashProvider: FixedHash(''),
          onComplete: result.call,
        )
        ..put('/a', 1, onComplete: result.call);
      bool getCompleted = false;
      unawaited(
        client.get(defaultSpecAt('/a')).whenComplete(() => getCompleted = true),
      );
      await pumpEventQueue();
      expect(server.received, isEmpty);
      expect(result.completion, isNull);
      expect(getCompleted, isFalse);
    });

    test('a write completion pending at shutdown is dropped', () async {
      final RestClient client = restClientFor(
        ScriptedServer.always(200, '1'),
        delegate: delegate,
      );
      final ListenResult result = ListenResult();
      client.merge('/a', <String, Object?>{'b': 1}, onComplete: result.call);
      await client.shutdown();
      await pumpEventQueue();
      expect(result.completion, isNull);
    });
  });

  test('writes and onDisconnect requests complete with read_only, '
      'asynchronously, and send nothing', () async {
    final ScriptedServer server = ScriptedServer.always(200, '1');
    final RestClient client = restClientFor(server, delegate: delegate);
    final List<String> statuses = <String>[];
    client.onDisconnectCancel(
      '/a',
      onComplete: (String status, Object? _) => statuses.add(status),
    );
    client.put('/a', 1);
    expect(statuses, isEmpty);
    await pumpEventQueue();
    expect(statuses, <String>[statusReadOnly]);
    expect(server.received, isEmpty);
    expect(delegate.calls, isEmpty);
  });
}
