// Regression tests for the findings of the independent review of the client core (transport, queue,
// persistence). Each test failed before its fix. The names keep the review's numbers.
//
// Not covered on purpose: a request that times out after the endpoint accepted it is sent again. The
// Measurement Protocol cannot recognise a repeated request, so delivery is at least once (see
// AnalyticsSender.send).
//
// The "1e999" tests run on the VM, where the number decodes as a double, and in the browser leg, where it
// decodes as an infinite int that passes `is int` (design rule 9).

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_analytics_dart/firebase_analytics_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

int _n = 0;
FirebaseApp _app() => FirebaseApp.withOptions(
  const FirebaseOptions(apiKey: 'k', appId: '1:1:web:a', projectId: 'p'),
  name: 'rev-${_n++}',
);

class _SlowAuth extends AuthTokenProvider {
  final Completer<void> gate = Completer<void>();
  final Completer<void> asked = Completer<void>();
  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    if (!asked.isCompleted) {
      asked.complete();
    }
    await gate.future;
    return GetTokenResult('tok');
  }

  @override
  String? get uid => 'u';
  @override
  Stream<AuthTokenChange> get onTokenChanged => const Stream.empty();
}

class _MapStore implements AnalyticsStore {
  final Map<String, String> values = <String, String>{};
  Duration writeDelay = Duration.zero;
  int failReads = 0;
  @override
  Future<String?> read(String key) async {
    if (failReads > 0) {
      failReads--;
      throw StateError('busy');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String? value) async {
    if (writeDelay > Duration.zero) {
      await Future<void>.delayed(writeDelay);
    }
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

void main() {
  test('1 request leaves after analytics storage was denied', () async {
    final app = _app();
    final auth = _SlowAuth();
    app.authProvider = auth;
    final reqs = <http.Request>[];
    final a = FirebaseAnalytics(
      app,
      measurementId: 'G-TEST1234',
      transport: AnalyticsTransport.relay(Uri.parse('https://r.example/c')),
      onWarning: (_) {},
      httpClient: MockClient((r) async {
        reqs.add(r);
        return http.Response('', 204);
      }),
    );
    await a.logEvent(name: 'level_up');
    final f = a.flush();
    await auth.asked.future;
    await a.setConsent(analyticsStorage: false);
    expect(reqs, isEmpty);
    auth.gate.complete();
    await f;
    expect(reqs, isEmpty, reason: 'sent after consent was denied');
  });

  test('2 a stalled answer body hangs flush forever', () {
    fakeAsync((fa) {
      final a = FirebaseAnalytics(
        _app(),
        measurementId: 'G-TEST1234',
        transport: AnalyticsTransport.direct(apiSecret: 's'),
        onWarning: (_) {},
        httpClient: _StallClient(),
      );
      bool done = false;
      a
          .logEvent(name: 'level_up')
          .then((_) => a.flush())
          .then((_) => done = true);
      fa.elapse(const Duration(hours: 24));
      expect(done, isTrue, reason: 'flush still pending after 24h');
    });
  });

  test('3 flush racing close throws StateError', () async {
    final store = _MapStore()..writeDelay = const Duration(milliseconds: 50);
    final a = FirebaseAnalytics(
      _app(),
      measurementId: 'G-TEST1234',
      transport: AnalyticsTransport.direct(apiSecret: 's'),
      store: store,
      onWarning: (_) {},
      httpClient: MockClient((r) async => http.Response('', 204)),
    );
    await a.logEvent(name: 'level_up');
    final closing = a.close();
    Object? error;
    // Poll: call flush at several moments while close is running.
    for (int i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      try {
        await a.flush();
      } catch (e) {
        error = e;
        break;
      }
    }
    await closing;
    expect(error, isNull, reason: 'flush is documented to do nothing');
  });

  test('4 a request is sent after close() returned', () async {
    final reqs = <http.Request>[];
    final gate = Completer<void>();
    late FirebaseAnalytics a;
    a = FirebaseAnalytics(
      _app(),
      measurementId: 'G-TEST1234',
      transport: AnalyticsTransport.direct(apiSecret: 's'),
      onWarning: (_) {},
      httpClient: MockClient((r) async {
        reqs.add(r);
        if (reqs.length == 1) {
          await gate.future;
        }
        return http.Response('', 204);
      }),
    );
    await a.logEvent(name: 'first');
    final closing = a.close(); // flush: request 1 in flight
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // 60 more events while close waits for the request.
    final logs = <Future<void>>[
      for (int i = 0; i < 60; i++) a.logEvent(name: 'e$i'),
    ];
    gate.complete();
    await closing;
    final atClose = reqs.length;
    await Future.wait(logs.map((f) => f.catchError((_) {})));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(reqs.length, atClose, reason: 'requests after close returned');
  });

  test(
    '5 reset then crash: old user events go out under the new client id',
    () async {
      final store = _MapStore();
      final a = FirebaseAnalytics(
        _app(),
        measurementId: 'G-TEST1234',
        transport: AnalyticsTransport.direct(apiSecret: 's'),
        store: store,
        onWarning: (_) {},
        httpClient: MockClient((r) async => http.Response('', 503)),
      );
      await a.setUserId('alice');
      await a.logEvent(name: 'level_up');
      await a.flush(); // persisted queue
      final oldId = await a.appInstanceId;
      await a.resetAnalyticsData();
      final newId = await a.appInstanceId;
      expect(newId, isNot(oldId));
      // "Crash" now: copy the store as it is on disk at this moment.
      final crashed = _MapStore()..values.addAll(store.values);
      final reqs = <http.Request>[];
      final b = FirebaseAnalytics(
        FirebaseApp.withOptions(
          const FirebaseOptions(
            apiKey: 'k',
            appId: '1:1:web:a',
            projectId: 'p',
          ),
          name: '${a.app.name}x',
        ),
        measurementId: 'G-TEST1234',
        transport: AnalyticsTransport.direct(apiSecret: 's'),
        store: _Rekey(crashed, a.app.name),
        onWarning: (_) {},
        httpClient: MockClient((r) async {
          reqs.add(r);
          return http.Response('', 204);
        }),
      );
      await b.flush();
      expect(reqs.map((r) => r.body).join(), isNot(contains('alice')));
    },
  );

  test('6 one failed read turns a stored opt-out into collection', () async {
    final store = _MapStore();
    final app = _app();
    FirebaseAnalytics make(List<http.Request> reqs) => FirebaseAnalytics(
      app,
      measurementId: 'G-TEST1234',
      transport: AnalyticsTransport.direct(apiSecret: 's'),
      store: store,
      onWarning: (_) {},
      httpClient: MockClient((r) async {
        reqs.add(r);
        return http.Response('', 204);
      }),
    );
    final a = make([]);
    await a.setAnalyticsCollectionEnabled(false);
    await a.setConsent(analyticsStorage: false);
    await a.close();
    store.failReads = 1;
    final reqs = <http.Request>[];
    final b = make(reqs);
    await b.logEvent(name: 'level_up');
    await b.flush();
    expect(reqs, isEmpty, reason: 'user had opted out');
    await b.close();
    final c = make(reqs);
    expect(
      await c.sessionId,
      isNull,
      reason: 'opt-out was overwritten in the store',
    );
  });

  test('7 nothing retries after a failed flush', () {
    fakeAsync((fa) {
      int? status;
      final reqs = <http.Request>[];
      final a = FirebaseAnalytics(
        _app(),
        measurementId: 'G-TEST1234',
        transport: AnalyticsTransport.direct(apiSecret: 's'),
        onWarning: (_) {},
        clock: () => DateTime.utc(2026).add(fa.elapsed),
        random: Random(1),
        httpClient: MockClient((r) async {
          reqs.add(r);
          if (status == null) {
            throw http.ClientException('down');
          }
          return http.Response('', status);
        }),
      );
      a.logEvent(name: 'level_up');
      fa.flushMicrotasks();
      a.setAppActive(false); // flush, fails
      fa.flushMicrotasks();
      expect(reqs, hasLength(1));
      status = 204;
      fa.elapse(const Duration(hours: 6));
      expect(reqs.length, greaterThan(1), reason: 'never retried in 6 hours');
    });
  });

  test(
    '8 tampered store: future timestamp and huge session id are sent',
    () async {
      final store = _MapStore();
      final app = _app();
      store.values['${app.name}/G-TEST1234/queue'] = jsonEncode([
        {
          'n': 'level_up',
          'p': {'session_id': 9007199254740993000, 'engagement_time_msec': 1},
          't': 4102444800000000 * 100,
          'x': <String, Object>{},
        },
      ]);
      final reqs = <http.Request>[];
      final a = FirebaseAnalytics(
        app,
        measurementId: 'G-TEST1234',
        transport: AnalyticsTransport.direct(apiSecret: 's'),
        store: store,
        onWarning: (_) {},
        httpClient: MockClient((r) async {
          reqs.add(r);
          return http.Response('', 204);
        }),
      );
      await a.flush();
      expect(reqs, isEmpty, reason: reqs.isEmpty ? '' : reqs.single.body);
    },
  );

  test('9 a throwing onWarning', () async {
    final errors = <Object>[];
    await runZonedGuarded(() async {
      final a = FirebaseAnalytics(
        _app(),
        measurementId: 'G-TEST1234',
        transport: AnalyticsTransport.direct(apiSecret: 's'),
        onWarning: (m) => throw StateError('logger broke'),
        batchDelay: Duration.zero,
        httpClient: MockClient((r) async => http.Response('', 503)),
      );
      await a.logEvent(name: 'level_up');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }, (e, s) => errors.add(e));
    expect(errors, isEmpty);
  });

  test('4b a request is sent after close() returned', () async {
    final reqs = <http.Request>[];
    bool closed = false;
    final afterClose = <http.Request>[];
    final a = FirebaseAnalytics(
      FirebaseApp.withOptions(
        const FirebaseOptions(apiKey: 'k', appId: '1:1:web:a', projectId: 'p'),
        name: 'rev-${_n++}',
      ),
      measurementId: 'G-TEST1234',
      transport: AnalyticsTransport.direct(apiSecret: 's'),
      store: _MapStore()..writeDelay = const Duration(milliseconds: 20),
      onWarning: (_) {},
      httpClient: MockClient((r) async {
        reqs.add(r);
        if (closed) {
          afterClose.add(r);
        }
        return http.Response('', 204);
      }),
    );
    await a.logEvent(name: 'first');
    final closing = a.close().then((_) => closed = true);
    // Wait until the flush inside close has delivered and is saving the queue.
    while (reqs.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final logs = <Future<void>>[
      for (int i = 0; i < 25; i++) a.logEvent(name: 'e$i').catchError((_) {}),
    ];
    await closing;
    await Future.wait(logs);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(afterClose, isEmpty, reason: 'requests after close returned');
  });

  test('w1 a stored event dated 1e999 does not stop sending', () async {
    final store = _MapStore();
    final app = FirebaseApp.withOptions(
      const FirebaseOptions(apiKey: 'k', appId: '1:1:web:a', projectId: 'p'),
      name: 'rev-${_n++}',
    );
    store.values['${app.name}/G-TEST1234/queue'] =
        '[{"n":"level_up","p":{"session_id":1,"engagement_time_msec":1},"t":1e999,"x":{}}]';
    final reqs = <http.Request>[];
    final warnings = <String>[];
    final a = FirebaseAnalytics(
      app,
      measurementId: 'G-TEST1234',
      transport: AnalyticsTransport.direct(apiSecret: 's'),
      store: store,
      onWarning: warnings.add,
      httpClient: MockClient((r) async {
        reqs.add(r);
        return http.Response('', 204);
      }),
    );
    await a.logEvent(name: 'good');
    await a.flush();
    expect(reqs.map((r) => r.body).join(), contains('good'));
  });

  test('w2 a stored session id of 1e999 does not break logEvent', () async {
    final store = _MapStore();
    final app = FirebaseApp.withOptions(
      const FirebaseOptions(apiKey: 'k', appId: '1:1:web:a', projectId: 'p'),
      name: 'rev-${_n++}',
    );
    store.values['${app.name}/G-TEST1234/state'] =
        '{"v":1,"sessionId":1e999,"lastEventMicros":${DateTime.now().microsecondsSinceEpoch}}';
    final warnings = <String>[];
    final a = FirebaseAnalytics(
      app,
      measurementId: 'G-TEST1234',
      transport: AnalyticsTransport.direct(apiSecret: 's'),
      store: store,
      onWarning: warnings.add,
      httpClient: MockClient((r) async => http.Response('', 204)),
    );
    await a.logEvent(name: 'good');
    await a.flush();
    expect(warnings.any((String w) => w.contains('session')), isTrue);
  });
}

class _Rekey implements AnalyticsStore {
  _Rekey(this.inner, this.name);
  final _MapStore inner;
  final String name;
  String k(String key) => '$name/${key.split('/').skip(1).join('/')}';
  @override
  Future<String?> read(String key) => inner.read(k(key));
  @override
  Future<void> write(String key, String? value) => inner.write(k(key), value);
}

class _StallClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    return http.StreamedResponse(StreamController<List<int>>().stream, 200);
  }
}
