@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:firebase_remote_config_dart/src/platform.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/rc_fetch_harness.dart';

const Duration _zero = Duration.zero;

/// The waits of the n-th throttling failure, entry `min(n, 8)` (5.5).
const List<int> _throttleMinutes = <int>[2, 4, 8, 16, 32, 64, 128, 256];

void main() {
  group('states', () {
    fakeTest(
      '5.5 UPDATE stores the fetched record; reads change only after activate',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(defaults: <String, Object>{'a': 'default'});
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(
            entries: <String, String>{'a': 'remote'},
            templateVersion: '4',
          ),
        );

        expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);

        expect(env.remoteConfig.getString('a'), 'default');
        final RemoteConfigInfo info = env.remoteConfig.info;
        expect(info.fetchedTemplateVersion, 4);
        expect(info.activeTemplateVersion, isNull);
        expect(info.lastFetchStatus, RemoteConfigFetchStatus.success);
        expect(info.lastSuccessfulFetchTime, h.now());
        final Map<String, Object?> fetched = h.settle(
          env.readRecord('fetched'),
        )!;
        expect(fetched['entries'], <String, Object?>{'a': 'remote'});
        expect(fetched['templateVersion'], 4);
        expect(h.settle(env.readRecord('active')), isNull);
      },
    );

    fakeTest('5.5 a body without state is stored as UPDATE', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(
          state: null,
          entries: <String, String>{'a': '1'},
          templateVersion: 2,
        ),
      );

      expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);
      expect(env.remoteConfig.info.fetchedTemplateVersion, 2);
      expect(h.settle(env.readRecord('fetched'))!['entries'], <String, Object?>{
        'a': '1',
      });
    });

    for (final String state in <String>['NO_TEMPLATE', 'EMPTY_CONFIG']) {
      fakeTest(
        '5.5 $state stores a fetched record with no entries; result updated',
        (FakeAsync async, Harness h) {
          final RcEnv env = h.env();
          env.backend.enqueue(
            FakeRoute.fetch,
            FakeAnswer.fetch(
              state: state,
              entries: <String, String>{'ignored': 'x'},
            ),
          );

          expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);
          final Map<String, Object?> fetched = h.settle(
            env.readRecord('fetched'),
          )!;
          expect(fetched['entries'], isEmpty);
          expect(
            env.remoteConfig.info.lastFetchStatus,
            RemoteConfigFetchStatus.success,
          );
        },
      );
    }

    fakeTest(
      '5.5 NO_CHANGE refreshes lastSuccessfulFetchTime and keeps the fetched record',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(
            entries: <String, String>{'a': '1'},
            templateVersion: '1',
          ),
        );
        h.settle(env.remoteConfig.fetch());
        final Map<String, Object?> before = h.settle(
          env.readRecord('fetched'),
        )!;

        async.elapse(const Duration(hours: 1));
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(state: 'NO_CHANGE', templateVersion: '1'),
        );
        expect(
          h.settle(env.remoteConfig.fetch(minimumFetchInterval: _zero)),
          FetchResult.unchanged,
        );

        expect(env.remoteConfig.info.lastSuccessfulFetchTime, h.now());
        expect(
          env.remoteConfig.info.lastFetchStatus,
          RemoteConfigFetchStatus.success,
        );
        expect(h.settle(env.readRecord('fetched')), before);
      },
    );

    fakeTest('5.5 HTTP 304 is handled as NO_CHANGE', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.bytes(const <int>[], status: 304),
      );

      expect(h.settle(env.remoteConfig.fetch()), FetchResult.unchanged);
      expect(
        env.remoteConfig.info.lastFetchStatus,
        RemoteConfigFetchStatus.success,
      );
      expect(env.remoteConfig.info.lastSuccessfulFetchTime, h.now());
    });

    fakeTest(
      '5.5 INSTANCE_STATE_UNSPECIFIED keeps the config and records success',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(
            entries: <String, String>{'a': 'remote'},
            templateVersion: '3',
          ),
        );
        expect(h.settle(env.remoteConfig.fetchAndActivate()), isTrue);

        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(state: 'INSTANCE_STATE_UNSPECIFIED'),
        );
        expect(
          h.settle(env.remoteConfig.fetch(minimumFetchInterval: _zero)),
          FetchResult.unchanged,
        );

        expect(env.remoteConfig.getString('a'), 'remote');
        expect(env.remoteConfig.info.fetchedTemplateVersion, 3);
        expect(
          env.remoteConfig.info.lastFetchStatus,
          RemoteConfigFetchStatus.success,
        );
      },
    );
  });

  group('cache', () {
    fakeTest(
      '5.5 cached result names the cache (§6 row 1): no request, status success',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(entries: <String, String>{'a': '1'}),
        );
        h.settle(env.remoteConfig.fetch());
        final DateTime fetchedAt = h.now();
        env.backend.clearRequests();

        async.elapse(const Duration(hours: 1));
        expect(h.settle(env.remoteConfig.fetch()), FetchResult.cached);

        expect(env.backend.requests, isEmpty);
        expect(
          env.remoteConfig.info.lastFetchStatus,
          RemoteConfigFetchStatus.success,
        );
        expect(env.remoteConfig.info.lastSuccessfulFetchTime, fetchedAt);
      },
    );

    fakeTest(
      '5.5 strict boundary: cached below minimumFetchInterval, sent at it',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(entries: <String, String>{'a': '1'}),
        );
        h.settle(env.remoteConfig.fetch());

        async.elapse(
          const Duration(hours: 12) - const Duration(milliseconds: 1),
        );
        expect(h.settle(env.remoteConfig.fetch()), FetchResult.cached);
        expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));

        async.elapse(const Duration(milliseconds: 1));
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(state: 'NO_CHANGE'),
        );
        expect(h.settle(env.remoteConfig.fetch()), FetchResult.unchanged);
        expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(2));
      },
    );

    fakeTest('5.5 a call\'s minimumFetchInterval replaces the constructor\'s', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(entries: <String, String>{'a': '1'}),
      );
      h.settle(env.remoteConfig.fetch());

      async.elapse(const Duration(hours: 1));
      expect(
        h.settle(
          env.remoteConfig.fetch(
            minimumFetchInterval: const Duration(hours: 2),
          ),
        ),
        FetchResult.cached,
      );
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(state: 'NO_CHANGE'),
      );
      expect(
        h.settle(
          env.remoteConfig.fetch(
            minimumFetchInterval: const Duration(hours: 1),
          ),
        ),
        FetchResult.unchanged,
      );
    });

    fakeTest('5.5 minimumFetchInterval zero always sends', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env(minimumFetchInterval: _zero);
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(entries: <String, String>{'a': '1'}),
        times: 3,
      );

      for (int i = 0; i < 3; i++) {
        expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);
      }
      expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(3));
    });

    fakeTest('5.5 no cache without a fetched or active record', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(state: 'NO_CHANGE'),
        times: 2,
      );

      expect(h.settle(env.remoteConfig.fetch()), FetchResult.unchanged);
      expect(h.settle(env.remoteConfig.fetch()), FetchResult.unchanged);
      expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(2));
    });

    fakeTest('5.5 a failed fetch does not move lastSuccessfulFetchTime', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(entries: <String, String>{'a': '1'}),
      );
      h.settle(env.remoteConfig.fetch());
      final DateTime fetchedAt = h.now();

      async.elapse(const Duration(minutes: 5));
      env.backend.enqueue(FakeRoute.fetch, FakeAnswer.status(500));
      expect(
        h.rcError(env.remoteConfig.fetch(minimumFetchInterval: _zero)).code,
        'fetch-status',
      );

      expect(
        env.remoteConfig.info.lastFetchStatus,
        RemoteConfigFetchStatus.failure,
      );
      expect(env.remoteConfig.info.lastSuccessfulFetchTime, fetchedAt);
    });
  });

  group('stale flag (§6 row 5)', () {
    fakeTest(
      '5.5 signals make the cache stale; the stale fetch sends no If-None-Match',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(entries: <String, String>{'a': '1'}, etag: 'etag-1'),
        );
        h.settle(env.remoteConfig.fetch());

        h.settle(
          env.remoteConfig.setCustomSignals(<String, Object?>{'tier': 'gold'}),
        );
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(entries: <String, String>{'a': '2'}, etag: 'etag-2'),
        );
        expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);

        final RecordedRequest stale = env.backend
            .requestsTo(FakeRoute.fetch)
            .last;
        expect(stale.headers.containsKey('if-none-match'), isFalse);
        expect(stale.json['custom_signals'], <String, Object?>{'tier': 'gold'});

        // The successful stale fetch cleared the flag: the next call is answered by the cache.
        expect(h.settle(env.remoteConfig.fetch()), FetchResult.cached);
        expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(2));
      },
    );

    fakeTest('5.5 setting the same signals again leaves the cache valid', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      h.settle(
        env.remoteConfig.setCustomSignals(<String, Object?>{'tier': 'gold'}),
      );
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(entries: <String, String>{'a': '1'}),
      );
      h.settle(env.remoteConfig.fetch());

      h.settle(
        env.remoteConfig.setCustomSignals(<String, Object?>{'tier': 'gold'}),
      );
      expect(h.settle(env.remoteConfig.fetch()), FetchResult.cached);
    });

    fakeTest('5.5 an installation id change makes the cache stale', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(entries: <String, String>{'a': '1'}, etag: 'etag-1'),
      );
      h.settle(env.remoteConfig.fetch());
      final String oldFid =
          env.backend
                  .requestsTo(FakeRoute.fetch)
                  .single
                  .json['app_instance_id']!
              as String;

      h.settle(env.installations.delete());
      final String newFid = h.settle(env.installations.getId());
      h.settle(Future<void>.value());
      expect(newFid, isNot(oldFid));

      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(entries: <String, String>{'a': '2'}),
      );
      expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);

      final RecordedRequest stale = env.backend
          .requestsTo(FakeRoute.fetch)
          .last;
      expect(stale.json['app_instance_id'], newFid);
      expect(stale.headers.containsKey('if-none-match'), isFalse);
    });

    fakeTest(
      '5.5 a FID created inside the fetch call gets no If-None-Match (stale read at build time)',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(entries: <String, String>{'a': '1'}, etag: 'etag-1'),
        );
        h.settle(env.remoteConfig.fetch());

        // The next fetch's getIdAndToken creates and registers a new FID (onIdChange emits).
        h.settle(env.installations.delete());
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(entries: <String, String>{'a': '2'}),
        );
        h.settle(env.remoteConfig.fetch());

        final RecordedRequest request = env.backend
            .requestsTo(FakeRoute.fetch)
            .last;
        // The ETag goes only with the FID whose successful fetch stored it.
        expect(request.headers.containsKey('if-none-match'), isFalse);
      },
    );

    fakeTest(
      '5.9.5 the first FID, created inside the first fetch, does not make the cache stale',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(register: false);
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(entries: <String, String>{'a': '1'}, etag: 'etag-1'),
        );
        expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);
        expect(
          env.backend.requestsTo(FakeRoute.installationsCreate),
          hasLength(1),
        );
        final String fid =
            env.backend
                    .requestsTo(FakeRoute.fetch)
                    .single
                    .json['app_instance_id']!
                as String;

        // No successful fetch was made with another FID: the cache answers.
        expect(h.settle(env.remoteConfig.fetch()), FetchResult.cached);
        expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));

        // The stored FID is the one of that fetch, so a forced fetch sends its ETag.
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(state: 'NO_CHANGE'),
        );
        expect(
          h.settle(env.remoteConfig.fetch(minimumFetchInterval: _zero)),
          FetchResult.unchanged,
        );
        final RecordedRequest forced = env.backend
            .requestsTo(FakeRoute.fetch)
            .last;
        expect(forced.json['app_instance_id'], fid);
        expect(forced.headers['if-none-match'], 'etag-1');
      },
    );

    fakeTest('5.5 an old fetch does not clear a newer generation', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      final Gate gate = Gate();
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(
          entries: <String, String>{'a': '1'},
          etag: 'etag-1',
        ).after(gate.future),
      );
      final Future<FetchResult> first = env.remoteConfig.fetch();
      async.flushMicrotasks();
      expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));

      // The generation changes while the first request is in flight.
      h.settle(
        env.remoteConfig.setCustomSignals(<String, Object?>{'tier': 'gold'}),
      );
      gate.open();
      expect(h.settle(first), FetchResult.updated);

      // Still stale: the next call sends, without the ETag of the old request.
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(state: 'NO_CHANGE'),
      );
      expect(h.settle(env.remoteConfig.fetch()), FetchResult.unchanged);
      final RecordedRequest second = env.backend
          .requestsTo(FakeRoute.fetch)
          .last;
      expect(second.headers.containsKey('if-none-match'), isFalse);
      expect(second.json['custom_signals'], <String, Object?>{'tier': 'gold'});

      expect(h.settle(env.remoteConfig.fetch()), FetchResult.cached);
    });
  });

  group('concurrency', () {
    fakeTest(
      '5.5 concurrent fetches share one request, whatever interval they ask for',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        final Gate gate = Gate();
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(
            entries: <String, String>{'a': '1'},
          ).after(gate.future),
        );

        final Future<FetchResult> first = env.remoteConfig.fetch();
        final Future<FetchResult> second = env.remoteConfig.fetch(
          minimumFetchInterval: _zero,
        );
        final Future<bool> third = env.remoteConfig.fetchAndActivate(
          minimumFetchInterval: _zero,
        );
        async.flushMicrotasks();
        expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));

        gate.open();
        expect(h.settle(first), FetchResult.updated);
        expect(h.settle(second), FetchResult.updated);
        expect(h.settle(third), isTrue);
        expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));
      },
    );

    fakeTest(
      '5.5 a call made after the stale generation changed waits, then sends its own',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        final Gate gate = Gate();
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(
            entries: <String, String>{'a': '1'},
          ).after(gate.future),
        );
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(entries: <String, String>{'a': '2'}),
        );

        final Future<FetchResult> first = env.remoteConfig.fetch();
        async.flushMicrotasks();
        h.settle(
          env.remoteConfig.setCustomSignals(<String, Object?>{'tier': 'gold'}),
        );
        final Future<FetchResult> second = env.remoteConfig.fetch();
        async.flushMicrotasks();
        expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));

        gate.open();
        expect(h.settle(first), FetchResult.updated);
        expect(h.settle(second), FetchResult.updated);
        final List<RecordedRequest> requests = env.backend.requestsTo(
          FakeRoute.fetch,
        );
        expect(requests, hasLength(2));
        expect(requests[0].json.containsKey('custom_signals'), isFalse);
        expect(requests[1].json['custom_signals'], <String, Object?>{
          'tier': 'gold',
        });
      },
    );
  });

  group('throttle', () {
    fakeTest(
      '5.5 throttle table: n-th 503 waits entry min(n, 8) of 2..256 minutes',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        for (int n = 1; n <= 10; n++) {
          final Duration wait = Duration(
            minutes: _throttleMinutes[(n < 8 ? n : 8) - 1],
          );
          env.backend.enqueue(FakeRoute.fetch, FakeAnswer.status(503));
          final DateTime failedAt = h.now();
          final FirebaseRemoteConfigException error = h.rcError(
            env.remoteConfig.fetch(minimumFetchInterval: _zero),
          );
          expect(error.code, 'fetch-status', reason: 'failure $n');
          expect(error.httpStatus, 503, reason: 'failure $n');
          expect(
            error.throttledUntil,
            failedAt.add(wait),
            reason: 'failure $n',
          );
          expect(
            env.remoteConfig.info.throttledUntil,
            failedAt.add(wait),
            reason: 'failure $n',
          );

          async.elapse(wait - const Duration(milliseconds: 1));
          final int sent = env.backend.requests.length;
          final FirebaseRemoteConfigException throttled = h.rcError(
            env.remoteConfig.fetch(minimumFetchInterval: _zero),
          );
          expect(throttled.code, 'fetch-throttle', reason: 'failure $n');
          expect(
            throttled.throttledUntil,
            failedAt.add(wait),
            reason: 'failure $n',
          );
          expect(env.backend.requests, hasLength(sent), reason: 'failure $n');
          expect(
            env.remoteConfig.info.lastFetchStatus,
            RemoteConfigFetchStatus.throttled,
          );

          async.elapse(const Duration(milliseconds: 1));
        }
      },
    );

    for (final ({double random, Duration wait}) row
        in <({double random, Duration wait})>[
          (random: 0.0, wait: const Duration(minutes: 1)),
          (random: 0.25, wait: const Duration(seconds: 90)),
          (random: 0.999, wait: const Duration(milliseconds: 179880)),
        ]) {
      fakeTest(
        '5.5 throttle factor: random ${row.random} makes the first wait ${row.wait}',
        (FakeAsync async, Harness h) {
          final RcEnv env = h.env(random: () => row.random);
          env.backend.enqueue(FakeRoute.fetch, FakeAnswer.status(503));
          final DateTime failedAt = h.now();
          final FirebaseRemoteConfigException error = h.rcError(
            env.remoteConfig.fetch(),
          );
          expect(error.throttledUntil, failedAt.add(row.wait));
        },
      );
    }

    for (final int status in <int>[429, 502, 503, 504]) {
      fakeTest('5.5 status $status starts a throttle window', (
        FakeAsync async,
        Harness h,
      ) {
        final RcEnv env = h.env();
        env.backend.enqueue(FakeRoute.fetch, FakeAnswer.status(status));
        final DateTime failedAt = h.now();

        final FirebaseRemoteConfigException error = h.rcError(
          env.remoteConfig.fetch(),
        );
        expect(error.code, status == 429 ? 'fetch-throttle' : 'fetch-status');
        expect(error.httpStatus, status);
        expect(error.throttledUntil, failedAt.add(const Duration(minutes: 2)));
        expect(
          env.remoteConfig.info.throttledUntil,
          failedAt.add(const Duration(minutes: 2)),
        );
        if (status == 429) {
          expect(
            env.remoteConfig.info.lastFetchStatus,
            RemoteConfigFetchStatus.throttled,
          );
        }

        expect(h.rcError(env.remoteConfig.fetch()).code, 'fetch-throttle');
        expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));
      });
    }

    for (final int status in <int>[400, 401, 403, 404, 408, 500, 501]) {
      fakeTest('5.5 status $status is fetch-status and does not throttle', (
        FakeAsync async,
        Harness h,
      ) {
        final RcEnv env = h.env();
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.status(
            status,
            serverStatus: 'SOME_STATUS',
            message: 'line\nbreak',
          ),
        );

        final FirebaseRemoteConfigException error = h.rcError(
          env.remoteConfig.fetch(),
        );
        expect(error.code, 'fetch-status');
        expect(error.httpStatus, status);
        expect(error.serverStatus, 'SOME_STATUS');
        expect(error.serverMessage, 'linebreak');
        expect(error.throttledUntil, isNull);
        expect(env.remoteConfig.info.throttledUntil, isNull);
        expect(
          env.remoteConfig.info.lastFetchStatus,
          RemoteConfigFetchStatus.failure,
        );

        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(state: 'NO_CHANGE'),
        );
        expect(h.settle(env.remoteConfig.fetch()), FetchResult.unchanged);
      });
    }

    fakeTest(
      '5.5 a transport error is fetch-client-network and does not throttle',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        env.backend.enqueue(FakeRoute.fetch, FakeAnswer.transportError());

        final FirebaseRemoteConfigException error = h.rcError(
          env.remoteConfig.fetch(),
        );
        expect(error.code, 'fetch-client-network');
        expect(error.cause, isNotNull);
        expect(env.remoteConfig.info.throttledUntil, isNull);

        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(state: 'NO_CHANGE'),
        );
        expect(h.settle(env.remoteConfig.fetch()), FetchResult.unchanged);
      },
    );

    fakeTest('5.5 a validation failure does not throttle and stores nothing', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.json(<String, Object?>{
          'state': 'UPDATE',
          'entries': <String, Object?>{'a': 1},
        }),
      );

      expect(h.rcError(env.remoteConfig.fetch()).code, 'fetch-client-parse');
      expect(env.remoteConfig.info.throttledUntil, isNull);
      expect(env.remoteConfig.info.fetchedTemplateVersion, isNull);
      expect(h.settle(env.readRecord('fetched')), isNull);
      expect(h.settle(env.readRecord('throttle')), isNull);

      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(entries: <String, String>{'a': '1'}),
      );
      expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);
    });

    fakeTest('5.5 a valid 200 resets the throttle count', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      env.backend.enqueue(FakeRoute.fetch, FakeAnswer.status(503));
      h.rcError(env.remoteConfig.fetch());
      async.elapse(const Duration(minutes: 2));
      env.backend.enqueue(FakeRoute.fetch, FakeAnswer.status(503));
      expect(
        h.rcError(env.remoteConfig.fetch()).throttledUntil,
        h.now().add(const Duration(minutes: 4)),
      );
      async.elapse(const Duration(minutes: 4));

      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(state: 'NO_CHANGE'),
      );
      expect(h.settle(env.remoteConfig.fetch()), FetchResult.unchanged);
      expect(env.remoteConfig.info.throttledUntil, isNull);

      env.backend.enqueue(FakeRoute.fetch, FakeAnswer.status(503));
      expect(
        h
            .rcError(env.remoteConfig.fetch(minimumFetchInterval: _zero))
            .throttledUntil,
        h.now().add(const Duration(minutes: 2)),
      );
    });

    fakeTest('5.5 a throttled fetch sends nothing, Installations included', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      env.backend.enqueue(FakeRoute.fetch, FakeAnswer.status(503));
      h.rcError(env.remoteConfig.fetch());
      // Without a stored installation, any call to getIdAndToken would send a create request.
      h.settle(env.installations.delete());
      env.backend.clearRequests();

      final FirebaseRemoteConfigException error = h.rcError(
        env.remoteConfig.fetch(),
      );
      expect(error.code, 'fetch-throttle');
      expect(env.backend.requests, isEmpty);
    });

    fakeTest('5.5 minimumFetchInterval zero does not bypass the throttle', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env(minimumFetchInterval: _zero);
      env.backend.enqueue(FakeRoute.fetch, FakeAnswer.status(504));
      h.rcError(env.remoteConfig.fetch());

      expect(h.rcError(env.remoteConfig.fetch()).code, 'fetch-throttle');
      expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));
    });

    fakeTest('5.5 a new instance on the same store is still throttled (5.10)', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      env.backend.enqueue(FakeRoute.fetch, FakeAnswer.status(503));
      final DateTime until = h
          .rcError(env.remoteConfig.fetch())
          .throttledUntil!;
      h.settle(env.remoteConfig.close());

      final FirebaseRemoteConfig other = env.newRemoteConfig(random: () => 0.5);
      h.settle(other.ensureInitialized());
      expect(other.info.throttledUntil, until);
      final FirebaseRemoteConfigException error = h.rcError(other.fetch());
      expect(error.code, 'fetch-throttle');
      expect(error.throttledUntil, until);
      expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));
    });
  });

  group('ETag', () {
    fakeTest('5.5 If-None-Match is sent only when an ETag is stored', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env(minimumFetchInterval: _zero);
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(entries: <String, String>{'a': '1'}, etag: 'etag-1'),
      );
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(entries: <String, String>{'a': '2'}),
      );
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(state: 'NO_CHANGE'),
      );

      h.settle(env.remoteConfig.fetch());
      h.settle(env.remoteConfig.fetch());
      h.settle(env.remoteConfig.fetch());

      final List<RecordedRequest> requests = env.backend.requestsTo(
        FakeRoute.fetch,
      );
      expect(requests[0].headers.containsKey('if-none-match'), isFalse);
      expect(requests[1].headers['if-none-match'], 'etag-1');
      // The second answer had no ETag, so the stored record has none.
      expect(requests[2].headers.containsKey('if-none-match'), isFalse);
    });

    for (final String bad in <String>[
      'etag\r\nX-Injected: 1',
      'etag\nx',
      'etag\x00',
      'etag\x7f',
    ]) {
      fakeTest(
        '5.5 an ETag with control characters (${jsonEncode(bad)}) is dropped',
        (FakeAsync async, Harness h) {
          final RcEnv env = h.env(minimumFetchInterval: _zero);
          env.backend.enqueue(
            FakeRoute.fetch,
            FakeAnswer.fetch(entries: <String, String>{'a': '1'}, etag: bad),
          );
          env.backend.enqueue(
            FakeRoute.fetch,
            FakeAnswer.fetch(state: 'NO_CHANGE'),
          );

          expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);
          expect(
            h.settle(env.readRecord('fetched'))!.containsKey('etag'),
            isFalse,
          );
          h.settle(env.remoteConfig.fetch());
          expect(
            env.backend
                .requestsTo(FakeRoute.fetch)
                .last
                .headers
                .containsKey('if-none-match'),
            isFalse,
          );
        },
      );
    }

    fakeTest('5.5 an ETag is kept up to 1024 bytes and dropped above', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env(minimumFetchInterval: _zero);
      final String longest = 'e' * 1024;
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(entries: <String, String>{'a': '1'}, etag: longest),
      );
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(
          entries: <String, String>{'a': '2'},
          etag: '${longest}e',
        ),
      );
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(state: 'NO_CHANGE'),
      );

      h.settle(env.remoteConfig.fetch());
      h.settle(env.remoteConfig.fetch());
      h.settle(env.remoteConfig.fetch());

      final List<RecordedRequest> requests = env.backend.requestsTo(
        FakeRoute.fetch,
      );
      expect(requests[1].headers['if-none-match'], longest);
      expect(requests[2].headers.containsKey('if-none-match'), isFalse);
    });
  });

  group('response validation', () {
    final Map<String, Object> badBodies = <String, Object>{
      'not JSON': '{"state": "UPDATE"',
      'not an object': '["UPDATE"]',
      'state not a string': <String, Object?>{'state': 5},
      'entries not an object': <String, Object?>{
        'entries': <Object?>['a'],
      },
      'entries with a number value': <String, Object?>{
        'entries': <String, Object?>{'a': 1},
      },
      'entries with a null value': <String, Object?>{
        'entries': <String, Object?>{'a': null},
      },
      'templateVersion with a fraction': <String, Object?>{
        'templateVersion': '1.5',
      },
      'templateVersion negative': <String, Object?>{'templateVersion': -1},
      'templateVersion 2^53': <String, Object?>{
        'templateVersion': '9007199254740992',
      },
      'templateVersion hex': <String, Object?>{'templateVersion': '0x10'},
      'templateVersion with a space': <String, Object?>{
        'templateVersion': ' 1',
      },
      'nesting of 33': '{"x":${'[' * 32}${']' * 32}}',
    };
    for (final MapEntry<String, Object> bad in badBodies.entries) {
      fakeTest('5.5 ${bad.key} is fetch-client-parse and stores nothing', (
        FakeAsync async,
        Harness h,
      ) {
        final RcEnv env = h.env();
        final Object body = bad.value;
        env.backend.enqueue(
          FakeRoute.fetch,
          body is String ? FakeAnswer.text(body) : FakeAnswer.json(body),
        );

        final FirebaseRemoteConfigException error = h.rcError(
          env.remoteConfig.fetch(),
        );
        expect(error.code, 'fetch-client-parse');
        expect(h.settle(env.readRecord('fetched')), isNull);
        expect(
          env.remoteConfig.info.lastFetchStatus,
          RemoteConfigFetchStatus.failure,
        );
      });
    }

    final Map<String, Object?> goodVersions = <String, Object?>{
      'a JSON integer': 7,
      'a decimal string': '7',
      '2^53 - 1': '9007199254740991',
      'zero': '0',
    };
    for (final MapEntry<String, Object?> good in goodVersions.entries) {
      fakeTest('5.5 templateVersion as ${good.key} is accepted', (
        FakeAsync async,
        Harness h,
      ) {
        final RcEnv env = h.env();
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(templateVersion: good.value),
        );

        expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);
        expect(
          env.remoteConfig.info.fetchedTemplateVersion,
          good.value is int ? good.value : int.parse(good.value! as String),
        );
      });
    }

    fakeTest('5.5 nesting of exactly 32 is accepted', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.text('{"state":"UPDATE","x":${'[' * 31}${']' * 31}}'),
      );

      expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);
    });

    fakeTest(
      '5.5 metadata of the wrong shape is dropped item by item, the rest kept and logged',
      (FakeAsync async, Harness h) {
        final List<String> logs = <String>[];
        final RcEnv env = h.env(
          logger: (RemoteConfigLogLevel level, String message) =>
              logs.add(message),
        );
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(
            entries: <String, String>{'a': '1'},
            templateVersion: '3',
            extra: <String, Object?>{
              'experimentDescriptions': <Object?>[
                <String, Object?>{
                  'experimentId': 'exp-good',
                  'variantId': 'v1',
                  'experimentStartTime': '2026-11-01T00:00:00Z',
                  'triggerTimeoutMillis': '1000',
                  'timeToLiveMillis': '2000',
                  'affectedParameterKeys': <Object?>['a'],
                },
                <String, Object?>{'experimentId': 5, 'variantId': 'v2'},
                <String, Object?>{
                  'experimentId': 'exp-bad-ttl',
                  'variantId': 'v3',
                  'timeToLiveMillis': '1e3',
                },
                'secret-junk',
              ],
              'rolloutMetadata': 'not a list',
              'personalizationMetadata': <String, Object?>{
                'a': <String, Object?>{
                  'personalizationId': 'p1',
                  'armIndex': 1,
                  'group': 'g',
                  'choiceId': 'c',
                },
                'b': <String, Object?>{'armIndex': 'secret-arm'},
              },
            },
          ),
        );

        expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);

        final Map<String, Object?> fetched = h.settle(
          env.readRecord('fetched'),
        )!;
        expect(fetched['entries'], <String, Object?>{'a': '1'});
        expect(fetched['templateVersion'], 3);
        final List<Object?> experiments =
            fetched['experimentDescriptions']! as List<Object?>;
        expect(experiments, hasLength(1));
        expect(
          (experiments.single! as Map<String, Object?>)['experimentId'],
          'exp-good',
        );
        expect(fetched['rolloutMetadata'], isEmpty);
        final Map<String, Object?> personalization =
            fetched['personalizationMetadata']! as Map<String, Object?>;
        expect(personalization.keys, <String>['a']);
        expect(logs, isNotEmpty);
        expect(logs.join('\n'), isNot(contains('secret')));
      },
    );
  });

  group('errors', () {
    fakeTest('5.5 one deadline covers the call, Installations included', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env(
        register: false,
        fetchTimeout: const Duration(seconds: 5),
      );
      env.backend.enqueue(FakeRoute.installationsCreate, FakeAnswer.hang());

      bool done = false;
      final Future<FetchResult> fetch = env.remoteConfig.fetch()
        ..ignore()
        ..whenComplete(() => done = true).ignore();
      async.elapse(
        const Duration(seconds: 5) - const Duration(milliseconds: 1),
      );
      expect(done, isFalse);
      expect(env.backend.requestsTo(FakeRoute.fetch), isEmpty);

      async.elapse(const Duration(milliseconds: 1));
      final FirebaseRemoteConfigException error = h.rcError(fetch);
      expect(error.code, 'fetch-timeout');
    });

    fakeTest(
      '5.5 a hanging fetch request ends with fetch-timeout at the call\'s timeout',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        env.backend.enqueue(FakeRoute.fetch, FakeAnswer.hang());

        final Future<FetchResult> fetch = env.remoteConfig.fetch(
          timeout: const Duration(seconds: 3),
        );
        final FirebaseRemoteConfigException error = h.rcErrorWithin(
          fetch,
          const Duration(seconds: 3),
        );
        expect(error.code, 'fetch-timeout');
        expect(env.backend.requestsTo(FakeRoute.fetch).single.aborted, isTrue);
        expect(env.remoteConfig.info.throttledUntil, isNull);
      },
    );

    fakeTest(
      '5.5 an Installations failure is installations-error with the cause',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(register: false);
        env.backend.enqueue(
          FakeRoute.installationsCreate,
          FakeAnswer.status(400),
        );

        final FirebaseRemoteConfigException error = h.rcError(
          env.remoteConfig.fetch(),
        );
        expect(error.code, 'installations-error');
        expect(error.cause, isA<FirebaseInstallationsException>());
        expect(env.backend.requestsTo(FakeRoute.fetch), isEmpty);
      },
    );

    for (final int status in <int>[301, 302, 307]) {
      fakeTest('5.5 a $status on the VM is fetch-status and is not followed', (
        FakeAsync async,
        Harness h,
      ) {
        final RcEnv env = h.env();
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.text(
            '',
            status: status,
            headers: <String, String>{'location': 'https://evil.example/'},
          ),
        );

        final FirebaseRemoteConfigException error = h.rcError(
          env.remoteConfig.fetch(),
        );
        expect(error.code, 'fetch-status');
        expect(error.httpStatus, status);
        expect(
          env.backend.requests.where(
            (RecordedRequest r) => r.url.host == 'evil.example',
          ),
          isEmpty,
        );
        expect(
          env.backend.requestsTo(FakeRoute.fetch).single.followRedirects,
          isFalse,
        );
      });
    }

    fakeTest(
      '5.4 fetch after close fails with remote-config-closed and sends nothing',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        h.settle(env.remoteConfig.close());
        env.backend.clearRequests();

        expect(
          h.rcError(env.remoteConfig.fetch()).code,
          'remote-config-closed',
        );
        expect(
          h.rcError(env.remoteConfig.fetchAndActivate()).code,
          'remote-config-closed',
        );
        expect(env.backend.requests, isEmpty);
      },
    );

    fakeTest('5.4 close aborts a fetch in flight with remote-config-closed', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env();
      env.backend.enqueue(FakeRoute.fetch, FakeAnswer.hang());
      // Ignored: the fetch fails while close() is being settled, before the test listens to it.
      final Future<FetchResult> fetch = env.remoteConfig.fetch()..ignore();
      async.flushMicrotasks();
      expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));

      h.settle(env.remoteConfig.close());
      expect(h.rcError(fetch).code, 'remote-config-closed');
      expect(env.backend.requestsTo(FakeRoute.fetch).single.aborted, isTrue);
    });
  });

  group('language (5.6)', () {
    fakeTest('5.6 languageCode is sent as language_code', (
      FakeAsync async,
      Harness h,
    ) {
      final RcEnv env = h.env(languageCode: 'ro-RO');
      env.backend.enqueue(
        FakeRoute.fetch,
        FakeAnswer.fetch(state: 'NO_CHANGE'),
      );
      h.settle(env.remoteConfig.fetch());

      expect(
        env.backend.requestsTo(FakeRoute.fetch).single.json['language_code'],
        'ro-RO',
      );
    });

    fakeTest(
      '5.6 without languageCode the VM sends Platform.localeName reduced to BCP 47',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(languageCode: null);
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(state: 'NO_CHANGE'),
        );
        h.settle(env.remoteConfig.fetch());

        final Object? sent = env.backend
            .requestsTo(FakeRoute.fetch)
            .single
            .json['language_code'];
        expect(sent, normalizeLanguageTag(Platform.localeName));
        expect(
          sent,
          isNot(anyOf(contains('_'), contains('.'), contains('@'), isEmpty)),
        );
      },
    );

    final Map<String, String> table = <String, String>{
      'en_US.UTF-8': 'en-US',
      'de_DE@euro': 'de-DE',
      'pt_BR.UTF-8@latin': 'pt-BR',
      'sr_RS@latin.UTF-8': 'sr-RS',
      'fr': 'fr',
      'en-GB': 'en-GB',
      'zh_Hant_TW': 'zh-Hant-TW',
      '': 'en',
      '.UTF-8': 'en',
      '@euro': 'en',
    };
    for (final MapEntry<String, String> row in table.entries) {
      test('5.6 ${jsonEncode(row.key)} → ${row.value}', () {
        expect(normalizeLanguageTag(row.key), row.value);
      });
    }
  });
}
