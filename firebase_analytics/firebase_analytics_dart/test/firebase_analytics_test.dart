import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_analytics_dart/firebase_analytics_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

int _appCount = 0;

const String _measurementId = 'G-TEST1234';
const String _appId = '1:123:dart:abc';

FirebaseApp _newApp({String? measurementId}) => FirebaseApp.withOptions(
  FirebaseOptions(
    apiKey: 'key',
    appId: _appId,
    projectId: 'demo-test',
    measurementId: measurementId,
  ),
  name: 'analytics-test-${_appCount++}',
);

/// The fake start of every test.
final DateTime _start = DateTime.utc(2026, 3, 1, 12);

final RegExp _clientIdPattern = RegExp(r'^\d+\.\d+$');

/// One request the mock client received.
class _Sent {
  _Sent(this.request, this.at, this.status);

  final http.Request request;

  /// The fake time it was sent at.
  final Duration at;

  /// The answer, or null for a network error.
  final int? status;

  Map<String, Object?> get body =>
      jsonDecode(request.body) as Map<String, Object?>;

  List<Map<String, Object?>> get events => <Map<String, Object?>>[
    for (final Object? e in body['events']! as List) e! as Map<String, Object?>,
  ];

  List<String> get names => <String>[
    for (final Map<String, Object?> e in events) e['name']! as String,
  ];
}

class _ThrowingStore implements AnalyticsStore {
  @override
  Future<String?> read(String key) async => throw StateError('read');

  @override
  Future<void> write(String key, String? value) async =>
      throw StateError('write');
}

/// Everything one test drives: fake time, the mock client and the warnings.
class _Env {
  _Env(this.fa, this.app);

  final FakeAsync fa;
  final FirebaseApp app;
  final List<_Sent> sent = <_Sent>[];
  final List<String> warnings = <String>[];

  /// The status the mock client answers; null makes it throw a network error.
  int? status = 204;

  late final MockClient client = MockClient((http.Request request) async {
    final int? answer = status;
    sent.add(_Sent(request, fa.elapsed, answer));
    if (answer == null) {
      throw http.ClientException('network down');
    }
    return http.Response('', answer);
  });

  DateTime now() => _start.add(fa.elapsed);

  /// The requests that were answered with 2xx.
  List<_Sent> get delivered => <_Sent>[
    for (final _Sent s in sent)
      if (s.status != null && s.status! >= 200 && s.status! < 300) s,
  ];

  /// The events of every delivered request.
  List<Map<String, Object?>> get deliveredEvents => <Map<String, Object?>>[
    for (final _Sent s in delivered) ...s.events,
  ];

  FirebaseAnalytics create({
    AnalyticsStore? store,
    FirebaseApp? app,
    String? measurementId = _measurementId,
    AnalyticsRegion region = AnalyticsRegion.global,
    bool collectionEnabledByDefault = true,
    int maxQueuedEvents = 1000,
    Duration sessionTimeout = const Duration(minutes: 30),
    AnalyticsDevice? device,
    int seed = 7,
  }) => FirebaseAnalytics(
    app ?? this.app,
    measurementId: measurementId,
    transport: AnalyticsTransport.direct(apiSecret: 'secret123'),
    store: store ?? AnalyticsStore.memory(),
    region: region,
    collectionEnabledByDefault: collectionEnabledByDefault,
    maxQueuedEvents: maxQueuedEvents,
    sessionTimeout: sessionTimeout,
    device: device,
    onWarning: warnings.add,
    httpClient: client,
    clock: now,
    random: Random(seed),
  );

  /// Runs microtasks until [future] completes and returns its value.
  T wait<T>(Future<T> future) {
    bool done = false;
    late T value;
    Object? error;
    StackTrace? stack;
    future.then(
      (T v) {
        value = v;
        done = true;
      },
      onError: (Object e, StackTrace s) {
        error = e;
        stack = s;
        done = true;
      },
    );
    fa.flushMicrotasks();
    if (!done) {
      fail('The future did not complete.');
    }
    if (error != null) {
      Error.throwWithStackTrace(error!, stack!);
    }
    return value;
  }

  /// Runs microtasks until [future] fails and returns the error.
  Object error(Future<Object?> future) {
    try {
      wait(future);
    } on TestFailure {
      rethrow;
    } on Object catch (e) {
      return e;
    }
    fail('The future did not fail.');
  }
}

void main() {
  late FirebaseApp app;

  setUp(() => app = _newApp());
  tearDown(() => app.delete());

  void fakeTest(String name, void Function(_Env env) body, {String? skip}) {
    test(name, () {
      fakeAsync((FakeAsync fa) => body(_Env(fa, app)));
    }, skip: skip);
  }

  group('request', () {
    fakeTest('direct goes to the global endpoint with the secret', (_Env env) {
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'level_up'));
      env.wait(analytics.flush());

      final http.Request request = env.sent.single.request;
      expect(request.method, 'POST');
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'www.google-analytics.com');
      expect(request.url.path, '/mp/collect');
      expect(request.url.queryParameters, <String, String>{
        'measurement_id': _measurementId,
        'api_secret': 'secret123',
      });
      expect(request.headers['Content-Type'], startsWith('application/json'));
    });

    fakeTest('AnalyticsRegion.eu goes to region1', (_Env env) {
      final FirebaseAnalytics analytics = env.create(
        region: AnalyticsRegion.eu,
      );
      env.wait(analytics.logEvent(name: 'level_up'));
      env.wait(analytics.flush());

      final Uri url = env.sent.single.request.url;
      expect(url.host, 'region1.google-analytics.com');
      expect(url.path, '/mp/collect');
      expect(url.queryParameters['measurement_id'], _measurementId);
      expect(url.queryParameters['api_secret'], 'secret123');
    });

    fakeTest('the body', (_Env env) {
      final FirebaseAnalytics analytics = env.create(
        device: const AnalyticsDevice(category: 'desktop', model: 'Test Box'),
      );
      env.wait(analytics.setUserId('user-1'));
      env.wait(analytics.setUserProperty(name: 'plan', value: 'pro'));
      env.wait(
        analytics.logEvent(
          name: 'level_up',
          parameters: <String, Object?>{'level': 3},
        ),
      );
      env.wait(analytics.flush());

      final Map<String, Object?> body = env.sent.single.body;
      expect(body['client_id'], matches(_clientIdPattern));
      expect(body['client_id'], env.wait(analytics.appInstanceId));
      expect(body['user_id'], 'user-1');
      expect(body['user_properties'], <String, Object?>{
        'plan': <String, Object?>{'value': 'pro'},
      });
      expect(body.containsKey('consent'), isFalse);
      final Map<String, Object?> device =
          body['device']! as Map<String, Object?>;
      expect(device['category'], 'desktop');
      expect(device['model'], 'Test Box');

      final Map<String, Object?> event = env.sent.single.events.single;
      expect(event['name'], 'level_up');
      expect(event['timestamp_micros'], _start.microsecondsSinceEpoch);
      final Map<String, Object?> params =
          event['params']! as Map<String, Object?>;
      expect(params['level'], 3);
      expect(params['session_id'], _start.millisecondsSinceEpoch ~/ 1000);
      expect(params['engagement_time_msec'], greaterThanOrEqualTo(1));
    });

    fakeTest('consent is sent only after setConsent', (_Env env) {
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'before'));
      env.wait(
        analytics.setConsent(adUserData: true, adPersonalization: false),
      );
      env.wait(analytics.logEvent(name: 'after'));
      env.wait(analytics.flush());

      expect(env.sent, hasLength(2));
      expect(env.sent[0].names, <String>['before']);
      expect(env.sent[0].body.containsKey('consent'), isFalse);
      expect(env.sent[1].names, <String>['after']);
      expect(env.sent[1].body['consent'], <String, Object?>{
        'ad_user_data': 'GRANTED',
        'ad_personalization': 'DENIED',
      });
    });

    fakeTest('the client id is kept between requests', (_Env env) {
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'a'));
      env.wait(analytics.flush());
      env.fa.elapse(const Duration(minutes: 1));
      env.wait(analytics.logEvent(name: 'b'));
      env.wait(analytics.flush());
      expect(env.sent, hasLength(2));
      expect(env.sent[0].body['client_id'], env.sent[1].body['client_id']);
    });
  });

  group('batching', () {
    fakeTest('a batch goes batchDelay after its first event', (_Env env) {
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'a'));
      env.fa.elapse(const Duration(seconds: 2));
      env.wait(analytics.logEvent(name: 'b'));
      env.fa.elapse(const Duration(milliseconds: 2999));
      expect(env.sent, isEmpty);
      env.fa.elapse(const Duration(milliseconds: 1));
      expect(env.sent, hasLength(1));
      expect(env.sent.single.at, const Duration(seconds: 5));
      expect(env.sent.single.names, <String>['a', 'b']);
      env.fa.elapse(const Duration(minutes: 1));
      expect(env.sent, hasLength(1));
    });

    fakeTest('25 events go at once', (_Env env) {
      final FirebaseAnalytics analytics = env.create();
      for (int i = 0; i < 25; i++) {
        env.wait(analytics.logEvent(name: 'e$i'));
      }
      env.fa.flushMicrotasks();
      expect(env.sent, hasLength(1));
      expect(env.sent.single.at, Duration.zero);
      expect(env.sent.single.events, hasLength(25));
    });

    fakeTest('30 events make two requests of 25 and 5', (_Env env) {
      final FirebaseAnalytics analytics = env.create();
      for (int i = 0; i < 30; i++) {
        env.wait(analytics.logEvent(name: 'e$i'));
      }
      env.fa.elapse(const Duration(seconds: 6));
      expect(env.sent, hasLength(2));
      expect(env.sent[0].events, hasLength(25));
      expect(env.sent[1].events, hasLength(5));
      expect(
        <String>[...env.sent[0].names, ...env.sent[1].names],
        <String>[for (int i = 0; i < 30; i++) 'e$i'],
      );
    });

    fakeTest('flush sends at once', (_Env env) {
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'a'));
      env.wait(analytics.flush());
      expect(env.sent, hasLength(1));
      expect(env.sent.single.at, Duration.zero);
      expect(env.wait(analytics.queuedEventCount), 0);
      env.fa.elapse(const Duration(minutes: 1));
      expect(env.sent, hasLength(1));
    });

    fakeTest('close flushes and later calls throw StateError', (_Env env) {
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'a'));
      env.wait(analytics.close());
      expect(env.sent, hasLength(1));
      expect(env.sent.single.names, <String>['a']);

      expect(env.error(analytics.logEvent(name: 'b')), isA<StateError>());
      expect(env.error(analytics.setUserId('u')), isA<StateError>());
      expect(
        env.error(analytics.setUserProperty(name: 'p', value: 'v')),
        isA<StateError>(),
      );
      expect(env.error(analytics.appInstanceId), isA<StateError>());
      // flush, close and setAppActive do nothing.
      env.wait(analytics.flush());
      env.wait(analytics.close());
      analytics.setAppActive(false);
      env.fa.elapse(const Duration(minutes: 1));
      expect(env.sent, hasLength(1));
    });
  });

  fakeTest('events before and after setUserId go in separate requests', (
    _Env env,
  ) {
    final FirebaseAnalytics analytics = env.create();
    env.wait(analytics.logEvent(name: 'anonymous'));
    env.wait(analytics.setUserId('u1'));
    env.wait(analytics.logEvent(name: 'signed_in_1'));
    env.wait(analytics.logEvent(name: 'signed_in_2'));
    env.wait(analytics.setUserId('u2'));
    env.wait(analytics.logEvent(name: 'other_user'));
    env.fa.elapse(const Duration(seconds: 6));

    expect(env.sent, hasLength(3));
    expect(env.sent[0].names, <String>['anonymous']);
    expect(env.sent[0].body.containsKey('user_id'), isFalse);
    expect(env.sent[1].names, <String>['signed_in_1', 'signed_in_2']);
    expect(env.sent[1].body['user_id'], 'u1');
    expect(env.sent[2].names, <String>['other_user']);
    expect(env.sent[2].body['user_id'], 'u2');
  });

  group('sessions', () {
    Map<String, Object?> params(Map<String, Object?> event) =>
        event['params']! as Map<String, Object?>;

    fakeTest('session_id is the first event time and expires after the '
        'timeout', (_Env env) {
      final FirebaseAnalytics analytics = env.create();
      expect(env.wait(analytics.sessionId), isNull);

      env.wait(analytics.logEvent(name: 'a'));
      final int first = _start.millisecondsSinceEpoch ~/ 1000;
      expect(env.wait(analytics.sessionId), first);

      env.fa.elapse(const Duration(minutes: 20));
      env.wait(analytics.logEvent(name: 'b'));
      // Exactly the timeout after the previous event is still within it.
      env.fa.elapse(const Duration(minutes: 30));
      expect(env.wait(analytics.sessionId), first);
      env.wait(analytics.logEvent(name: 'c'));

      env.fa.elapse(const Duration(minutes: 30, seconds: 1));
      expect(env.wait(analytics.sessionId), isNull);
      env.wait(analytics.logEvent(name: 'd'));
      final int second = env.now().millisecondsSinceEpoch ~/ 1000;
      expect(env.wait(analytics.sessionId), second);
      env.wait(analytics.flush());

      final List<Map<String, Object?>> events = env.deliveredEvents;
      expect(
        <Object?>[
          for (final Map<String, Object?> e in events) params(e)['session_id'],
        ],
        <int>[first, first, first, second],
      );
    });

    fakeTest('engagement time counts active time since the previous event', (
      _Env env,
    ) {
      final FirebaseAnalytics analytics = env.create();
      // Logged at the moment the client was made: at least 1.
      env.wait(analytics.logEvent(name: 'a'));

      env.fa.elapse(const Duration(seconds: 10));
      env.wait(analytics.logEvent(name: 'b'));

      env.fa.elapse(const Duration(seconds: 3));
      analytics.setAppActive(false);
      env.fa.elapse(const Duration(seconds: 20));
      analytics.setAppActive(true);
      env.fa.elapse(const Duration(seconds: 2));
      env.wait(analytics.logEvent(name: 'c'));

      // More than the session timeout: capped.
      env.fa.elapse(const Duration(hours: 2));
      env.wait(analytics.logEvent(name: 'd'));
      env.wait(analytics.flush());

      final Map<String, int> engagement = <String, int>{
        for (final Map<String, Object?> e in env.deliveredEvents)
          e['name']! as String: params(e)['engagement_time_msec']! as int,
      };
      expect(engagement, <String, int>{
        'a': 1,
        'b': 10000,
        'c': 5000,
        'd': const Duration(minutes: 30).inMilliseconds,
      });
    });

    fakeTest('engagement time is at least 1 for events at the same instant', (
      _Env env,
    ) {
      final FirebaseAnalytics analytics = env.create();
      env.fa.elapse(const Duration(seconds: 1));
      env.wait(analytics.logEvent(name: 'a'));
      env.wait(analytics.logEvent(name: 'b'));
      env.wait(analytics.flush());
      final List<Map<String, Object?>> events = env.deliveredEvents;
      expect(params(events[0])['engagement_time_msec'], 1000);
      expect(params(events[1])['engagement_time_msec'], 1);
    });
  });

  group('retries', () {
    fakeTest('a 503 keeps the events and retries with growing delays', (
      _Env env,
    ) {
      env.status = 503;
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'a'));
      env.fa.elapse(const Duration(seconds: 5));
      expect(env.sent, hasLength(1));
      env.fa.elapse(const Duration(milliseconds: 999));
      expect(env.sent, hasLength(1), reason: 'the first retry waits >= 1 s');

      env.fa.elapse(const Duration(minutes: 1));
      final int count = env.sent.length;
      expect(count, inInclusiveRange(4, 7));
      final List<Duration> gaps = <Duration>[
        for (int i = 1; i < env.sent.length; i++)
          env.sent[i].at - env.sent[i - 1].at,
      ];
      // Failure n waits between half and all of 2 s * 2^(n-1).
      for (int i = 0; i < gaps.length; i++) {
        final int ceiling = 2000 * (1 << i);
        expect(
          gaps[i].inMilliseconds,
          inInclusiveRange(ceiling ~/ 2, ceiling),
          reason: 'gap $i',
        );
      }
      expect(gaps.last, greaterThan(gaps.first));
      for (final _Sent s in env.sent) {
        expect(s.names, <String>['a']);
      }
      expect(env.wait(analytics.queuedEventCount), 1);
      expect(env.warnings, isNotEmpty);

      // Delivered once the endpoint answers 2xx.
      env.status = 200;
      env.fa.elapse(const Duration(minutes: 10));
      expect(env.delivered, hasLength(1));
      expect(env.delivered.single.names, <String>['a']);
      expect(env.wait(analytics.queuedEventCount), 0);
      final int after = env.sent.length;
      env.fa.elapse(const Duration(hours: 1));
      expect(env.sent, hasLength(after));
    });

    fakeTest('retry delays stop growing at 5 minutes', (_Env env) {
      env.status = 503;
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'a'));
      env.fa.elapse(const Duration(hours: 3));
      final List<Duration> gaps = <Duration>[
        for (int i = 1; i < env.sent.length; i++)
          env.sent[i].at - env.sent[i - 1].at,
      ];
      for (final Duration gap in gaps) {
        expect(gap, lessThanOrEqualTo(const Duration(minutes: 5)));
      }
      expect(gaps.last, greaterThanOrEqualTo(const Duration(minutes: 2)));
    });

    fakeTest('a network error keeps the events and retries', (_Env env) {
      env.status = null;
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'a'));
      env.fa.elapse(const Duration(seconds: 5));
      expect(env.sent, hasLength(1));
      env.fa.elapse(const Duration(seconds: 30));
      expect(env.sent.length, greaterThan(2));
      final List<Duration> gaps = <Duration>[
        for (int i = 1; i < env.sent.length; i++)
          env.sent[i].at - env.sent[i - 1].at,
      ];
      expect(gaps.last, greaterThan(gaps.first));
      expect(env.wait(analytics.queuedEventCount), 1);
      // The warning names the error type, not its message.
      expect(
        env.warnings.any((String w) => w.contains('ClientException')),
        isTrue,
      );
      expect(env.warnings.any((String w) => w.contains('secret123')), isFalse);

      env.status = 204;
      env.fa.elapse(const Duration(minutes: 5));
      expect(env.delivered.single.names, <String>['a']);
      expect(env.wait(analytics.queuedEventCount), 0);
    });

    fakeTest('a 400 drops the batch without retrying', (_Env env) {
      env.status = 400;
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'a'));
      env.fa.elapse(const Duration(seconds: 5));
      expect(env.sent, hasLength(1));
      expect(env.warnings.any((String w) => w.contains('400')), isTrue);
      expect(env.wait(analytics.queuedEventCount), 0);
      env.fa.elapse(const Duration(hours: 1));
      expect(env.sent, hasLength(1));

      // Later events still go.
      env.status = 204;
      env.wait(analytics.logEvent(name: 'b'));
      env.wait(analytics.flush());
      expect(env.sent, hasLength(2));
      expect(env.sent.last.names, <String>['b']);
    });

    fakeTest('429 is retried', (_Env env) {
      env.status = 429;
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'a'));
      env.fa.elapse(const Duration(seconds: 10));
      expect(env.sent.length, greaterThan(1));
      expect(env.wait(analytics.queuedEventCount), 1);
    });

    fakeTest('flush after a failure completes and keeps the events', (
      _Env env,
    ) {
      env.status = 500;
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'a'));
      env.wait(analytics.flush());
      expect(env.sent, hasLength(1));
      expect(env.wait(analytics.queuedEventCount), 1);
      env.status = 204;
      env.wait(analytics.flush());
      expect(env.delivered.single.names, <String>['a']);
    });
  });

  group('event age', () {
    fakeTest('events older than 72 hours at send time are dropped', (_Env env) {
      env.status = 503;
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'old'));
      env.fa.elapse(const Duration(hours: 72, minutes: 1));
      expect(env.sent, isNotEmpty);
      env.status = 204;
      env.wait(analytics.logEvent(name: 'fresh'));
      env.wait(analytics.flush());
      env.fa.elapse(const Duration(minutes: 10));

      expect(env.delivered, isNotEmpty);
      final List<String> names = <String>[
        for (final _Sent s in env.delivered) ...s.names,
      ];
      expect(names, <String>['fresh']);
      expect(env.wait(analytics.queuedEventCount), 0);
      expect(env.warnings.any((String w) => w.contains('72 hours')), isTrue);
    });

    fakeTest('an event 71 hours old is still sent', (_Env env) {
      env.status = 503;
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'late'));
      env.fa.elapse(const Duration(hours: 71));
      env.status = 204;
      env.wait(analytics.flush());
      expect(env.delivered.single.names, <String>['late']);
      expect(
        env.delivered.single.events.single['timestamp_micros'],
        _start.microsecondsSinceEpoch,
      );
    });
  });

  group('collection', () {
    fakeTest('disabling collection drops the queue and later events', (
      _Env env,
    ) {
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'a'));
      env.wait(analytics.setAnalyticsCollectionEnabled(false));
      expect(env.wait(analytics.queuedEventCount), 0);
      env.wait(analytics.logEvent(name: 'b'));
      expect(env.wait(analytics.queuedEventCount), 0);
      expect(env.wait(analytics.sessionId), isNull);
      env.fa.elapse(const Duration(minutes: 1));
      env.wait(analytics.flush());
      expect(env.sent, isEmpty);

      env.wait(analytics.setAnalyticsCollectionEnabled(true));
      env.wait(analytics.logEvent(name: 'c'));
      env.wait(analytics.flush());
      expect(env.sent.single.names, <String>['c']);
    });

    fakeTest('collectionEnabledByDefault false sends nothing until enabled', (
      _Env env,
    ) {
      final FirebaseAnalytics analytics = env.create(
        collectionEnabledByDefault: false,
      );
      env.wait(analytics.logEvent(name: 'a'));
      env.fa.elapse(const Duration(minutes: 1));
      env.wait(analytics.flush());
      expect(env.sent, isEmpty);

      env.wait(analytics.setAnalyticsCollectionEnabled(true));
      env.wait(analytics.logEvent(name: 'b'));
      env.fa.elapse(const Duration(seconds: 5));
      expect(env.sent.single.names, <String>['b']);
    });

    fakeTest('denying analytics storage drops the queue and sends nothing', (
      _Env env,
    ) {
      final FirebaseAnalytics analytics = env.create();
      env.wait(analytics.logEvent(name: 'a'));
      expect(env.wait(analytics.appInstanceId), matches(_clientIdPattern));
      env.wait(analytics.setConsent(analyticsStorage: false));
      expect(env.wait(analytics.queuedEventCount), 0);
      expect(env.wait(analytics.appInstanceId), isNull);
      expect(env.wait(analytics.sessionId), isNull);
      env.wait(analytics.logEvent(name: 'b'));
      env.fa.elapse(const Duration(minutes: 1));
      env.wait(analytics.flush());
      expect(env.sent, isEmpty);

      // Other consent leaves analytics storage denied.
      env.wait(analytics.setConsent(adUserData: true));
      env.wait(analytics.logEvent(name: 'c'));
      env.wait(analytics.flush());
      expect(env.sent, isEmpty);

      env.wait(analytics.setConsent(analyticsStorage: true));
      env.wait(analytics.logEvent(name: 'd'));
      env.wait(analytics.flush());
      expect(env.sent.single.names, <String>['d']);
    });
  });

  group('persistence', () {
    fakeTest('a second client on the same store keeps the state and the '
        'queue', (_Env env) {
      final AnalyticsStore store = AnalyticsStore.memory();
      env.status = 503;
      final FirebaseAnalytics first = env.create(store: store);
      env.wait(first.setUserId('u1'));
      env.wait(first.setUserProperty(name: 'plan', value: 'pro'));
      env.wait(
        first.setDefaultEventParameters(<String, Object?>{
          'app_version': '1.0',
        }),
      );
      env.wait(first.setConsent(adUserData: true, adPersonalization: true));
      env.wait(first.setAnalyticsCollectionEnabled(true));
      env.wait(first.logEvent(name: 'queued'));
      final String clientId = env.wait(first.appInstanceId)!;
      env.wait(first.close());
      expect(env.delivered, isEmpty);
      final int failed = env.sent.length;

      env.status = 204;
      final FirebaseAnalytics second = env.create(
        store: store,
        collectionEnabledByDefault: false,
        seed: 99,
      );
      expect(env.wait(second.appInstanceId), clientId);
      env.fa.elapse(const Duration(seconds: 5));
      expect(env.sent.length, greaterThan(failed));
      expect(env.delivered.single.names, <String>['queued']);

      env.wait(second.logEvent(name: 'next'));
      env.wait(second.flush());
      expect(env.delivered, hasLength(2));
      final _Sent next = env.delivered.last;
      expect(next.names, <String>['next']);
      expect(next.body['client_id'], clientId);
      expect(next.body['user_id'], 'u1');
      expect(next.body['user_properties'], <String, Object?>{
        'plan': <String, Object?>{'value': 'pro'},
      });
      expect(next.body['consent'], <String, Object?>{
        'ad_user_data': 'GRANTED',
        'ad_personalization': 'GRANTED',
      });
      final Map<String, Object?> params =
          next.events.single['params']! as Map<String, Object?>;
      expect(params['app_version'], '1.0');
    });

    fakeTest('the collection switch is kept', (_Env env) {
      final AnalyticsStore store = AnalyticsStore.memory();
      final FirebaseAnalytics first = env.create(store: store);
      env.wait(first.setAnalyticsCollectionEnabled(false));
      env.wait(first.close());

      final FirebaseAnalytics second = env.create(store: store);
      env.wait(second.logEvent(name: 'a'));
      env.fa.elapse(const Duration(minutes: 1));
      env.wait(second.flush());
      expect(env.sent, isEmpty);
    });

    fakeTest('denied analytics storage is kept', (_Env env) {
      final AnalyticsStore store = AnalyticsStore.memory();
      final FirebaseAnalytics first = env.create(store: store);
      env.wait(first.setConsent(analyticsStorage: false));
      env.wait(first.close());

      final FirebaseAnalytics second = env.create(store: store);
      expect(env.wait(second.appInstanceId), isNull);
      env.wait(second.logEvent(name: 'a'));
      env.wait(second.flush());
      expect(env.sent, isEmpty);
    });

    fakeTest('another app on the same store has its own state', (_Env env) {
      final AnalyticsStore store = AnalyticsStore.memory();
      final FirebaseApp other = _newApp();
      final FirebaseAnalytics first = env.create(store: store);
      env.wait(first.setUserId('u1'));
      final String clientId = env.wait(first.appInstanceId)!;

      final FirebaseAnalytics second = env.create(
        store: store,
        app: other,
        seed: 99,
      );
      expect(env.wait(second.appInstanceId), isNot(clientId));
      env.wait(second.logEvent(name: 'a'));
      env.wait(second.flush());
      expect(env.sent.single.body.containsKey('user_id'), isFalse);
      unawaited(other.delete());
    });
  });

  group('corrupt store', () {
    const String stateKey = 'APP/$_measurementId/state';
    const String queueKey = 'APP/$_measurementId/queue';

    String key(String template, FirebaseApp app) =>
        template.replaceFirst('APP', app.name);

    Map<String, Object?> queued(String name, Map<String, Object?> params) =>
        <String, Object?>{
          'n': name,
          'p': <String, Object?>{
            ...params,
            'session_id': 5,
            'engagement_time_msec': 1,
          },
          't': _start.microsecondsSinceEpoch,
          'x': <String, Object?>{},
        };

    fakeTest(
      'an unreadable state fails closed until the user decides again, and is not overwritten',
      (_Env env) {
        // It may have held an opt-out (design rule 7).
        final AnalyticsStore store = AnalyticsStore.memory();
        env.wait(store.write(key(stateKey, env.app), '{not json'));
        env.wait(store.write(key(queueKey, env.app), '[{'));
        final FirebaseAnalytics analytics = env.create(store: store);
        env.wait(analytics.setUserId('u1'));
        env.wait(analytics.logEvent(name: 'a'));
        env.wait(analytics.flush());
        expect(env.sent, isEmpty);
        expect(env.wait(store.read(key(stateKey, env.app))), '{not json');
        expect(env.warnings.any((String w) => w.contains('opt-out')), isTrue);

        env.wait(analytics.setAnalyticsCollectionEnabled(true));
        env.wait(analytics.logEvent(name: 'b'));
        env.wait(analytics.flush());
        expect(env.sent.single.names, <String>['b']);
        expect(env.sent.single.body['client_id'], matches(_clientIdPattern));
        expect(
          env.wait(store.read(key(stateKey, env.app))),
          isNot('{not json'),
        );
      },
    );

    fakeTest('a collection switch or consent of the wrong type fails closed', (
      _Env env,
    ) {
      for (final Map<String, Object?> state in <Map<String, Object?>>[
        <String, Object?>{'v': 1, 'collectionEnabled': 'no'},
        <String, Object?>{'v': 1, 'consent': 'granted'},
        <String, Object?>{
          'v': 1,
          'consent': <String, Object?>{'analyticsStorage': 0},
        },
      ]) {
        final AnalyticsStore store = AnalyticsStore.memory();
        env.wait(store.write(key(stateKey, env.app), jsonEncode(state)));
        final FirebaseAnalytics analytics = env.create(store: store);
        env.wait(analytics.logEvent(name: 'a'));
        env.wait(analytics.close());
        expect(env.sent, isEmpty, reason: '$state');
      }
    });

    fakeTest('wrong types are dropped', (_Env env) {
      final AnalyticsStore store = AnalyticsStore.memory();
      env.wait(
        store.write(
          key(stateKey, env.app),
          jsonEncode(<String, Object?>{
            'v': 1,
            'clientId': 12,
            'userId': 7,
            'userProperties': <String, Object?>{'plan': 3, 'ok': 'yes'},
            'defaultParameters': <String, Object?>{
              'bad': <int>[1],
            },
            'sessionId': 'x',
          }),
        ),
      );
      env.wait(store.write(key(queueKey, env.app), '{"a": 1}'));
      final FirebaseAnalytics analytics = env.create(store: store);
      env.wait(analytics.logEvent(name: 'a'));
      env.wait(analytics.flush());
      final Map<String, Object?> body = env.sent.single.body;
      expect(env.sent.single.names, <String>['a']);
      expect(body['client_id'], matches(_clientIdPattern));
      expect(body.containsKey('user_id'), isFalse);
      expect(body['user_properties'], <String, Object?>{
        'ok': <String, Object?>{'value': 'yes'},
      });
      expect(body.containsKey('consent'), isFalse);
      final Map<String, Object?> params =
          env.sent.single.events.single['params']! as Map<String, Object?>;
      expect(params.containsKey('bad'), isFalse);
      expect(env.warnings, isNotEmpty);
    });

    fakeTest('an invalid client id is replaced', (_Env env) {
      final AnalyticsStore store = AnalyticsStore.memory();
      env.wait(
        store.write(
          key(stateKey, env.app),
          jsonEncode(<String, Object?>{
            'v': 1,
            'clientId': 'abc.def',
            'userId': 'u1',
          }),
        ),
      );
      final FirebaseAnalytics analytics = env.create(store: store);
      final String id = env.wait(analytics.appInstanceId)!;
      expect(id, matches(_clientIdPattern));
      expect(id, isNot('abc.def'));
      expect(env.warnings.any((String w) => w.contains('client id')), isTrue);
      env.wait(analytics.logEvent(name: 'a'));
      env.wait(analytics.flush());
      // The valid fields are kept.
      expect(env.sent.single.body['user_id'], 'u1');
    });

    fakeTest('bad queued events are dropped and the rest are sent', (_Env env) {
      final AnalyticsStore store = AnalyticsStore.memory();
      env.wait(
        store.write(
          key(queueKey, env.app),
          jsonEncode(<Object?>[
            queued('kept', <String, Object?>{'a': 1}),
            queued('first_open', <String, Object?>{}),
            queued('too_long', <String, Object?>{'a': 'x' * 101}),
            queued('reserved_param', <String, Object?>{'firebase_x': 1}),
            'not an event',
          ]),
        ),
      );
      final FirebaseAnalytics analytics = env.create(store: store);
      expect(env.wait(analytics.queuedEventCount), 1);
      expect(
        env.warnings.any((String w) => w.contains('4 stored events')),
        isTrue,
        reason: '${env.warnings}',
      );
      env.wait(analytics.logEvent(name: 'new_one'));
      env.wait(analytics.flush());
      expect(
        env.deliveredEvents.map((Map<String, Object?> e) => e['name']),
        <String>['kept', 'new_one'],
      );
    });
  });

  fakeTest(
    'a store that throws fails closed, then works once the user decides',
    (_Env env) {
      final FirebaseAnalytics analytics = env.create(store: _ThrowingStore());
      env.wait(analytics.logEvent(name: 'ignored'));
      env.fa.elapse(const Duration(seconds: 5));
      expect(env.sent, isEmpty);
      env.wait(analytics.setAnalyticsCollectionEnabled(true));
      env.wait(analytics.setUserId('u1'));
      env.wait(analytics.logEvent(name: 'a'));
      env.fa.elapse(const Duration(seconds: 5));
      expect(env.sent.single.names, <String>['a']);
      expect(env.sent.single.body['user_id'], 'u1');
      expect(env.sent.single.body['client_id'], matches(_clientIdPattern));
      expect(env.warnings.any((String w) => w.contains('read')), isTrue);
      expect(env.warnings.any((String w) => w.contains('saved')), isTrue);
      env.wait(analytics.close());
    },
  );

  fakeTest('resetAnalyticsData starts over and keeps default parameters', (
    _Env env,
  ) {
    env.status = 503;
    final FirebaseAnalytics analytics = env.create();
    env.wait(analytics.setUserId('u1'));
    env.wait(analytics.setUserProperty(name: 'plan', value: 'pro'));
    env.wait(
      analytics.setDefaultEventParameters(<String, Object?>{
        'app_version': '1',
      }),
    );
    env.wait(analytics.logEvent(name: 'before'));
    final String oldId = env.wait(analytics.appInstanceId)!;
    expect(env.wait(analytics.sessionId), isNotNull);

    env.wait(analytics.resetAnalyticsData());
    expect(env.wait(analytics.queuedEventCount), 0);
    expect(env.wait(analytics.sessionId), isNull);
    final String newId = env.wait(analytics.appInstanceId)!;
    expect(newId, isNot(oldId));
    expect(newId, matches(_clientIdPattern));

    env.status = 204;
    env.wait(analytics.logEvent(name: 'after'));
    env.wait(analytics.flush());
    expect(env.delivered.single.names, <String>['after']);
    final Map<String, Object?> body = env.delivered.single.body;
    expect(body['client_id'], newId);
    expect(body.containsKey('user_id'), isFalse);
    expect(body.containsKey('user_properties'), isFalse);
    final Map<String, Object?> params =
        env.delivered.single.events.single['params']! as Map<String, Object?>;
    expect(params['app_version'], '1');
  });

  fakeTest('setDefaultEventParameters', (_Env env) {
    final FirebaseAnalytics analytics = env.create();
    Map<String, Object?> lastParams() {
      env.wait(analytics.flush());
      return env.sent.last.events.single['params']! as Map<String, Object?>;
    }

    env.wait(
      analytics.setDefaultEventParameters(<String, Object?>{'a': 1, 'b': 'x'}),
    );
    env.wait(
      analytics.logEvent(name: 'e1', parameters: <String, Object?>{'b': 'y'}),
    );
    Map<String, Object?> params = lastParams();
    expect(params['a'], 1);
    expect(params['b'], 'y');

    // Merged into the current defaults.
    env.wait(analytics.setDefaultEventParameters(<String, Object?>{'c': true}));
    env.wait(analytics.logEvent(name: 'e2'));
    params = lastParams();
    expect(params['a'], 1);
    expect(params['b'], 'x');
    expect(params['c'], 1);

    // A null value removes one default.
    env.wait(analytics.setDefaultEventParameters(<String, Object?>{'a': null}));
    env.wait(analytics.logEvent(name: 'e3'));
    params = lastParams();
    expect(params.containsKey('a'), isFalse);
    expect(params['b'], 'x');

    // Null clears them all.
    env.wait(analytics.setDefaultEventParameters(null));
    env.wait(analytics.logEvent(name: 'e4'));
    params = lastParams();
    expect(params.keys.toSet(), <String>{'session_id', 'engagement_time_msec'});
  });

  fakeTest('logScreenView sends page_view', (_Env env) {
    final FirebaseAnalytics analytics = env.create();
    env.wait(
      analytics.logScreenView(
        screenName: 'Home Page/é',
        screenClass: 'HomeView',
        parameters: <String, Object?>{'extra': 1},
      ),
    );
    env.wait(analytics.flush());
    final Map<String, Object?> event = env.sent.single.events.single;
    expect(event['name'], 'page_view');
    final Map<String, Object?> params =
        event['params']! as Map<String, Object?>;
    expect(params['page_title'], 'Home Page/é');
    expect(
      params['page_location'],
      'app://$_appId/${Uri.encodeComponent('Home Page/é')}',
    );
    expect(params['page_location'], 'app://$_appId/Home%20Page%2F%C3%A9');
    expect(params['screen_class'], 'HomeView');
    expect(params['extra'], 1);

    final Object error = env.error(analytics.logScreenView(screenName: ''));
    expect(
      error,
      isA<FirebaseAnalyticsException>().having(
        (FirebaseAnalyticsException e) => e.code,
        'code',
        'invalid-parameter',
      ),
    );
  });

  fakeTest('maxQueuedEvents drops the oldest with one warning', (_Env env) {
    env.status = 503;
    final FirebaseAnalytics analytics = env.create(maxQueuedEvents: 25);
    for (int i = 0; i < 30; i++) {
      env.wait(
        analytics.logEvent(name: 'e', parameters: <String, Object?>{'i': i}),
      );
    }
    for (int i = 30; i < 35; i++) {
      env.wait(
        analytics.logEvent(name: 'e', parameters: <String, Object?>{'i': i}),
      );
    }
    expect(env.wait(analytics.queuedEventCount), 25);
    expect(
      env.warnings.where((String w) => w.contains('oldest')),
      hasLength(1),
    );

    env.status = 204;
    env.wait(analytics.flush());
    expect(
      <Object?>[
        for (final Map<String, Object?> e in env.deliveredEvents)
          (e['params']! as Map<String, Object?>)['i'],
      ],
      <int>[for (int i = 10; i < 35; i++) i],
    );
  });

  group('measurementId', () {
    fakeTest('falls back to app.options.measurementId', (_Env env) {
      final FirebaseApp withId = _newApp(measurementId: 'G-FROMAPP1');
      final FirebaseAnalytics analytics = env.create(
        app: withId,
        measurementId: null,
      );
      expect(analytics.measurementId, 'G-FROMAPP1');
      env.wait(analytics.logEvent(name: 'a'));
      env.wait(analytics.flush());
      expect(
        env.sent.single.request.url.queryParameters['measurement_id'],
        'G-FROMAPP1',
      );
      unawaited(withId.delete());
    });

    fakeTest('an invalid one throws ArgumentError', (_Env env) {
      for (final String id in <String>['UA-12345-1', 'G-', 'g-abc123', '']) {
        expect(() => env.create(measurementId: id), throwsArgumentError);
      }
      // None given and none in the options.
      expect(() => env.create(measurementId: null), throwsArgumentError);
      final FirebaseApp bad = _newApp(measurementId: 'not-an-id');
      expect(
        () => env.create(app: bad, measurementId: null),
        throwsArgumentError,
      );
      unawaited(bad.delete());
    });
  });
}
