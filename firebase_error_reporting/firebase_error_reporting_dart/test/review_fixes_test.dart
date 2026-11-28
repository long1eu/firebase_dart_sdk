// Tests for the findings of the first independent review of the package.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_error_reporting_dart/firebase_error_reporting_dart.dart';
import 'package:firebase_error_reporting_dart/src/format.dart';
import 'package:firebase_error_reporting_dart/src/transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fakes.dart';

class _NoJitter implements Random {
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
  @override
  int nextInt(int max) => 0;
}

class _SlowStore implements ErrorReportingStore {
  _SlowStore(this.state);

  ErrorReportingState state;
  final Completer<void> release = Completer<void>();

  @override
  Future<ErrorReportingState> load() async {
    await release.future;
    return state;
  }

  @override
  Future<void> save(ErrorReportingState state) async => this.state = state;
}

class _SlowAppCheck extends AppCheckTokenProvider {
  final Completer<AppCheckTokenResult> result =
      Completer<AppCheckTokenResult>();

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) =>
      result.future;

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}

final DateTime _start = DateTime.utc(2026, 11, 28, 12);

ErrorReporter _reporter(
  FakeAsync async,
  Server server, {
  FirebaseApp? app,
  ErrorReportingTransport? transport,
  ErrorReportingStore? store,
  List<String>? logs,
  void Function(String)? onDiagnostic,
}) => ErrorReporter(
  app ?? newApp(),
  service: 's',
  transport:
      transport ?? ErrorReportingTransport.direct(apiKey: 'AIzaSecretKey'),
  store: store,
  httpClient: server.client,
  clock: () => _start.add(async.elapsed),
  random: _NoJitter(),
  onDiagnostic: onDiagnostic ?? (logs ?? <String>[]).add,
);

StackTrace _stackAt(int line) =>
    StackTrace.fromString('#0      f (package:notes/f.dart:$line:1)\n');

void main() {
  test('C1: Retry-After 0 does not loop; the backoff is the floor', () {
    fakeAsync((FakeAsync async) {
      final Server server = Server(<int>[503])
        ..responseHeaders = <String, String>{'retry-after': '0'};
      final ErrorReporter reporter = _reporter(async, server);
      reporter.recordError(StateError('x'), appStack);
      async.elapse(const Duration(seconds: 10));
      // 2 s delay, then waits of 1, 2, 4 s: at most four requests in ten seconds.
      expect(server.requests.length, lessThanOrEqualTo(4));
    });
  });

  test('C3: close before the store was read does not erase it', () {
    fakeAsync((FakeAsync async) {
      final _SlowStore store = _SlowStore(
        const ErrorReportingState(user: 'u', collectionEnabled: false),
      );
      final ErrorReporter reporter = _reporter(async, Server(), store: store);
      reporter.close(timeout: const Duration(seconds: 1));
      async.elapse(const Duration(seconds: 2));
      store.release.complete();
      async.elapse(const Duration(seconds: 2));
      expect(store.state.user, 'u');
      expect(store.state.collectionEnabled, isFalse);
    });
  });

  test(
    'C4: user and request fields are capped; a user that is not a string is ignored on load',
    () {
      fakeAsync((FakeAsync async) {
        final Server server = Server();
        final ErrorReporter reporter = _reporter(async, server);
        reporter.setUser('u' * 1000);
        async.flushMicrotasks();
        reporter.recordError(
          StateError('x'),
          appStack,
          httpRequest: HttpRequestContext(
            url: 'https://e.example/${'a' * 10000}',
          ),
        );
        async.elapse(const Duration(seconds: 3));
        final Map<String, Object?> context =
            server.requests.single.body['context']! as Map<String, Object?>;
        expect(
          (context['user']! as String).length,
          ErrorReporter.maxUserLength,
        );
        expect(
          ((context['httpRequest']! as Map<String, Object?>)['url']! as String)
              .length,
          ErrorReporter.maxRequestFieldLength,
        );
      });
      expect(
        ErrorReportingState.fromJson(const <String, Object?>{'user': 42}).user,
        isNull,
      );
    },
  );

  group('C5: an error message cannot forge stack frames', () {
    test('line breaks in the header become a visible \\n', () {
      final FormattedError result = formatError(
        typeName: 'FormatException',
        description:
            'bad input\n    at Forged.frame (package:evil/a.dart:1:1)\r\nmore',
        stack: appStack,
        format: MessageFormat.v8,
      );
      final List<String> lines = result.message.split('\n');
      expect(
        lines.first,
        r'FormatException: bad input\n    at Forged.frame (package:evil/a.dart:1:1)\nmore',
      );
      expect(
        lines[1],
        '    at ListBase.first (dart:collection/list.dart:79:5)',
      );
      expect(result.message, isNot(contains('\n    at Forged')));
    });

    test('a type name with a line break stays on one line', () {
      final FormattedError result = formatError(
        typeName: 'Evil\n    at X.y (package:e/e.dart:1:1)',
        description: 'd',
        stack: appStack,
        format: MessageFormat.v8,
      );
      expect(
        result.message.split('\n')[1],
        startsWith('    at ListBase.first'),
      );
    });
  });

  test(
    'C7: a non-finite number from a store becomes 0; an event JSON cannot hold is dropped',
    () async {
      final Object? infinity = jsonDecode('1e999');
      final ErrorEvent event = ErrorEvent.fromStoreJson(<String, Object?>{
        'eventTime': '2026-11-28T00:00:00.000Z',
        'message': 'm',
        'reportLocation': <String, Object?>{
          'filePath': 'f',
          'lineNumber': infinity,
          'functionName': 'g',
        },
      });
      expect(event.reportLocation!.lineNumber, 0);
      final SendResult result =
          await ErrorReportingTransport.direct(apiKey: 'k').send(
            Server().client,
            newApp(),
            <String, Object?>{'message': 'm', 'n': double.infinity},
          );
      expect(
        result,
        isA<Dropped>().having((Dropped d) => d.status, 'status', 0),
      );
    },
  );

  test(
    'C8: obfuscated traces with different first frames have different fingerprints',
    () {
      String trace(String virt) =>
          "build_id: 'abc'\n#00 abs 00007f1c2b0d1e2f virt $virt _kDartIsolateSnapshotInstructions+0x1\n";
      FormattedError format(String virt) => formatError(
        typeName: 'StateError',
        description: 'x',
        stack: StackTrace.fromString(trace(virt)),
        format: MessageFormat.v8,
      );
      expect(
        format('000000000002de2f').fingerprint,
        isNot(format('000000000001ca11').fingerprint),
      );
    },
  );

  group('C9', () {
    test(
      'turning collection off while the relay fetches tokens sends nothing',
      () {
        fakeAsync((FakeAsync async) {
          final Server server = Server();
          final _SlowAppCheck appCheck = _SlowAppCheck();
          final FirebaseApp app = newApp()..appCheckProvider = appCheck;
          final ErrorReporter reporter = _reporter(
            async,
            server,
            app: app,
            transport: ErrorReportingTransport.relay(
              Uri.parse('https://example.com/e'),
            ),
          );
          reporter.recordError(StateError('x'), appStack);
          async.elapse(const Duration(seconds: 3));
          reporter.setCollectionEnabled(false);
          async.flushMicrotasks();
          appCheck.result.complete(
            const AppCheckTokenResult('app-check-token'),
          );
          async.elapse(const Duration(seconds: 1));
          expect(server.requests, isEmpty);
        });
      },
    );

    test('a token provider that never answers times out', () {
      fakeAsync((FakeAsync async) {
        final FirebaseApp app = newApp()..appCheckProvider = _SlowAppCheck();
        SendResult? result;
        ErrorReportingTransport.relay(Uri.parse('https://example.com/e'))
            .send(Server().client, app, <String, Object?>{})
            .then((SendResult r) => result = r);
        async.elapse(tokenTimeout + const Duration(seconds: 1));
        expect(result, isA<RetryLater>());
      });
    });
  });

  test('C10: a diagnostic sink that throws does not break the reporter', () {
    fakeAsync((FakeAsync async) {
      final ErrorReporter reporter = _reporter(
        async,
        Server(),
        onDiagnostic: (_) => throw StateError('sink'),
      );
      Object? failure;
      reporter
          .close()
          .then((_) => reporter.recordError(StateError('x'), appStack))
          .catchError((Object e) => failure = e);
      async.elapse(const Duration(seconds: 1));
      expect(failure, isNull);
    });
  });

  test('C11: cutting a header does not split a surrogate pair', () {
    final FormattedError result = formatError(
      typeName: 'E',
      description: '😀' * 5000,
      stack: null,
      format: MessageFormat.v8,
    );
    final String header = result.message.split('\n').first;
    final int last = header.codeUnitAt(header.length - 2);
    expect(last >= 0xd800 && last <= 0xdbff, isFalse);
  });

  group('P2: the relay pauses instead of dropping', () {
    test(
      'a 401 or 403 from the relay pauses the queue for five minutes',
      () async {
        for (final int status in <int>[401, 403]) {
          final SendResult result = await ErrorReportingTransport.relay(
            Uri.parse('https://example.com/e'),
          ).send(Server(<int>[status]).client, newApp(), <String, Object?>{});
          expect(
            result,
            isA<RetryLater>().having(
              (RetryLater r) => r.after,
              'after',
              relayRefusalPause,
            ),
          );
        }
      },
    );

    test(
      'a configured App Check provider that fails is retried, not sent without the token',
      () async {
        final Server server = Server();
        final FirebaseApp app = newApp()
          ..appCheckProvider = FakeAppCheck(
            const AppCheckTokenResult(''),
            error: StateError('down'),
          );
        final SendResult result = await ErrorReportingTransport.relay(
          Uri.parse('https://example.com/e'),
        ).send(server.client, app, <String, Object?>{});
        expect(result, isA<RetryLater>());
        expect(server.requests, isEmpty);
      },
    );
  });

  test('P3: the request is aborted at the deadline', () {
    fakeAsync((FakeAsync async) {
      http.BaseRequest? sent;
      final http.Client client = MockClient.streaming((
        http.BaseRequest request,
        http.ByteStream body,
      ) {
        sent = request;
        return Completer<http.StreamedResponse>().future;
      });
      ErrorReportingTransport.direct(
        apiKey: 'k',
      ).send(client, newApp(), <String, Object?>{});
      async.flushMicrotasks();
      expect(sent, isA<http.Abortable>());
      bool aborted = false;
      (sent! as http.Abortable).abortTrigger!.then((_) => aborted = true);
      async.elapse(requestTimeout - const Duration(seconds: 1));
      expect(aborted, isFalse);
      async.elapse(const Duration(seconds: 2));
      expect(aborted, isTrue);
    });
  });

  test('P4: the rate limit forgets kinds after a minute', () {
    fakeAsync((FakeAsync async) {
      final ErrorReporter reporter = _reporter(async, Server(<int>[503]));
      for (int i = 0; i < 25; i++) {
        reporter.recordError(StateError('e$i'), _stackAt(i + 1));
      }
      async.flushMicrotasks();
      expect(reporter.trackedKinds, 25);
      async.elapse(const Duration(minutes: 2));
      reporter.recordError(StateError('later'), _stackAt(999));
      async.flushMicrotasks();
      expect(reporter.trackedKinds, 1);
    });
  });

  test('P5: a refusal that echoes the token is logged without it', () {
    fakeAsync((FakeAsync async) {
      final List<String> logs = <String>[];
      final Server server = Server(<int>[400])
        ..responseBody =
            'bad request; Authorization: Bearer ya29.secret-token-value';
      final ErrorReporter reporter = _reporter(
        async,
        server,
        transport: ErrorReportingTransport.direct(
          credentials: FakeAuth(<String>['ya29.secret-token-value']),
        ),
        logs: logs,
      );
      reporter.recordError(StateError('x'), appStack);
      async.elapse(const Duration(seconds: 3));
      expect(logs.join('\n'), contains('<redacted>'));
      expect(logs.join('\n'), isNot(contains('ya29.secret-token-value')));
    });
  });

  test('P7: a token a header cannot hold is not sent', () async {
    final Server server = Server();
    final SendResult result = await ErrorReportingTransport.direct(
      credentials: FakeAuth(<String>['token\r\nX-Injected: 1']),
    ).send(server.client, newApp(), <String, Object?>{});
    expect(result, isA<RetryLater>());
    expect(server.requests, isEmpty);
  });

  test(
    'P9: an event that always fails is dropped after ten attempts and the queue moves on',
    () {
      fakeAsync((FakeAsync async) {
        final List<String> logs = <String>[];
        int calls = 0;
        final http.Client client = MockClient((http.Request request) async {
          calls++;
          final String message =
              (jsonDecode(request.body) as Map<String, Object?>)['message']!
                  as String;
          return http.Response('', message.contains('poison') ? 500 : 200);
        });
        final ErrorReporter reporter = ErrorReporter(
          newApp(),
          service: 's',
          transport: ErrorReportingTransport.direct(apiKey: 'k'),
          httpClient: client,
          clock: () => _start.add(async.elapsed),
          random: _NoJitter(),
          onDiagnostic: logs.add,
        );
        reporter.recordError(StateError('poison'), _stackAt(1));
        reporter.recordError(StateError('fine'), _stackAt(2));
        async.elapse(const Duration(hours: 1));
        expect(reporter.pendingCount, 0);
        expect(calls, ErrorReporter.maxAttemptsPerEvent + 1);
        expect(logs, contains(contains('failed 10 times')));
      });
    },
  );

  test(
    'P10: an error recorded while a send is in flight does not cut the backoff short',
    () {
      fakeAsync((FakeAsync async) {
        int calls = 0;
        final http.Client client = MockClient((http.Request request) async {
          calls++;
          await Future<void>.delayed(const Duration(seconds: 1));
          return http.Response(
            '',
            calls == 1 ? 503 : 200,
            headers: <String, String>{'retry-after': '60'},
          );
        });
        final ErrorReporter reporter = ErrorReporter(
          newApp(),
          service: 's',
          transport: ErrorReportingTransport.direct(apiKey: 'k'),
          httpClient: client,
          clock: () => _start.add(async.elapsed),
          random: _NoJitter(),
          onDiagnostic: (_) {},
        );
        reporter.recordError(StateError('a'), _stackAt(1));
        // The first request goes out at 2 s and is answered at 3 s; b is recorded in between.
        async.elapse(const Duration(milliseconds: 2500));
        reporter.recordError(StateError('b'), _stackAt(2));
        async.elapse(const Duration(seconds: 30));
        expect(calls, 1);
        async.elapse(const Duration(seconds: 35));
        expect(calls, greaterThan(1));
      });
    },
  );

  test('P11: a store loaded with collection off loses its saved queue', () {
    fakeAsync((FakeAsync async) {
      final _SlowStore store = _SlowStore(
        ErrorReportingState(
          collectionEnabled: false,
          queue: <ErrorEvent>[
            ErrorEvent(eventTime: _start, message: 'm', fingerprint: 'f'),
          ],
        ),
      );
      store.release.complete();
      _reporter(async, Server(), store: store);
      async.flushMicrotasks();
      expect(store.state.queue, isEmpty);
    });
  });

  test(
    'P12: an isolate error without a stack gets no stack of the reporter',
    () {
      fakeAsync((FakeAsync async) {
        final Server server = Server();
        final ErrorReporter reporter = _reporter(async, server);
        reporter.recordErrorText('Bad state: x', '');
        async.elapse(const Duration(seconds: 3));
        expect(server.requests.single.message, 'Error: Bad state: x');
      });
    },
  );

  test('P13: octets above 255 are not a loopback host', () {
    expect(mayCarryTokens(Uri.parse('http://127.999.1.1/')), isFalse);
    expect(mayCarryTokens(Uri.parse('http://127.0.0.1/')), isTrue);
  });
}
