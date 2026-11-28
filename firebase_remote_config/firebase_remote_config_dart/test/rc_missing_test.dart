@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:firebase_remote_config_dart/src/template.dart'
    show maxRecordBytes;
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/missing_backoff_harness.dart';
import 'support/rc_fetch_harness.dart';
import 'support/rc_realtime_fakes.dart';

const Duration _zero = Duration.zero;
const Duration _second = Duration(seconds: 1);

Duration _s(num seconds) => secondsAfterEpoch(seconds);

Map<String, Object?> _rollout(
  String rolloutId,
  String variantId, [
  List<String>? keys,
]) => <String, Object?>{
  'rolloutId': rolloutId,
  'variantId': variantId,
  'affectedParameterKeys': ?keys,
};

FakeAnswer _template(
  Map<String, String> entries, {
  Object? version,
  String? etag,
  List<Map<String, Object?>>? rollouts,
}) => FakeAnswer.fetch(
  entries: entries,
  templateVersion: version,
  etag: etag,
  extra: <String, Object?>{'rolloutMetadata': ?rollouts},
);

RolloutAssignment _assignment(
  String rolloutId,
  String variantId,
  String key,
  String value,
  int version,
) => RolloutAssignment(
  rolloutId: rolloutId,
  variantId: variantId,
  parameterKey: key,
  parameterValue: value,
  templateVersion: version,
);

/// Collects the events of `onRolloutsStateChanged`.
List<Set<RolloutAssignment>> _rolloutEvents(FirebaseRemoteConfig rc) {
  final List<Set<RolloutAssignment>> events = <Set<RolloutAssignment>>[];
  rc.onRolloutsStateChanged.listen(events.add);
  return events;
}

/// Counts the events of `onActivated`.
final class _ActivatedLog {
  _ActivatedLog(Stream<void> stream) {
    stream.listen((void _) => count++, onDone: () => done = true);
  }

  int count = 0;
  bool done = false;
}

Future<http.StreamedResponse> _refuse503(RealtimeConnection connection) =>
    connection.refuse(503);

void main() {
  group('A38 reset()', () {
    fakeTest(
      'A38 reset clears the fetched, active, meta and throttle records in memory and in '
      'the store; the defaults and the custom signals stay; info reads noFetchYet',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(defaults: <String, Object>{'a': 'default'});
        final FirebaseRemoteConfig rc = env.remoteConfig;
        h.settle(rc.setCustomSignals(<String, Object?>{'tier': 'gold'}));
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'remote'}, version: '5', etag: 'e1'),
        );
        expect(h.settle(rc.fetchAndActivate()), isTrue);
        async.elapse(_second);
        env.backend.enqueue(FakeRoute.fetch, FakeAnswer.status(503));
        expect(
          h.rcError(rc.fetch(minimumFetchInterval: _zero)).code,
          'fetch-status',
        );
        // The state reset must clear: a remote value, a throttle window and the fetch status.
        expect(rc.getString('a'), 'remote');
        expect(rc.info.throttledUntil, isNotNull);
        expect(rc.info.lastSuccessfulFetchTime, isNotNull);
        for (final String name in <String>[
          'fetched',
          'active',
          'meta',
          'throttle',
          'signals',
        ]) {
          expect(h.settle(env.readRecord(name)), isNotNull, reason: name);
        }

        h.settle(rc.reset());

        expect(rc.getString('a'), 'default');
        expect(rc.getValue('a').source, ValueSource.valueDefault);
        expect(rc.defaults['a']?.text, 'default');
        final RemoteConfigInfo info = rc.info;
        expect(info.lastFetchStatus, RemoteConfigFetchStatus.noFetchYet);
        expect(info.lastSuccessfulFetchTime, isNull);
        expect(info.throttledUntil, isNull);
        expect(info.activeTemplateVersion, isNull);
        expect(info.fetchedTemplateVersion, isNull);
        for (final String name in <String>[
          'fetched',
          'active',
          'meta',
          'throttle',
        ]) {
          expect(h.settle(env.readRecord(name)), isNull, reason: name);
        }
        expect(h.settle(env.readRecord('signals')), isNotNull);

        // The throttle is gone (no fetch-throttle) and the cache too (a request is sent); the signals
        // are still sent.
        env.backend.clearRequests();
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'after'}, version: '6'),
        );
        expect(h.settle(rc.fetch()), FetchResult.updated);
        final List<RecordedRequest> fetches = env.backend.requestsTo(
          FakeRoute.fetch,
        );
        expect(fetches, hasLength(1));
        expect(fetches.single.json['custom_signals'], <String, Object?>{
          'tier': 'gold',
        });
      },
    );

    fakeTest('A38 the first fetch after reset sends no If-None-Match', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      final FirebaseRemoteConfig rc = env.remoteConfig;
      env.backend.enqueue(
        FakeRoute.fetch,
        _template(<String, String>{'a': '1'}, version: '1', etag: 'e1'),
      );
      expect(h.settle(rc.fetchAndActivate()), isTrue);
      async.elapse(_second);
      env.backend.enqueue(
        FakeRoute.fetch,
        _template(<String, String>{'a': '2'}, version: '2', etag: 'e2'),
      );
      h.settle(rc.fetch(minimumFetchInterval: _zero));
      // Control: before the reset the stored ETag is sent.
      expect(
        env.backend.requestsTo(FakeRoute.fetch).last.headers['if-none-match'],
        'e1',
      );

      h.settle(rc.reset());
      async.elapse(_second);
      env.backend.enqueue(
        FakeRoute.fetch,
        _template(<String, String>{'a': '3'}, version: '3', etag: 'e3'),
      );
      expect(h.settle(rc.fetch()), FetchResult.updated);

      final RecordedRequest request = env.backend
          .requestsTo(FakeRoute.fetch)
          .last;
      expect(request.headers.containsKey('if-none-match'), isFalse);
    });

    fakeTest(
      'A38 reset during an in-flight fetch waits for it; the late answer does not refill the '
      'cleared records',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        final FirebaseRemoteConfig rc = env.remoteConfig;
        final Gate gate = Gate();
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{
            'a': 'late',
          }, version: '3').after(gate.future),
        );
        final Future<FetchResult> fetch = rc.fetch();
        async.elapse(_zero);
        expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));

        bool resetDone = false;
        final Future<void> reset = rc.reset();
        unawaited(reset.then<void>((void _) => resetDone = true));
        async.elapse(const Duration(seconds: 5));
        expect(
          resetDone,
          isFalse,
          reason: 'the reset waits for the fetch in flight',
        );

        gate.open();
        expect(h.settle(fetch), FetchResult.updated);
        h.settle(reset);
        expect(resetDone, isTrue);

        expect(h.settle(env.readRecord('fetched')), isNull);
        expect(h.settle(env.readRecord('meta')), isNull);
        expect(rc.info.fetchedTemplateVersion, isNull);
        expect(rc.info.lastFetchStatus, RemoteConfigFetchStatus.noFetchYet);
        expect(h.settle(rc.activate()), isFalse);
        expect(rc.getString('a'), '');
      },
    );

    fakeTest(
      'A38 a fetch called during reset waits for the reset, then sends its request',
      (FakeAsync async, Harness h) {
        final ScriptedStore store = ScriptedStore();
        final RcEnv env = h.env(store: store);
        final FirebaseRemoteConfig rc = env.remoteConfig;
        final Gate gate = Gate();
        // The fetch waits for the reset, so the first update of the fetched record is the reset's.
        store.before = (StoreOp op, String key) =>
            op == StoreOp.update && key == env.recordKey('fetched')
            ? gate.future
            : null;

        final Future<void> reset = rc.reset();
        async.elapse(_zero);
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'new'}, version: '2'),
        );
        final Future<FetchResult> fetch = rc.fetch();
        async.elapse(const Duration(seconds: 5));
        expect(
          env.backend.requestsTo(FakeRoute.fetch),
          isEmpty,
          reason: 'the fetch waits while the reset runs',
        );

        gate.open();
        h.settle(reset);
        expect(h.settle(fetch), FetchResult.updated);
        store.before = null;

        expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));
        // The fetch ran after the reset cleared the records, so its record stays.
        expect(h.settle(env.readRecord('fetched')), isNotNull);
        expect(rc.info.fetchedTemplateVersion, 2);
      },
    );

    fakeTest(
      'A38 an activate called during reset waits for it and finds nothing to activate',
      (FakeAsync async, Harness h) {
        final ScriptedStore store = ScriptedStore();
        final RcEnv env = h.env(store: store);
        final FirebaseRemoteConfig rc = env.remoteConfig;
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'remote'}, version: '5'),
        );
        h.settle(rc.fetch());
        final Gate gate = Gate();
        // activate only reads the fetched record, so this update is the reset's.
        store.before = (StoreOp op, String key) =>
            op == StoreOp.update && key == env.recordKey('fetched')
            ? gate.future
            : null;

        final Future<void> reset = rc.reset();
        async.elapse(_zero);
        bool activateDone = false;
        final Future<bool> activate = rc.activate();
        unawaited(activate.then<void>((bool _) => activateDone = true));
        async.elapse(const Duration(seconds: 5));
        expect(activateDone, isFalse);

        gate.open();
        h.settle(reset);
        expect(h.settle(activate), isFalse);
        store.before = null;

        expect(h.settle(env.readRecord('active')), isNull);
        expect(rc.getString('a'), '');
        expect(rc.info.activeTemplateVersion, isNull);
      },
    );

    fakeTest(
      'A38 an activate already running when reset starts returns false and stores nothing',
      (FakeAsync async, Harness h) {
        final ScriptedStore store = ScriptedStore();
        final RcEnv env = h.env(
          store: store,
          defaults: <String, Object>{'a': 'default'},
        );
        final FirebaseRemoteConfig rc = env.remoteConfig;
        final _ActivatedLog activated = _ActivatedLog(rc.onActivated);
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'remote'}, version: '5'),
        );
        h.settle(rc.fetch());
        final Gate gate = Gate();
        // The activate stops just before its update of the active record; the reset's later update
        // of the same record is not held.
        bool held = false;
        store.before = (StoreOp op, String key) {
          if (!held && op == StoreOp.update && key == env.recordKey('active')) {
            held = true;
            return gate.future;
          }
          return null;
        };
        final Future<bool> activate = rc.activate();
        async.elapse(_zero);

        h.settle(rc.reset());
        gate.open();
        expect(h.settle(activate), isFalse);
        store.before = null;
        async.elapse(_zero);

        expect(h.settle(env.readRecord('active')), isNull);
        expect(rc.getString('a'), 'default');
        expect(rc.getValue('a').source, ValueSource.valueDefault);
        expect(rc.info.activeTemplateVersion, isNull);
        expect(activated.count, 0);
      },
    );

    fakeTest(
      'A38 a store failure during reset throws storage-error and leaves memory unchanged; '
      'records cleared before the failure stay cleared',
      (FakeAsync async, Harness h) {
        final ScriptedStore store = ScriptedStore();
        final RcEnv env = h.env(
          store: store,
          defaults: <String, Object>{'a': 'default'},
        );
        final FirebaseRemoteConfig rc = env.remoteConfig;
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': 'remote'}, version: '5'),
        );
        expect(h.settle(rc.fetchAndActivate()), isTrue);
        final DateTime? lastSuccess = rc.info.lastSuccessfulFetchTime;
        store.before = (StoreOp op, String key) {
          if (op == StoreOp.update && key == env.recordKey('active')) {
            throw StateError('fake disk full');
          }
        };

        expect(h.rcError(rc.reset()).code, 'storage-error');

        expect(rc.getString('a'), 'remote');
        expect(rc.getValue('a').source, ValueSource.valueRemote);
        final RemoteConfigInfo info = rc.info;
        expect(info.activeTemplateVersion, 5);
        expect(info.fetchedTemplateVersion, 5);
        expect(info.lastFetchStatus, RemoteConfigFetchStatus.success);
        expect(info.lastSuccessfulFetchTime, lastSuccess);
        expect(
          h.settle(env.readRecord('fetched')),
          isNull,
          reason: 'cleared before the failure',
        );
        expect(h.settle(env.readRecord('active')), isNotNull);

        // The failed reset left nothing waiting: a second one goes through.
        store.before = null;
        h.settle(rc.reset());
        expect(rc.getString('a'), 'default');
        expect(h.settle(env.readRecord('active')), isNull);
      },
    );

    test(
      'A38 the realtime backoff survives reset, in the store and in memory',
      () {
        fakeAsync((FakeAsync async) {
          final String stored = backoffText(
            serverFailures: 1,
            serverUntil: _s(120),
          );
          final BackoffHarness h = BackoffHarness(
            async,
            records: <String, String>{'realtime': stored},
          );

          async.settle(h.remoteConfig.reset());

          expect(h.record('realtime'), jsonDecode(stored));
          h.listen();
          h.elapseTo(_s(119.999));
          expect(h.server.connections, isEmpty);
          h.elapseTo(_s(120));
          expect(h.server.connections, hasLength(1));
          h.dispose();
        });
      },
    );

    fakeTest(
      'A38 reset emits an empty set on onRolloutsStateChanged when rollouts were active, '
      'once; onActivated does not emit',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        final FirebaseRemoteConfig rc = env.remoteConfig;
        final List<Set<RolloutAssignment>> events = _rolloutEvents(rc);
        final _ActivatedLog activated = _ActivatedLog(rc.onActivated);
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(
            <String, String>{'a': '1'},
            version: '2',
            rollouts: <Map<String, Object?>>[
              _rollout('r1', 'v1', <String>['a']),
            ],
          ),
        );
        expect(h.settle(rc.fetchAndActivate()), isTrue);
        async.elapse(_zero);
        expect(events, hasLength(2));
        expect(activated.count, 1);

        h.settle(rc.reset());
        async.elapse(_zero);
        expect(events, hasLength(3));
        expect(events.last, isEmpty);
        expect(activated.count, 1);

        h.settle(rc.reset());
        async.elapse(_zero);
        expect(events, hasLength(3), reason: 'a second reset changes nothing');
      },
    );

    fakeTest(
      'A38 reset with no rollouts active emits nothing on onRolloutsStateChanged',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        final FirebaseRemoteConfig rc = env.remoteConfig;
        final List<Set<RolloutAssignment>> events = _rolloutEvents(rc);
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': '1'}, version: '2'),
        );
        expect(h.settle(rc.fetchAndActivate()), isTrue);
        h.settle(rc.reset());
        async.elapse(_zero);

        expect(events, <Set<RolloutAssignment>>[<RolloutAssignment>{}]);
      },
    );
  });

  group('A39 persisted realtime backoff', () {
    test(
      'A39 a restored server wait delays the first connect, made while the records load; the '
      'connect dropped meanwhile counts no failure',
      () {
        fakeAsync((FakeAsync async) {
          final Gate gate = Gate();
          final String stored = backoffText(
            serverFailures: 1,
            serverUntil: _s(120),
          );
          final BackoffHarness h = BackoffHarness(
            async,
            records: <String, String>{'realtime': stored},
            before: (StoreOp op, String key) =>
                op == StoreOp.read && key.endsWith('/realtime')
                ? gate.future
                : null,
          );
          h.server.realtimeAnswer = _refuse503;
          h.listen();
          expect(h.remoteConfig.isInitialized, isFalse);
          expect(h.server.connections, isEmpty);

          gate.open();
          h.elapseTo(_s(119.999));
          expect(h.remoteConfig.isInitialized, isTrue);
          expect(h.server.connections, isEmpty);
          expect(
            h.record('realtime'),
            jsonDecode(stored),
            reason: 'no failure was counted',
          );

          // The connect at the end of the wait is refused: the second server failure waits 4 min.
          h.elapseTo(_s(120));
          expect(h.server.connections, hasLength(1));
          expect(
            h.record('realtime'),
            backoffJson(serverFailures: 2, serverUntil: _s(120 + 240)),
          );
          h.elapseTo(_s(359.999));
          expect(h.server.connections, hasLength(1));
          h.elapseTo(_s(360));
          expect(h.server.connections, hasLength(2));
          h.dispose();
        });
      },
    );

    for (final String field in <String>[
      'serverUntil',
      'transportUntil',
      'retryUntil',
    ]) {
      test(
        'A39 a restored $field 90 s ahead delays the first connect to 90 s',
        () {
          fakeAsync((FakeAsync async) {
            final BackoffHarness h = BackoffHarness(
              async,
              records: <String, String>{
                'realtime': backoffText(
                  serverUntil: field == 'serverUntil' ? _s(90) : null,
                  transportUntil: field == 'transportUntil' ? _s(90) : null,
                  retryUntil: field == 'retryUntil' ? _s(90) : null,
                ),
              },
            );
            h.listen();
            h.elapseTo(_s(89.999));
            expect(h.server.connections, isEmpty);
            h.elapseTo(_s(90));
            expect(h.server.connections, hasLength(1));
            h.dispose();
          });
        },
      );
    }

    final int future = epochMillis(_s(120));
    final Map<String, String> corrupt = <String, String>{
      'not JSON': 'not json',
      'version 2': jsonEncode(<String, Object?>{
        'v': 2,
        'serverFailures': 1,
        'transportFailures': 0,
        'serverUntil': future,
      }),
      'serverFailures 1001': jsonEncode(<String, Object?>{
        'v': 1,
        'serverFailures': 1001,
        'transportFailures': 0,
        'serverUntil': future,
      }),
      'serverFailures -1': jsonEncode(<String, Object?>{
        'v': 1,
        'serverFailures': -1,
        'transportFailures': 0,
        'serverUntil': future,
      }),
      'transportFailures missing': jsonEncode(<String, Object?>{
        'v': 1,
        'serverFailures': 1,
        'serverUntil': future,
      }),
      'serverUntil a word': jsonEncode(<String, Object?>{
        'v': 1,
        'serverFailures': 1,
        'transportFailures': 0,
        'serverUntil': 'soon',
      }),
      'serverUntil a fraction': jsonEncode(<String, Object?>{
        'v': 1,
        'serverFailures': 1,
        'transportFailures': 0,
        'serverUntil': future + 0.5,
      }),
    };
    for (final MapEntry<String, String> entry in corrupt.entries) {
      test(
        'A39 a corrupt realtime record (${entry.key}) is ignored and logged once: the first '
        'connect is not delayed',
        () {
          fakeAsync((FakeAsync async) {
            final List<String> messages = <String>[];
            final BackoffHarness h = BackoffHarness(
              async,
              records: <String, String>{'realtime': entry.value},
              logger: (RemoteConfigLogLevel level, String message) =>
                  messages.add(message),
            );
            expect(h.remoteConfig.isInitialized, isTrue);
            h.listen();
            h.elapseTo(_s(1));
            expect(h.server.connections, hasLength(1));
            expect(
              messages.where(
                (String message) => message.contains('realtime record'),
              ),
              hasLength(1),
            );
            h.dispose();
          });
        },
      );
    }

    test('A39 a stored end later than now + 24 h is capped at now + 24 h', () {
      fakeAsync((FakeAsync async) {
        final BackoffHarness h = BackoffHarness(
          async,
          records: <String, String>{
            'realtime': backoffText(
              serverFailures: 1,
              serverUntil: const Duration(days: 30),
            ),
          },
        );
        h.listen();
        h.elapseTo(const Duration(hours: 24) - const Duration(milliseconds: 1));
        expect(h.server.connections, isEmpty);
        h.elapseTo(const Duration(hours: 24));
        expect(h.server.connections, hasLength(1));
        h.dispose();
      });
    });

    test(
      'A39 a connection open 60 s clears the counts and removes the record when it is empty',
      () {
        fakeAsync((FakeAsync async) {
          final String stored = backoffText(
            serverFailures: 3,
            transportFailures: 2,
            serverUntil: -_s(10),
            transportUntil: -_s(5),
          );
          final BackoffHarness h = BackoffHarness(
            async,
            records: <String, String>{'realtime': stored},
          );
          h.listen();
          expect(h.server.connections, hasLength(1));
          h.elapseTo(_s(59.999));
          expect(h.record('realtime'), jsonDecode(stored));

          h.elapseTo(_s(60));
          expect(h.record('realtime'), isNull);

          // The counts start again from zero: the next server failure is the first (a 2-minute wait).
          h.server.realtimeAnswer = _refuse503;
          h.elapseTo(_s(61));
          h.server.last.end();
          h.elapseTo(_s(62));
          expect(h.server.connections, hasLength(2));
          expect(
            h.record('realtime'),
            backoffJson(serverFailures: 1, serverUntil: _s(62 + 120)),
          );
          h.dispose();
        });
      },
    );

    test(
      'A39 / A20 the retryIntervalSeconds wait survives a successful connection',
      () {
        fakeAsync((FakeAsync async) {
          final BackoffHarness h = BackoffHarness(async);
          h.listen();
          expect(h.server.connections, hasLength(1));
          h.server.last.send('{"retryIntervalSeconds": 600}');
          h.elapseTo(_s(1));
          expect(h.record('realtime'), backoffJson(retryUntil: _s(600)));

          h.elapseTo(_s(61));
          expect(h.record('realtime'), backoffJson(retryUntil: _s(600)));
          h.server.last.end();
          h.elapseTo(_s(599.999));
          expect(h.server.connections, hasLength(1));
          h.elapseTo(_s(600));
          expect(h.server.connections, hasLength(2));
          h.dispose();
        });
      },
    );

    test(
      'A39 a new instance on the same store restores the retryIntervalSeconds wait',
      () {
        fakeAsync((FakeAsync async) {
          final BackoffHarness h = BackoffHarness(async);
          h.listen();
          h.server.last.send('{"retryIntervalSeconds": 600}');
          h.elapseTo(_s(100));

          h.restart();
          h.listen();
          h.elapseTo(_s(599.999));
          expect(h.server.connections, hasLength(1));
          h.elapseTo(_s(600));
          expect(h.server.connections, hasLength(2));
          h.dispose();
        });
      },
    );
  });

  group('A40 onRolloutsStateChanged', () {
    fakeTest(
      'A40 a listener added before the load gets exactly one set, as does one added after',
      (FakeAsync async, Harness h) {
        final ScriptedStore store = ScriptedStore();
        final RcEnv env = h.env(
          store: store,
          defaults: <String, Object>{'a': 'default-a'},
        );
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(
            <String, String>{'a': 'remote-a'},
            version: '4',
            rollouts: <Map<String, Object?>>[
              _rollout('r1', 'v1', <String>['a']),
            ],
          ),
        );
        expect(h.settle(env.remoteConfig.fetchAndActivate()), isTrue);
        final Set<RolloutAssignment> expected = <RolloutAssignment>{
          _assignment('r1', 'v1', 'a', 'remote-a', 4),
        };

        final Gate gate = Gate();
        store.before = (StoreOp op, String key) =>
            op == StoreOp.read && key.startsWith('remote_config/')
            ? gate.future
            : null;
        final FirebaseRemoteConfig second = env.newRemoteConfig(
          defaults: <String, Object>{'a': 'default-a'},
        );
        final List<Set<RolloutAssignment>> early = _rolloutEvents(second);
        async.elapse(_second);
        expect(second.isInitialized, isFalse);
        expect(early, isEmpty);

        gate.open();
        async.elapse(_second);
        expect(second.isInitialized, isTrue);
        expect(early, <Set<RolloutAssignment>>[expected]);

        final List<Set<RolloutAssignment>> afterLoad = _rolloutEvents(second);
        async.elapse(const Duration(minutes: 1));
        expect(early, <Set<RolloutAssignment>>[expected]);
        expect(afterLoad, <Set<RolloutAssignment>>[expected]);
        store.before = null;
      },
    );

    fakeTest('A40 nothing active: a new listener gets an empty set', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      final List<Set<RolloutAssignment>> events = _rolloutEvents(
        env.remoteConfig,
      );
      async.elapse(_second);

      expect(events, <Set<RolloutAssignment>>[<RolloutAssignment>{}]);
    });

    fakeTest('A40 a failed load gives a new listener nothing', (
      FakeAsync async,
      Harness h,
    ) {
      final ScriptedStore store = ScriptedStore();
      final RcEnv env = h.env(store: store);
      store.before = (StoreOp op, String key) {
        if (op == StoreOp.read && key.startsWith('remote_config/')) {
          throw StateError('fake unreadable store');
        }
      };
      final FirebaseRemoteConfig second = env.newRemoteConfig();
      final List<Set<RolloutAssignment>> events = _rolloutEvents(second);
      async.elapse(_second);

      expect(h.rcError(second.ensureInitialized()).code, 'storage-error');
      expect(events, isEmpty);
      store.before = null;
    });

    fakeTest(
      'A40 assignment fields: rollout id, variant id, the first affected key or \'\', its '
      'value from active, else default, else \'\', and the template version',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(
          defaults: <String, Object>{'a': 'default-a', 'd': 42},
        );
        final FirebaseRemoteConfig rc = env.remoteConfig;
        final List<Set<RolloutAssignment>> events = _rolloutEvents(rc);
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(
            <String, String>{'a': 'remote-a', 'b': 'remote-b'},
            version: '7',
            rollouts: <Map<String, Object?>>[
              _rollout('r1', 'v1', <String>['a', 'b']),
              _rollout('r2', 'v2', <String>['d']),
              _rollout('r3', 'v3', <String>['z']),
              _rollout('r4', 'v4'),
              _rollout('r5', 'v5', <String>[]),
            ],
          ),
        );
        expect(h.settle(rc.fetchAndActivate()), isTrue);
        async.elapse(_zero);

        expect(events, hasLength(2));
        expect(events.last, <RolloutAssignment>{
          _assignment('r1', 'v1', 'a', 'remote-a', 7),
          _assignment('r2', 'v2', 'd', '42', 7),
          _assignment('r3', 'v3', 'z', '', 7),
          _assignment('r4', 'v4', '', '', 7),
          _assignment('r5', 'v5', '', '', 7),
        });
      },
    );

    fakeTest(
      'A40 an active template without a version gives template version 0',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        final FirebaseRemoteConfig rc = env.remoteConfig;
        final List<Set<RolloutAssignment>> events = _rolloutEvents(rc);
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(
            <String, String>{'a': '1'},
            rollouts: <Map<String, Object?>>[
              _rollout('r1', 'v1', <String>['a']),
            ],
          ),
        );
        expect(h.settle(rc.fetchAndActivate()), isTrue);
        async.elapse(_zero);

        expect(events.last, <RolloutAssignment>{
          _assignment('r1', 'v1', 'a', '1', 0),
        });
      },
    );

    fakeTest(
      'A40 an activate that leaves the rollouts unchanged emits nothing; each change emits '
      'once',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        final FirebaseRemoteConfig rc = env.remoteConfig;
        final List<Set<RolloutAssignment>> events = _rolloutEvents(rc);
        final _ActivatedLog activated = _ActivatedLog(rc.onActivated);
        void fetchAndActivate(Map<String, String> entries, String variant) {
          async.elapse(_second);
          env.backend.enqueue(
            FakeRoute.fetch,
            _template(
              entries,
              rollouts: <Map<String, Object?>>[
                _rollout('r1', variant, <String>['a']),
              ],
            ),
          );
          h.settle(rc.fetch(minimumFetchInterval: _zero));
          expect(h.settle(rc.activate()), isTrue);
          async.elapse(_zero);
        }

        async.elapse(_zero);
        expect(events, hasLength(1));

        fetchAndActivate(<String, String>{'a': '1', 'x': '1'}, 'v1');
        expect(events, hasLength(2));

        // A different template, the same assignments.
        fetchAndActivate(<String, String>{'a': '1', 'x': '2'}, 'v1');
        expect(activated.count, 2);
        expect(events, hasLength(2));

        // The affected value changes.
        fetchAndActivate(<String, String>{'a': '2', 'x': '2'}, 'v1');
        expect(events, hasLength(3));
        expect(events.last, <RolloutAssignment>{
          _assignment('r1', 'v1', 'a', '2', 0),
        });

        // The variant changes.
        fetchAndActivate(<String, String>{'a': '2', 'x': '2'}, 'v2');
        expect(events, hasLength(4));
        expect(events.last, <RolloutAssignment>{
          _assignment('r1', 'v2', 'a', '2', 0),
        });
        expect(activated.count, 4);
      },
    );
  });

  group('A41 small read and stream additions', () {
    fakeTest(
      'A41 onActivated emits once per activate() that returns true, nothing on false, and '
      'nothing after close()',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        final FirebaseRemoteConfig rc = env.remoteConfig;
        final _ActivatedLog first = _ActivatedLog(rc.onActivated);
        final _ActivatedLog second = _ActivatedLog(rc.onActivated);

        expect(h.settle(rc.activate()), isFalse);
        async.elapse(_zero);
        expect(first.count, 0);

        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': '1'}, version: '1'),
        );
        h.settle(rc.fetch());
        expect(h.settle(rc.activate()), isTrue);
        async.elapse(_zero);
        expect(first.count, 1);

        expect(h.settle(rc.activate()), isFalse);
        async.elapse(_zero);
        expect(first.count, 1);

        async.elapse(_second);
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{'a': '2'}, version: '2'),
        );
        h.settle(rc.fetch(minimumFetchInterval: _zero));
        expect(h.settle(rc.activate()), isTrue);
        async.elapse(_zero);
        expect(first.count, 2);
        expect(second.count, 2);

        h.settle(rc.close());
        async.elapse(_zero);
        expect(first.done, isTrue);
        expect(second.done, isTrue);
        expect(h.rcError(rc.activate()).code, 'remote-config-closed');
        async.elapse(_zero);
        expect(first.count, 2);
      },
    );

    test('A41 asBytes is the UTF-8 encoding of the text', () {
      expect(
        const RemoteConfigValue('é€😀', ValueSource.valueRemote).asBytes(),
        <int>[0xC3, 0xA9, 0xE2, 0x82, 0xAC, 0xF0, 0x9F, 0x98, 0x80],
      );
      expect(
        const RemoteConfigValue('plain', ValueSource.valueDefault).asBytes(),
        utf8.encode('plain'),
      );
      expect(
        const RemoteConfigValue('', ValueSource.valueStatic).asBytes(),
        isEmpty,
      );
    });

    fakeTest('A41 asBytes of a fetched value with non-ASCII text', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      env.backend.enqueue(
        FakeRoute.fetch,
        _template(<String, String>{'k': 'ñ'}, version: '1'),
      );
      expect(h.settle(env.remoteConfig.fetchAndActivate()), isTrue);

      expect(env.remoteConfig.getValue('k').asBytes(), <int>[0xC3, 0xB1]);
      expect(env.remoteConfig.getValue('missing').asBytes(), isEmpty);
    });

    final Map<String, (String, Object?)> validJson =
        <String, (String, Object?)>{
          'an object': (
            '{"a":[1,2,{"b":null}],"c":"é"}',
            <String, Object?>{
              'a': <Object?>[
                1,
                2,
                <String, Object?>{'b': null},
              ],
              'c': 'é',
            },
          ),
          'an array': ('[1,"two",true]', <Object?>[1, 'two', true]),
          'a string': ('"text"', 'text'),
          'a number': ('3.5', 3.5),
          'a boolean': ('false', false),
        };
    for (final MapEntry<String, (String, Object?)> entry in validJson.entries) {
      test('A41 asJson of ${entry.key} returns the decoded value', () {
        final (String text, Object? expected) = entry.value;
        expect(
          RemoteConfigValue(text, ValueSource.valueRemote).asJson(),
          expected,
        );
        expect(
          RemoteConfigValue(text, ValueSource.valueDefault).asJson(),
          expected,
        );
      });
    }

    test(
      'A41 asJson of arrays nested 32 deep returns the value (the bound)',
      () {
        final String text = '${'[' * 32}${']' * 32}';
        expect(
          RemoteConfigValue(text, ValueSource.valueRemote).asJson(),
          isA<List<Object?>>(),
        );
      },
    );

    test('A41 asJson of text exactly at the size bound returns the value', () {
      final String text = '"${'a' * (maxRecordBytes - 2)}"';
      final Object? json = RemoteConfigValue(
        text,
        ValueSource.valueRemote,
      ).asJson();
      expect(json, isA<String>());
      expect((json! as String).length, maxRecordBytes - 2);
    });

    final Map<String, String> nullJson = <String, String>{
      'arrays nested 33 deep': '${'[' * 33}${']' * 33}',
      'objects nested 33 deep': '${'{"a":' * 33}1${'}' * 33}',
      'the text "null"': 'null',
      '"[1"': '[1',
      'empty text': '',
      'text that is not JSON': 'not json',
      'text one byte over the size bound': '"${'a' * (maxRecordBytes - 1)}"',
      'text over the size bound in UTF-8 only':
          '"${'é' * (maxRecordBytes ~/ 2)}"',
    };
    for (final MapEntry<String, String> entry in nullJson.entries) {
      test('A41 asJson of ${entry.key} returns null without throwing', () {
        expect(
          RemoteConfigValue(entry.value, ValueSource.valueRemote).asJson(),
          isNull,
        );
      });
    }

    test(
      'A41 asJson of a static value returns null, even for valid JSON text',
      () {
        expect(
          const RemoteConfigValue('{"a":1}', ValueSource.valueStatic).asJson(),
          isNull,
        );
        expect(
          const RemoteConfigValue('', ValueSource.valueStatic).asJson(),
          isNull,
        );
      },
    );

    fakeTest(
      'A41 getKeysByPrefix: active and default keys, deduplicated, sorted by UTF-16 code '
      'units; an empty prefix gives every key; the list is unmodifiable',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(
          defaults: <String, Object>{
            'app.a': 'd',
            'app.c': 'd',
            'app.Z': 'd',
            'app.～': 'd',
            'app.😀': 'd',
            'b': 'd',
          },
        );
        final FirebaseRemoteConfig rc = env.remoteConfig;
        // Before an activate: the defaults only. 'Z' (0x5A) sorts before 'a' (0x61).
        expect(rc.getKeysByPrefix('app.'), <String>[
          'app.Z',
          'app.a',
          'app.c',
          'app.😀',
          'app.～',
        ]);

        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{
            'app.b': 'r',
            'app.a': 'r',
            'app.é': 'r',
            'x': 'r',
          }, version: '1'),
        );
        expect(h.settle(rc.fetchAndActivate()), isTrue);

        // U+1F600 is the surrogate pair D83D DE00, so it sorts before U+FF5E by code unit (and after
        // it by code point).
        expect(rc.getKeysByPrefix('app.'), <String>[
          'app.Z',
          'app.a',
          'app.b',
          'app.c',
          'app.é',
          'app.😀',
          'app.～',
        ]);
        expect(rc.getKeysByPrefix(''), <String>[
          'app.Z',
          'app.a',
          'app.b',
          'app.c',
          'app.é',
          'app.😀',
          'app.～',
          'b',
          'x',
        ]);
        expect(rc.getKeysByPrefix('app.a'), <String>['app.a']);
        expect(rc.getKeysByPrefix('q'), isEmpty);

        final List<String> keys = rc.getKeysByPrefix('app.');
        expect(() => keys.add('app.q'), throwsUnsupportedError);
        expect(() => keys[0] = 'app.q', throwsUnsupportedError);
        expect(() => keys.sort(), throwsUnsupportedError);
      },
    );

    fakeTest(
      'A41 getValueFrom returns the value of the source asked for, and the static value when '
      'that source lacks the key',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(
          defaults: <String, Object>{'a': 'default-a', 'b': 'default-b'},
        );
        final FirebaseRemoteConfig rc = env.remoteConfig;
        env.backend.enqueue(
          FakeRoute.fetch,
          _template(<String, String>{
            'a': 'remote-a',
            'c': 'remote-c',
          }, version: '1'),
        );
        expect(h.settle(rc.fetchAndActivate()), isTrue);

        void check(
          String key,
          ValueSource source,
          String text,
          ValueSource expected,
        ) {
          final RemoteConfigValue value = rc.getValueFrom(key, source);
          expect(value.text, text, reason: '$key from ${source.name}');
          expect(value.source, expected, reason: '$key from ${source.name}');
        }

        check(
          'a',
          ValueSource.valueRemote,
          'remote-a',
          ValueSource.valueRemote,
        );
        check(
          'a',
          ValueSource.valueDefault,
          'default-a',
          ValueSource.valueDefault,
        );
        check('a', ValueSource.valueStatic, '', ValueSource.valueStatic);
        check('b', ValueSource.valueRemote, '', ValueSource.valueStatic);
        check(
          'b',
          ValueSource.valueDefault,
          'default-b',
          ValueSource.valueDefault,
        );
        check(
          'c',
          ValueSource.valueRemote,
          'remote-c',
          ValueSource.valueRemote,
        );
        check('c', ValueSource.valueDefault, '', ValueSource.valueStatic);
        for (final ValueSource source in ValueSource.values) {
          check('missing', source, '', ValueSource.valueStatic);
        }
      },
    );
  });
}
