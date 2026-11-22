// Owner R. Threat model T23 (token in the query string), T3 (token scope), T7 and T8 (no query or
// token in a log line or an error) for RestClient.
import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:firebase_database_dart/src/realtime/rest_client.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../contract/server_actions_contract.dart';
import '../util/rest_client_fakes.dart';

void main() {
  late RecordingServerActionsDelegate delegate;
  late RecordingLogger logger;

  setUp(() {
    delegate = RecordingServerActionsDelegate();
    logger = RecordingLogger();
  });

  FixedTokenSource markers() =>
      FixedTokenSource(auth: authMarker, appCheck: appCheckMarker);

  Map<String, String> lowerCaseHeaders(http.BaseRequest request) =>
      <String, String>{
        for (final MapEntry<String, String> header in request.headers.entries)
          header.key.toLowerCase(): header.value,
      };

  group('token scope', () {
    test('the ID token goes in auth=, last, and nowhere else', () async {
      final ScriptedServer server = ScriptedServer.always(200, '1');
      final RestClient client = restClientFor(
        server,
        delegate: delegate,
        tokens: markers(),
        target: productionTarget(),
      );
      await client.get(defaultSpecAt('/a'));
      final http.BaseRequest request = server.received.single.request;
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'demo-db.firebaseio.com');
      expect(request.url.queryParameters['auth'], authMarker);
      expect(request.url.queryParametersAll.keys.last, 'auth');
      expect(request.url.queryParameters.containsKey('access_token'), isFalse);
      final Map<String, String> headers = lowerCaseHeaders(request);
      expect(headers.containsKey('authorization'), isFalse);
      expect(headers.values, isNot(contains(authMarker)));
    });

    test('VM form (headers): App Check goes in the X-Firebase-AppCheck '
        'header, never in the URL (B-10.1)', () async {
      final ScriptedServer server = ScriptedServer.always(200, '1');
      final RestClient client = restClientFor(
        server,
        delegate: delegate,
        tokens: markers(),
      );
      await client.get(defaultSpecAt('/a'));
      final http.BaseRequest request = server.received.single.request;
      expect(lowerCaseHeaders(request)['x-firebase-appcheck'], appCheckMarker);
      expect(request.url.queryParameters.containsKey('ac'), isFalse);
      expect(request.url.toString(), isNot(contains(appCheckMarker)));
      expect(request.url.queryParametersAll.keys.toList(), <String>[
        'ns',
        'format',
        'auth',
      ]);
    });

    test('web form (no headers): App Check goes in ac=, after auth, and in no '
        'header (B-10.1)', () async {
      final ScriptedServer server = ScriptedServer.always(200, '1');
      final RestClient client = restClientFor(
        server,
        delegate: delegate,
        tokens: markers(),
        useHeaders: false,
      );
      await client.get(defaultSpecAt('/a'));
      final http.BaseRequest request = server.received.single.request;
      expect(request.url.queryParameters['ac'], appCheckMarker);
      expect(request.url.queryParameters['auth'], authMarker);
      expect(request.url.queryParametersAll.keys.toList(), <String>[
        'ns',
        'format',
        'auth',
        'ac',
      ]);
      expect(request.headers, isEmpty);
    });

    test('the emulator target gets both tokens over http', () async {
      final ScriptedServer server = ScriptedServer.always(200, '1');
      final RestClient client = restClientFor(
        server,
        delegate: delegate,
        tokens: markers(),
      );
      await client.get(defaultSpecAt('/a'));
      final http.BaseRequest request = server.received.single.request;
      expect(request.url.scheme, 'http');
      expect(request.url.authority, '127.0.0.1:9000');
      expect(request.url.queryParameters['auth'], authMarker);
    });

    test('empty tokens are not sent', () async {
      final ScriptedServer server = ScriptedServer.always(200, '1');
      final RestClient client = restClientFor(
        server,
        delegate: delegate,
        tokens: FixedTokenSource(auth: '', appCheck: ''),
      );
      await client.get(defaultSpecAt('/a'));
      final http.BaseRequest request = server.received.single.request;
      expect(request.url.queryParameters.containsKey('auth'), isFalse);
      expect(
        lowerCaseHeaders(request).containsKey('x-firebase-appcheck'),
        isFalse,
      );
    });

    test('a target that is neither TLS nor the emulator is refused, so no '
        'token can go over plain http to a production host (review M1)', () {
      expect(() => plainHttpTarget(), throwsArgumentError);
      expect(() => plainHttpTarget(useHeaders: false), throwsArgumentError);
    });

    // With M1 every target the client can be built with accepts its own REST URLs, so the
    // client's `mayReceiveTokens` gate is defence in depth; these pin that the tokens only ever
    // go to a URL the target accepts, and that the target refuses its neighbours.
    for (final bool useHeaders in <bool>[true, false]) {
      test('tokens go only to a URL the target accepts '
          '(${useHeaders ? 'VM' : 'web'} form)', () async {
        for (final RealtimeTarget target in <RealtimeTarget>[
          emulatorTarget(useHeaders: useHeaders),
          productionTarget(useHeaders: useHeaders),
        ]) {
          final ScriptedServer server = ScriptedServer.always(200, '1');
          final RestClient client = restClientFor(
            server,
            delegate: delegate,
            tokens: markers(),
            target: target,
            useHeaders: useHeaders,
          );
          await client.get(defaultSpecAt('/a'));
          final Uri url = server.received.single.url;
          expect(url.queryParameters['auth'], authMarker);
          expect(target.mayReceiveTokens(url), isTrue);
          await client.shutdown();
        }
      });
    }

    test('the targets refuse tokens for another port, host or scheme', () {
      final RealtimeTarget emulator = emulatorTarget();
      final RealtimeTarget production = productionTarget();
      expect(
        emulator.mayReceiveTokens(Uri.parse('http://127.0.0.1:9001/a.json')),
        isFalse,
      );
      expect(
        emulator.mayReceiveTokens(Uri.parse('http://10.0.0.5:9000/a.json')),
        isFalse,
      );
      expect(
        production.mayReceiveTokens(
          Uri.parse('http://demo-db.firebaseio.com/a.json'),
        ),
        isFalse,
      );
      expect(
        production.mayReceiveTokens(Uri.parse('https://evil.example/a.json')),
        isFalse,
      );
    });
  });

  group('redirects', () {
    test(
      'an answer from another origin (a client that followed a redirect) '
      'is refused with network_error and its data is dropped (review L5)',
      () async {
        final RedirectedClient http = RedirectedClient(
          Uri.parse('https://evil.example/a.json'),
          '{"secret":1}',
        );
        final RestClient client = RestClient(
          target: emulatorTarget(),
          tokens: markers(),
          delegate: delegate,
          logger: logger.call,
          httpClient: http,
          maxResponseBytes: 1 << 20,
          useHeaders: true,
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
        expect(http.sent, hasLength(1));
        expect(logger.lines, everyElement(isNot(contains('evil.example'))));
      },
    );

    test('an answer that reports the requested origin is accepted', () async {
      final RedirectedClient http = RedirectedClient(
        Uri.parse('http://127.0.0.1:9000/a.json?ns=x'),
        '1',
      );
      final RestClient client = RestClient(
        target: emulatorTarget(),
        tokens: FixedTokenSource(),
        delegate: delegate,
        httpClient: http,
        maxResponseBytes: 1 << 20,
        useHeaders: true,
      );
      expect(await client.get(defaultSpecAt('/a')), 1);
    });

    test('a 302 is not followed: one request, rest_error:302', () async {
      final ScriptedServer server = ScriptedServer(
        (http.BaseRequest _) async => http.StreamedResponse(
          const Stream<List<int>>.empty(),
          302,
          headers: <String, String>{'location': 'https://evil.example/x'},
          isRedirect: true,
        ),
      );
      final RestClient client = restClientFor(
        server,
        delegate: delegate,
        tokens: markers(),
      );
      final ListenResult result = ListenResult();
      client.listen(
        defaultSpecAt('/a'),
        hashProvider: FixedHash(''),
        onComplete: result.call,
      );
      await pumpUntil(() => result.completion != null);
      expect(server.received, hasLength(1));
      expect(server.received.single.request.followRedirects, isFalse);
      expect(result.completion?.status, 'rest_error:302');
      expect(delegate.calls, isEmpty);
    });
  });

  group('body caps', () {
    test('an error body is read up to 16 KiB only', () async {
      final CountingBody body = CountingBody(chunks: 1024, chunkSize: 1024);
      final RestClient client = restClientFor(
        ScriptedServer(
          (http.BaseRequest _) async => http.StreamedResponse(body.stream, 500),
        ),
        delegate: delegate,
      );
      Object? error;
      try {
        await client.get(defaultSpecAt('/a'));
      } on ServerActionsException catch (e) {
        error = e;
      }
      expect(error, isA<ServerActionsException>());
      expect(body.produced, lessThan(24), reason: 'reading stops at 16 KiB');
      final String reason = (error! as ServerActionsException).reason!;
      expect(reason.length, lessThan(2048), reason: 'cut by safeServerText');
    });

    test('a success body is read up to maxResponseBytes only', () async {
      final CountingBody body = CountingBody(chunks: 1024, chunkSize: 1024);
      final RestClient client = restClientFor(
        ScriptedServer(
          (http.BaseRequest _) async => http.StreamedResponse(body.stream, 200),
        ),
        delegate: delegate,
        maxResponseBytes: 8 * 1024,
      );
      await expectLater(
        client.get(defaultSpecAt('/a')),
        throwsA(isA<ServerActionsException>()),
      );
      expect(body.produced, lessThan(16));
    });
  });

  group('no query or token in a log line or an error', () {
    late ScriptedServer server;

    Future<List<String>> texts(
      Future<http.StreamedResponse> Function(http.BaseRequest request) answer, {
      required bool useHeaders,
      Duration requestTimeout = const Duration(seconds: 60),
    }) async {
      server = ScriptedServer(answer);
      final RestClient client = restClientFor(
        server,
        useHeaders: useHeaders,
        delegate: delegate,
        tokens: markers(),
        logger: logger,
        requestTimeout: requestTimeout,
      );
      final List<String> seen = <String>[];
      final ListenResult result = ListenResult();
      client.listen(
        defaultSpecAt('/a'),
        hashProvider: FixedHash(''),
        onComplete: result.call,
      );
      try {
        await client.get(defaultSpecAt('/b'));
      } on ServerActionsException catch (e) {
        seen.add(e.toString());
      }
      await pumpUntil(() => result.completion != null, rounds: 200);
      seen
        ..add('${result.completion?.data}')
        ..addAll(logger.lines)
        ..add(client.toString());
      await client.shutdown();
      return seen;
    }

    Matcher holdsNoSecret = everyElement(
      allOf(
        isNot(contains(authMarker)),
        isNot(contains(appCheckMarker)),
        isNot(contains('auth=')),
        isNot(contains('ac=')),
        isNot(contains('?')),
      ),
    );

    for (final bool useHeaders in <bool>[true, false]) {
      group(useHeaders ? 'VM form (App Check header)' : 'web form (ac=)', () {
        test('on success, with requests logged as contents hidden', () async {
          final List<String> seen = await texts(
            useHeaders: useHeaders,
            (http.BaseRequest _) async => respond(200, '1'),
          );
          expect(seen, holdsNoSecret);
          // The token really was in this request's URL (web) or header (VM).
          expect(
            server.received.first.url.queryParameters.containsKey('ac'),
            !useHeaders,
          );
          expect(
            logger.lines.where((String line) => line.startsWith('debug: GET')),
            everyElement(endsWith('(contents hidden)')),
          );
        });

        test('on 401, 500 and a body that is not JSON', () async {
          for (final (int status, String body) in <(int, String)>[
            (401, '{"error" : "Permission denied"}'),
            (500, 'boom'),
            (200, '{'),
          ]) {
            logger.lines.clear();
            final List<String> seen = await texts(
              useHeaders: useHeaders,
              (http.BaseRequest _) async => respond(status, body),
            );
            expect(seen, holdsNoSecret, reason: 'status $status');
          }
        });

        test('on a ClientException whose message holds the URL and the '
            'tokens', () async {
          final List<String> seen = await texts(
            useHeaders: useHeaders,
            (http.BaseRequest request) async => throw http.ClientException(
              'failed: ${request.url} ${request.url.query} $authMarker '
              '$appCheckMarker',
              request.url,
            ),
          );
          expect(seen, holdsNoSecret);
          expect(seen.join('\n'), contains('failed'));
        });

        test('on a timeout', () async {
          final List<String> seen = await texts(
            useHeaders: useHeaders,
            (http.BaseRequest _) => Completer<http.StreamedResponse>().future,
            requestTimeout: const Duration(milliseconds: 20),
          );
          expect(seen, holdsNoSecret);
          expect(seen.join('\n'), contains('network_error'));
        });
      });
    }

    test('on a failed auth token fetch', () async {
      final RestClient client = restClientFor(
        ScriptedServer.always(200, '1'),
        delegate: delegate,
        tokens: FixedTokenSource(authError: Exception(authMarker)),
        logger: logger,
      );
      Object? error;
      try {
        await client.get(defaultSpecAt('/a'));
      } on ServerActionsException catch (e) {
        error = e;
      }
      expect(error.toString(), isNot(contains(authMarker)));
      expect(logger.lines, everyElement(isNot(contains(authMarker))));
    });
  });
}
