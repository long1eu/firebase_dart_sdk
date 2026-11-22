// Owner R. Threat model T23 (token in the query string), T3 (token scope), T7 and T8 (no query or
// token in a log line or an error) for RestClient.
import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
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

    test('App Check goes in the X-Firebase-AppCheck header, never in the '
        'URL', () async {
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

    test('no token goes where the target says tokens may not go (plain '
        'http to a production host)', () async {
      final ScriptedServer server = ScriptedServer.always(200, '1');
      final RestClient client = restClientFor(
        server,
        delegate: delegate,
        tokens: markers(),
        target: plainHttpTarget(),
        logger: logger,
      );
      expect(await client.get(defaultSpecAt('/a')), 1);
      final http.BaseRequest request = server.received.single.request;
      expect(request.url.scheme, 'http');
      expect(request.url.toString(), isNot(contains(authMarker)));
      expect(lowerCaseHeaders(request).values, isNot(contains(appCheckMarker)));
      expect(logger.warnings.single, contains('without credentials'));
    });
  });

  group('redirects', () {
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
    Future<List<String>> texts(
      Future<http.StreamedResponse> Function(http.BaseRequest request) answer, {
      Duration requestTimeout = const Duration(seconds: 60),
    }) async {
      final RestClient client = restClientFor(
        ScriptedServer(answer),
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
        isNot(contains('?')),
      ),
    );

    test('on success, with requests logged as contents hidden', () async {
      final List<String> seen = await texts(
        (http.BaseRequest _) async => respond(200, '1'),
      );
      expect(seen, holdsNoSecret);
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
          (http.BaseRequest _) async => respond(status, body),
        );
        expect(seen, holdsNoSecret, reason: 'status $status');
      }
    });

    test('on a ClientException whose message holds the URL and the '
        'tokens', () async {
      final List<String> seen = await texts(
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
        (http.BaseRequest _) => Completer<http.StreamedResponse>().future,
        requestTimeout: const Duration(milliseconds: 20),
      );
      expect(seen, holdsNoSecret);
      expect(seen.join('\n'), contains('network_error'));
    });

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
