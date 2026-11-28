// Round 3 of the Remote Config tests: the as-built addendum of spec v4 (A9, A13, A19-A21) and the
// fields of 5.10 it touches.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:firebase_remote_config_dart/src/records.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/rc_fetch_harness.dart';
import 'support/rc_realtime_fakes.dart';
import 'support/rc_realtime_harness.dart';

const Duration _zero = Duration.zero;

/// [seconds] as a [Duration], fractions allowed.
Duration s(num seconds) => Duration(microseconds: (seconds * 1000000).round());

/// The largest version a stored record may carry (2^53 - 1).
const int _maxVersion = 9007199254740991;

/// A stored `fetched` record with [version], fetched at [fetchTime].
String _fetchedText({
  required int version,
  required DateTime fetchTime,
  String? etag,
  Map<String, String> entries = const <String, String>{'a': 'stored'},
}) => TemplateRecord(
  entries: entries,
  fetchTime: fetchTime,
  etag: etag,
  templateVersion: version,
).encode();

/// A stored `meta` record of a successful fetch at [last]; [extra] is merged in (a `fid`).
String _metaText(
  DateTime last, {
  Map<String, Object?> extra = const <String, Object?>{},
}) => jsonEncode(<String, Object?>{
  'v': 1,
  'lastFetchStatus': 'success',
  'lastSuccessfulFetchTime': last.millisecondsSinceEpoch,
  'staleGeneration': 0,
  ...extra,
});

/// Writes [text] as the record [name] of [env].
void _seed(Harness h, RcEnv env, String name, String text) {
  h.settle(env.store.write(env.recordKey(name), text));
}

/// The stored `staleGeneration` of [env]'s meta record; 0 when there is none.
int _storedGeneration(Harness h, RcEnv env) {
  final Map<String, Object?>? meta = h.settle(env.readRecord('meta'));
  return meta == null ? 0 : meta['staleGeneration']! as int;
}

/// Replaces the installation id of [env] (delete, then a new one) and lets the listeners run.
String _changeId(Harness h, RcEnv env) {
  h.settle(env.installations.delete());
  final String fid = h.settle(env.installations.getId());
  h.settle(Future<void>.value());
  return fid;
}

int _skewApps = 0;

void main() {
  group('5.9.5 / A9 installation id change', () {
    fakeTest(
      'A9 a meta record without fid but with a successful fetch, then an ID change: the next fetch '
      'inside the interval goes to the network',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        final DateTime last = h.now().subtract(const Duration(hours: 1));
        _seed(h, env, 'meta', _metaText(last));
        _seed(
          h,
          env,
          'fetched',
          _fetchedText(version: 1, fetchTime: last, etag: 'etag-old'),
        );
        final FirebaseRemoteConfig remoteConfig = env.newRemoteConfig();
        h.settle(remoteConfig.ensureInitialized());

        // Inside the 12 h interval and before any ID change: the cache answers.
        expect(h.settle(remoteConfig.fetch()), FetchResult.cached);
        expect(env.backend.requestsTo(FakeRoute.fetch), isEmpty);

        final String fid = _changeId(h, env);
        expect(_storedGeneration(h, env), isNot(0));

        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(
            entries: <String, String>{'a': 'new'},
            templateVersion: '2',
          ),
        );
        expect(h.settle(remoteConfig.fetch()), FetchResult.updated);
        final RecordedRequest request = env.backend
            .requestsTo(FakeRoute.fetch)
            .single;
        expect(request.json['app_instance_id'], fid);
        expect(request.headers.containsKey('if-none-match'), isFalse);
      },
    );

    fakeTest(
      'A9 a fresh install: its first FID marks nothing stale, and the first fetch is then served '
      'from the cache',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env(register: false);
        h.settle(env.remoteConfig.ensureInitialized());

        // The first FID, created outside a fetch: onIdChange reaches the instance with no stored fid
        // and no successful fetch.
        final String fid = h.settle(env.installations.getId());
        h.settle(Future<void>.value());
        expect(_storedGeneration(h, env), 0);

        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(entries: <String, String>{'a': '1'}, etag: 'e1'),
        );
        expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);
        expect(
          env.backend
              .requestsTo(FakeRoute.fetch)
              .single
              .json['app_instance_id'],
          fid,
        );
        expect(h.settle(env.readRecord('meta'))!['fid'], fid);

        expect(h.settle(env.remoteConfig.fetch()), FetchResult.cached);
        expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));
      },
    );
  });

  group('5.10 meta fid field', () {
    for (final Object badFid in <Object>[5, '']) {
      test(
        '5.10 meta with "fid": ${jsonEncode(badFid)} drops only that field',
        () {
          final DateTime now = DateTime.utc(2026, 11, 28, 12);
          final DateTime last = now.subtract(const Duration(hours: 1));
          final MetaRecord? meta = MetaRecord.tryParse(
            jsonEncode(<String, Object?>{
              'v': 1,
              'lastFetchStatus': 'success',
              'lastSuccessfulFetchTime': last.millisecondsSinceEpoch,
              'staleGeneration': 3,
              'fid': badFid,
            }),
            now,
          );
          expect(meta, isNotNull);
          expect(meta!.fid, isNull);
          expect(meta.lastFetchStatus, RemoteConfigFetchStatus.success);
          expect(meta.lastSuccessfulFetchTime, last);
          expect(meta.staleGeneration, 3);
        },
      );

      fakeTest(
        '5.10 meta with "fid": ${jsonEncode(badFid)}: the record still loads, the cache answers, '
        'and a forced fetch sends no If-None-Match',
        (FakeAsync async, Harness h) {
          final RcEnv env = h.env();
          final DateTime last = h.now().subtract(const Duration(hours: 1));
          _seed(
            h,
            env,
            'meta',
            _metaText(last, extra: <String, Object?>{'fid': badFid}),
          );
          _seed(
            h,
            env,
            'fetched',
            _fetchedText(version: 1, fetchTime: last, etag: 'etag-old'),
          );
          final FirebaseRemoteConfig remoteConfig = env.newRemoteConfig();
          h.settle(remoteConfig.ensureInitialized());

          final RemoteConfigInfo info = remoteConfig.info;
          expect(info.lastFetchStatus, RemoteConfigFetchStatus.success);
          expect(info.lastSuccessfulFetchTime, last);
          expect(info.fetchedTemplateVersion, 1);
          expect(h.settle(remoteConfig.fetch()), FetchResult.cached);
          expect(env.backend.requestsTo(FakeRoute.fetch), isEmpty);

          // The dropped fid is not the request's FID, so the stored ETag is not sent.
          env.backend.enqueue(
            FakeRoute.fetch,
            FakeAnswer.fetch(
              entries: <String, String>{'a': 'new'},
              templateVersion: '2',
            ),
          );
          expect(
            h.settle(remoteConfig.fetch(minimumFetchInterval: _zero)),
            FetchResult.updated,
          );
          expect(
            env.backend
                .requestsTo(FakeRoute.fetch)
                .single
                .headers
                .containsKey('if-none-match'),
            isFalse,
          );
        },
      );
    }
  });

  group('5.5 / A21 the fetched record', () {
    fakeTest(
      'A21 a stored record with version 2^53-1 and an old fetch time is replaced by a fetch of v6',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        _seed(
          h,
          env,
          'fetched',
          _fetchedText(
            version: _maxVersion,
            fetchTime: h.now().subtract(const Duration(days: 1)),
          ),
        );
        final FirebaseRemoteConfig remoteConfig = env.newRemoteConfig();
        h.settle(remoteConfig.ensureInitialized());
        expect(remoteConfig.info.fetchedTemplateVersion, _maxVersion);

        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(
            entries: <String, String>{'a': 'six'},
            templateVersion: '6',
          ),
        );
        expect(
          h.settle(remoteConfig.fetch(minimumFetchInterval: _zero)),
          FetchResult.updated,
        );
        expect(remoteConfig.info.fetchedTemplateVersion, 6);
        expect(h.settle(env.readRecord('fetched'))!['templateVersion'], 6);
      },
    );

    fakeTest(
      'A13 / A21 a stored record with a future fetch time and v9 is replaced by a fetch of v6',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        _seed(
          h,
          env,
          'fetched',
          _fetchedText(
            version: 9,
            fetchTime: h.now().add(const Duration(days: 1)),
          ),
        );
        final FirebaseRemoteConfig remoteConfig = env.newRemoteConfig();
        h.settle(remoteConfig.ensureInitialized());
        expect(remoteConfig.info.fetchedTemplateVersion, 9);

        async.elapse(const Duration(minutes: 1));
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(
            entries: <String, String>{'a': 'six'},
            templateVersion: '6',
          ),
        );
        expect(
          h.settle(remoteConfig.fetch(minimumFetchInterval: _zero)),
          FetchResult.updated,
        );
        expect(remoteConfig.info.fetchedTemplateVersion, 6);
        final Map<String, Object?> stored = h.settle(
          env.readRecord('fetched'),
        )!;
        expect(stored['templateVersion'], 6);
        expect(stored['fetchTime'], h.now().millisecondsSinceEpoch);
      },
    );

    fakeTest(
      'A21 two instances: B stores v6 while A\'s v5 request is in flight; v6 is kept',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        final FirebaseRemoteConfig a = env.remoteConfig;
        final FirebaseRemoteConfig b = env.newRemoteConfig();
        h.settle(b.ensureInitialized());

        final Gate gate = Gate();
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(
            entries: <String, String>{'a': 'five'},
            templateVersion: '5',
          ).after(gate.future),
        );
        final Future<FetchResult> slow = a.fetch(minimumFetchInterval: _zero);
        async.flushMicrotasks();
        expect(env.backend.requestsTo(FakeRoute.fetch), hasLength(1));

        async.elapse(const Duration(seconds: 1));
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(
            entries: <String, String>{'a': 'six'},
            templateVersion: '6',
          ),
        );
        expect(
          h.settle(b.fetch(minimumFetchInterval: _zero)),
          FetchResult.updated,
        );
        expect(h.settle(env.readRecord('fetched'))!['templateVersion'], 6);

        async.elapse(const Duration(seconds: 1));
        gate.open();
        h.settle(slow);

        expect(h.settle(env.readRecord('fetched'))!['templateVersion'], 6);
        expect(a.info.fetchedTemplateVersion, 6);
        expect(h.settle(a.activate()), isTrue);
        expect(a.getString('a'), 'six');
      },
    );

    fakeTest(
      'A14 / A21 the store holds v5 with a future time and the write of v6 fails: activate '
      'activates v6',
      (FakeAsync async, Harness h) {
        final ScriptedStore store = ScriptedStore();
        final RcEnv env = h.env(store: store);
        h.settle(
          store.inner.write(
            env.recordKey('fetched'),
            _fetchedText(
              version: 5,
              fetchTime: h.now().add(const Duration(days: 1)),
              entries: const <String, String>{'a': 'five'},
            ),
          ),
        );
        final FirebaseRemoteConfig remoteConfig = env.newRemoteConfig();
        h.settle(remoteConfig.ensureInitialized());
        expect(remoteConfig.info.fetchedTemplateVersion, 5);

        final String fetchedKey = env.recordKey('fetched');
        store.before = (StoreOp op, String key) {
          if (key == fetchedKey && op != StoreOp.read) {
            throw StateError('fake write failure');
          }
        };
        async.elapse(const Duration(minutes: 1));
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(
            entries: <String, String>{'a': 'six'},
            templateVersion: '6',
          ),
        );
        expect(
          h.settle(remoteConfig.fetch(minimumFetchInterval: _zero)),
          FetchResult.updated,
        );
        expect(remoteConfig.info.fetchedTemplateVersion, 6);
        expect(
          h.settle(store.inner.read(fetchedKey)),
          contains('"templateVersion":5'),
          reason: 'the write failed; the store still holds v5',
        );

        expect(h.settle(remoteConfig.activate()), isTrue);
        expect(remoteConfig.info.activeTemplateVersion, 6);
        expect(remoteConfig.getString('a'), 'six');
        expect(h.settle(env.readRecord('active'))!['templateVersion'], 6);
      },
    );
  });

  group('5.9.2 / A19 auto-fetch cool-down', () {
    test(
      'A19 an up-to-date chain, then higher announcements: each is fetched with no 60 s wait',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.server.fetchAnswer = (FetchCall call) =>
              templateResponse(version: 2);
          final UpdateLog log = h.listen();
          h.server.last.send('{"latestTemplateVersionNumber": "2"}');
          h.elapseTo(s(10));
          expect(h.server.fetches, hasLength(1));

          h.server.fetchAnswer = (FetchCall call) => templateResponse(
            version: 3,
            entries: const <String, String>{'welcome': 'three'},
          );
          h.server.last.send('{"latestTemplateVersionNumber": "3"}');
          h.elapseTo(s(11.5));
          expect(h.server.fetches, hasLength(2));

          h.server.fetchAnswer = (FetchCall call) => templateResponse(
            version: 4,
            entries: const <String, String>{'welcome': 'four'},
          );
          h.server.last.send('{"latestTemplateVersionNumber": "4"}');
          h.elapseTo(s(13));
          expect(h.server.fetches, hasLength(3));

          expect(
            <Duration>[
              for (final FetchCall call in h.server.fetches)
                call.at.difference(rcEpoch),
            ],
            <Duration>[s(1.5), s(11.5), s(13)],
          );
          expect(
            <String?>[
              for (final FetchCall call in h.server.fetches) call.fetchType,
            ],
            <String>['REALTIME/1', 'REALTIME/1', 'REALTIME/1'],
          );
          expect(h.remoteConfig.info.fetchedTemplateVersion, 4);
          expect(log.updates, hasLength(3));
          expect(log.errors, isEmpty);
          h.dispose();
        });
      },
    );

    test(
      'A19 a throttled chain plus rising announcements: at most one chain per 60 s',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          h.server.fetchAnswer = (FetchCall call) => http.Response('{}', 429);
          final List<Duration> errorTimes = <Duration>[];
          final List<String> codes = <String>[];
          final StreamSubscription<RemoteConfigUpdate> subscription = h
              .remoteConfig
              .onConfigUpdated
              .listen(
                (RemoteConfigUpdate _) {},
                onError: (Object error) {
                  errorTimes.add(async.elapsed);
                  if (error is FirebaseRemoteConfigException) {
                    codes.add(error.code);
                  }
                },
              );
          async.elapse(Duration.zero);
          expect(h.server.connections, hasLength(1));

          // A higher version every 5 s for 300 s.
          for (int i = 0; i < 60; i++) {
            h.elapseTo(s(i * 5));
            h.server.last.send('{"latestTemplateVersionNumber": "${i + 1}"}');
          }
          h.elapseTo(s(300));

          expect(errorTimes.length, greaterThanOrEqualTo(3));
          expect(errorTimes.length, lessThanOrEqualTo(5));
          for (int i = 1; i < errorTimes.length; i++) {
            expect(
              errorTimes[i] - errorTimes[i - 1],
              greaterThanOrEqualTo(s(60)),
              reason: 'chain ${i + 1} started within 60 s of chain $i',
            );
          }
          expect(codes.toSet(), <String>{'update-not-fetched'});
          expect(
            h.server.fetches.length,
            lessThanOrEqualTo(errorTimes.length),
            reason: 'each chain ends on its first failed attempt',
          );
          unawaited(subscription.cancel());
          h.dispose();
        });
      },
    );

    test(
      'A19 the clock stepped back during a cool-down: the deferred chain still runs within 60 s',
      () {
        fakeAsync((FakeAsync async) {
          Duration skew = Duration.zero;
          DateTime now() => rcEpoch.add(async.elapsed).add(skew);
          final RealtimeServer server = RealtimeServer(now);
          final FirebaseApp app = FirebaseApp.withOptions(
            rcOptions,
            name: 'rc-r3-skew-${_skewApps++}',
          );
          final FakeInstallations installations = FakeInstallations(
            now,
            app: app,
          );
          final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig(
            app,
            installations: installations,
            languageCode: 'en',
            httpClient: server.client,
            serverOrigin: rcServerOrigin,
            realtimeOrigin: rcRealtimeOrigin,
            clock: now,
            random: () => 0.5,
          );
          async.flushMicrotasks();
          server.fetchAnswer = (FetchCall call) => templateResponse(version: 1);
          final UpdateLog log = UpdateLog()
            ..listen(remoteConfig.onConfigUpdated);
          async.elapse(Duration.zero);

          // A stale chain (attempts at 1.5, 3 and 4.5 s): cool-down until 64.5 s on the clock.
          server.last.send('{"latestTemplateVersionNumber": "2"}');
          async.elapse(s(10));
          expect(server.fetches, hasLength(3));
          expect(log.codes, <String>['update-not-fetched']);

          // The clock steps back one hour; version 3 is announced at 10 s of fake time.
          skew = const Duration(hours: -1);
          server.fetchAnswer = (FetchCall call) => templateResponse(version: 3);
          server.last.send('{"latestTemplateVersionNumber": "3"}');
          async.elapse(s(60) - const Duration(milliseconds: 1));
          expect(
            server.fetches,
            hasLength(3),
            reason: 'still in the 60 s wait',
          );

          // The wait is capped at 60 s (until 70 s), then the attempt follows the 1.5 s jitter.
          async.elapse(s(1.5) + const Duration(milliseconds: 1));
          expect(server.fetches, hasLength(4));
          expect(server.fetches.last.fetchType, 'REALTIME/1');
          expect(remoteConfig.info.fetchedTemplateVersion, 3);
          expect(log.codes, <String>['update-not-fetched']);

          log.cancel();
          unawaited(remoteConfig.close());
          unawaited(app.delete());
          async.flushMicrotasks();
        });
      },
    );
  });

  group('5.9.1 / A20 network regained', () {
    test(
      'A20 retryIntervalSeconds 600, then network false -> true: no connect before 600 s',
      () {
        fakeAsync((FakeAsync async) {
          final DirectRealtime d = DirectRealtime(async);
          d.listen();
          d.server.last.send('{"retryIntervalSeconds": 600}');
          d.elapseTo(s(61));
          d.server.last.end();
          d.elapseTo(s(100));
          expect(d.server.connections, hasLength(1));

          d.network.add(false);
          d.elapseTo(s(100.5));
          d.network.add(true);
          d.elapseTo(s(599.999));
          expect(
            d.server.connections,
            hasLength(1),
            reason: 'the server\'s wait outlives a regained network',
          );
          d.elapseTo(s(600));
          expect(d.server.connections, hasLength(2));
          d.dispose();
        });
      },
    );
  });
}
