// Round 4 of the Remote Config tests: the as-built addendum of spec v4 (A25-A28, A35) and the fetch,
// activate and close rules it refines.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
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

/// A stored template record with [version] (none when null), fetched at [fetchTime].
String _recordText({
  required int? version,
  required DateTime fetchTime,
  String? etag,
  Map<String, String> entries = const <String, String>{'a': 'stored'},
}) => TemplateRecord(
  entries: entries,
  fetchTime: fetchTime,
  etag: etag,
  templateVersion: version,
).encode();

/// A stored `meta` record of a successful fetch at [last] made with [fid].
String _metaText(DateTime last, {String? fid}) => jsonEncode(<String, Object?>{
  'v': 1,
  'lastFetchStatus': 'success',
  'lastSuccessfulFetchTime': last.millisecondsSinceEpoch,
  'staleGeneration': 0,
  'fid': ?fid,
});

/// Writes [text] as the record [name] of [env].
void _seed(Harness h, RcEnv env, String name, String text) {
  h.settle(env.store.write(env.recordKey(name), text));
}

/// A fetch answer of 200 with `"state": "NO_CHANGE"`.
http.Response _noChange() => http.Response(
  '{"state": "NO_CHANGE"}',
  200,
  headers: <String, String>{'content-type': 'application/json'},
);

/// A fetch answer of 200 with template [version] and the `ETag` [etag].
http.Response _taggedTemplate(int version, String etag) => http.Response(
  jsonEncode(<String, Object?>{
    'state': 'UPDATE',
    'entries': <String, String>{'welcome': 'v$version'},
    'templateVersion': '$version',
  }),
  200,
  headers: <String, String>{'content-type': 'application/json', 'etag': etag},
);

/// The `If-None-Match` header of [call], or null.
String? _ifNoneMatch(FetchCall call) => call.request.headers['If-None-Match'];

/// The realtime fetches [server] received.
List<FetchCall> _realtimeCalls(RealtimeServer server) => <FetchCall>[
  for (final FetchCall call in server.fetches)
    if (call.fetchType?.startsWith('REALTIME/') ?? false) call,
];

/// The fake times, as offsets from [rcEpoch], of the realtime fetches [server] received.
List<Duration> _realtimeTimes(RealtimeServer server) => <Duration>[
  for (final FetchCall call in server.fetches)
    if (call.fetchType?.startsWith('REALTIME/') ?? false)
      call.at.difference(rcEpoch),
];

/// The fetch types of the realtime fetches [server] received.
List<String?> _realtimeTypes(RealtimeServer server) => <String?>[
  for (final FetchCall call in server.fetches)
    if (call.fetchType?.startsWith('REALTIME/') ?? false) call.fetchType,
];

/// An Installations instance whose `getIdAndToken` can be held, with an `onIdChange` the test drives.
final class _HeldInstallations implements FirebaseInstallations {
  _HeldInstallations(this.app, {KeyValueStore? store})
    : store = store ?? MemoryKeyValueStore();

  @override
  final FirebaseApp app;

  @override
  final KeyValueStore store;

  @override
  Map<String, String> get headers => const <String, String>{};

  final StreamController<String> _ids = StreamController<String>.broadcast();

  /// The FID the next calls return.
  String fid = rcFirstFid;

  /// Calls of [getIdAndToken].
  int calls = 0;

  Completer<void>? _hold;

  @override
  Stream<String> get onIdChange => _ids.stream;

  /// Makes the next calls of [getIdAndToken] wait for [release].
  void hold() => _hold = Completer<void>();

  /// Lets the held calls return.
  void release() {
    final Completer<void>? hold = _hold;
    _hold = null;
    hold?.complete();
  }

  /// Switches to [id] and emits it on [onIdChange].
  void emitId(String id) {
    fid = id;
    _ids.add(id);
  }

  @override
  Future<({String id, String token})> getIdAndToken({
    bool forceRefresh = false,
  }) async {
    calls++;
    final Completer<void>? hold = _hold;
    if (hold != null) {
      await hold.future;
    }
    return (id: fid, token: 'fake-installations-token');
  }

  // The controller is not closed: a close with no listener never completes under fake time.
  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

int _apps = 0;

/// A Remote Config instance on [installations] over [server], on the fake clock [now].
FirebaseRemoteConfig _direct(
  FirebaseApp app,
  FirebaseInstallations installations,
  RealtimeServer server,
  DateTime Function() now,
) => FirebaseRemoteConfig(
  app,
  installations: installations,
  languageCode: 'en',
  httpClient: server.client,
  serverOrigin: rcServerOrigin,
  realtimeOrigin: rcRealtimeOrigin,
  clock: now,
  random: () => 0.5,
);

void main() {
  group('5.9.2 / A25 auto-fetch with NO_CHANGE answers', () {
    test(
      'A25 v5 known; announcements 6, 7 and 8; three NO_CHANGE answers (attempt 1 with '
      'If-None-Match, attempts 2 and 3 without): one 3-attempt chain ending update-not-fetched, then '
      'the next chain only after the 60 s cool-down',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          final UpdateLog log = h.listen();
          h.server.fetchAnswer = (FetchCall call) => _taggedTemplate(5, '"e5"');
          unawaited(h.remoteConfig.fetch(minimumFetchInterval: _zero));
          async.flushMicrotasks();
          expect(h.remoteConfig.info.fetchedTemplateVersion, 5);

          h.server.fetchAnswer = (FetchCall call) => _noChange();
          h.elapseTo(s(1));
          h.server.last.send('{"latestTemplateVersionNumber": "6"}');
          h.elapseTo(s(2));
          h.server.last.send('{"latestTemplateVersionNumber": "7"}');
          h.elapseTo(s(3.5));
          h.server.last.send('{"latestTemplateVersionNumber": "8"}');
          h.elapseTo(s(10));

          expect(_realtimeTypes(h.server), <String>[
            'REALTIME/1',
            'REALTIME/2',
            'REALTIME/3',
          ]);
          expect(_realtimeTimes(h.server), <Duration>[s(2.5), s(4), s(5.5)]);
          expect(
            <String?>[
              for (final FetchCall call in _realtimeCalls(h.server))
                _ifNoneMatch(call),
            ],
            <String?>['"e5"', null, null],
          );
          expect(log.codes, <String>['update-not-fetched']);
          expect(h.remoteConfig.info.fetchedTemplateVersion, 5);

          // The chain ended stale at 5.5 s: an announcement at 10 s waits for the cool-down (65.5 s),
          // then the deferred chain's first attempt follows the 1.5 s wait.
          h.server.last.send('{"latestTemplateVersionNumber": "8"}');
          h.elapseTo(s(66.999));
          expect(_realtimeTimes(h.server), hasLength(3));
          h.elapseTo(s(67));
          expect(_realtimeTimes(h.server), hasLength(4));
          expect(_realtimeTypes(h.server).last, 'REALTIME/1');
          expect(
            _realtimeTimes(h.server)[3] - _realtimeTimes(h.server)[2],
            greaterThanOrEqualTo(s(60)),
          );

          h.elapseTo(s(200));
          expect(_realtimeTimes(h.server), <Duration>[
            s(2.5),
            s(4),
            s(5.5),
            s(67),
            s(68.5),
            s(70),
          ]);
          expect(log.codes, <String>[
            'update-not-fetched',
            'update-not-fetched',
          ]);
          h.dispose();
        });
      },
    );

    test(
      'A25 known v5, announcement 6: attempt 1 carries If-None-Match and gets NO_CHANGE; attempt 2 '
      'has none and its UPDATE v6 ends the chain up to date',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          final UpdateLog log = h.listen();
          h.server.fetchAnswer = (FetchCall call) => _taggedTemplate(5, '"e5"');
          unawaited(h.remoteConfig.fetch(minimumFetchInterval: _zero));
          async.flushMicrotasks();

          h.server.fetchAnswer = (FetchCall call) => _ifNoneMatch(call) == null
              ? _taggedTemplate(6, '"e6"')
              : _noChange();
          h.elapseTo(s(1));
          h.server.last.send('{"latestTemplateVersionNumber": "6"}');
          h.elapseTo(s(100));

          final List<FetchCall> calls = _realtimeCalls(h.server);
          expect(
            <String?>[for (final FetchCall call in calls) call.fetchType],
            <String>['REALTIME/1', 'REALTIME/2'],
          );
          expect(_ifNoneMatch(calls[0]), '"e5"');
          expect(_ifNoneMatch(calls[1]), isNull);
          expect(h.remoteConfig.info.fetchedTemplateVersion, 6);
          expect(log.errors, isEmpty);
          expect(log.updates, hasLength(1));
          h.dispose();
        });
      },
    );

    test(
      'A26 a BASE fetch with the ETag in flight when attempt 2 starts: two requests, the second '
      'without If-None-Match',
      () {
        fakeAsync((FakeAsync async) {
          DateTime now() => rcEpoch.add(async.elapsed);
          final RealtimeServer server = RealtimeServer(now);
          final FirebaseApp app = FirebaseApp.withOptions(
            rcOptions,
            name: 'rc-r4-${_apps++}',
          );
          final _HeldInstallations installations = _HeldInstallations(app);
          final FirebaseRemoteConfig remoteConfig = _direct(
            app,
            installations,
            server,
            now,
          );
          async.settle(remoteConfig.ensureInitialized());
          final UpdateLog log = UpdateLog()
            ..listen(remoteConfig.onConfigUpdated);
          async.elapse(Duration.zero);
          expect(server.connections, hasLength(1));

          server.fetchAnswer = (FetchCall call) => _taggedTemplate(5, '"e5"');
          async.settle(remoteConfig.fetch(minimumFetchInterval: _zero));
          expect(remoteConfig.info.fetchedTemplateVersion, 5);

          // Attempt 1 at 2.5 s: NO_CHANGE.
          server.fetchAnswer = (FetchCall call) => _noChange();
          async.elapse(s(1));
          server.last.send('{"latestTemplateVersionNumber": "6"}');
          async.elapse(s(2));
          expect(server.fetches, hasLength(2));

          // At 3 s the app's own fetch waits for Installations; attempt 2 (4 s) must not join it.
          installations.hold();
          final Future<FetchResult> base = remoteConfig.fetch(
            minimumFetchInterval: _zero,
          );
          async.elapse(s(2));
          expect(server.fetches, hasLength(2));

          server.fetchAnswer = (FetchCall call) => _ifNoneMatch(call) == null
              ? _taggedTemplate(6, '"e6"')
              : _noChange();
          installations.release();
          expect(async.settle(base), FetchResult.unchanged);
          async.elapse(s(1));

          expect(server.fetches, hasLength(4));
          final FetchCall shared = server.fetches[2];
          final FetchCall own = server.fetches[3];
          expect(shared.fetchType, 'BASE/1');
          expect(_ifNoneMatch(shared), '"e5"');
          expect(own.fetchType, 'REALTIME/2');
          expect(_ifNoneMatch(own), isNull);
          expect(remoteConfig.info.fetchedTemplateVersion, 6);
          expect(log.errors, isEmpty);

          log.cancel();
          unawaited(remoteConfig.close());
          unawaited(app.delete());
          async.flushMicrotasks();
        });
      },
    );

    test(
      'A25 NO_CHANGE once v6 is known ends the chain for 6 with no error and no cool-down',
      () {
        fakeAsync((FakeAsync async) {
          final RcHarness h = RcHarness(async);
          final UpdateLog log = h.listen();
          h.server.fetchAnswer = (FetchCall call) =>
              templateResponse(version: 5);
          unawaited(h.remoteConfig.fetch(minimumFetchInterval: _zero));
          async.flushMicrotasks();

          h.server.fetchAnswer = (FetchCall call) => _noChange();
          h.elapseTo(s(1));
          h.server.last.send('{"latestTemplateVersionNumber": "6"}');
          h.elapseTo(s(3));
          expect(_realtimeTimes(h.server), <Duration>[s(2.5)]);

          // The app's own fetch gets v6 between the attempts; the second attempt is NO_CHANGE again.
          h.server.fetchAnswer = (FetchCall call) =>
              templateResponse(version: 6);
          unawaited(h.remoteConfig.fetch(minimumFetchInterval: _zero));
          async.flushMicrotasks();
          expect(h.remoteConfig.info.fetchedTemplateVersion, 6);
          h.server.fetchAnswer = (FetchCall call) => _noChange();
          h.elapseTo(s(5));
          expect(_realtimeTypes(h.server), <String>[
            'REALTIME/1',
            'REALTIME/2',
          ]);
          expect(log.errors, isEmpty);

          // No cool-down: version 7 at 5 s starts a chain at once (its attempt at 6.5 s).
          h.server.last.send('{"latestTemplateVersionNumber": "7"}');
          h.elapseTo(s(6.499));
          expect(_realtimeTimes(h.server), hasLength(2));
          h.elapseTo(s(6.5));
          expect(_realtimeTimes(h.server), <Duration>[s(2.5), s(4), s(6.5)]);
          expect(_realtimeTypes(h.server).last, 'REALTIME/1');
          expect(log.errors, isEmpty);
          h.dispose();
        });
      },
    );
  });

  group('5.6 / A28 language code', () {
    for (final String given in <String>['', '   ']) {
      fakeTest(
        'A28 languageCode ${jsonEncode(given)} sends "language_code": "en"',
        (FakeAsync async, Harness h) {
          final RcEnv env = h.env(languageCode: given);
          env.backend.enqueue(
            FakeRoute.fetch,
            FakeAnswer.fetch(entries: <String, String>{'a': '1'}),
          );
          expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);
          expect(
            env.backend
                .requestsTo(FakeRoute.fetch)
                .single
                .json['language_code'],
            'en',
          );
        },
      );
    }
  });

  group('5.5 / A26 fetch requests', () {
    test(
      'A8 / A26 a fetch waiting for Installations is shared after setCustomSignals; the one request '
      'carries the new signals',
      () {
        fakeAsync((FakeAsync async) {
          DateTime now() => rcEpoch.add(async.elapsed);
          final RealtimeServer server = RealtimeServer(now);
          final FirebaseApp app = FirebaseApp.withOptions(
            rcOptions,
            name: 'rc-r4-${_apps++}',
          );
          final _HeldInstallations installations = _HeldInstallations(app);
          final FirebaseRemoteConfig remoteConfig = _direct(
            app,
            installations,
            server,
            now,
          );
          async.settle(remoteConfig.ensureInitialized());

          installations.hold();
          final Future<FetchResult> first = remoteConfig.fetch();
          async.flushMicrotasks();
          expect(installations.calls, 1);

          async.settle(
            remoteConfig.setCustomSignals(<String, Object?>{'tier': 'gold'}),
          );
          final Future<FetchResult> second = remoteConfig.fetch();
          async.flushMicrotasks();
          expect(server.fetches, isEmpty);

          installations.release();
          expect(async.settle(first), FetchResult.updated);
          expect(async.settle(second), FetchResult.updated);
          expect(server.fetches, hasLength(1));
          expect(installations.calls, 1);
          expect(
            server.fetches.single.body['custom_signals'],
            <String, Object?>{'tier': 'gold'},
          );

          unawaited(remoteConfig.close());
          unawaited(app.delete());
          async.flushMicrotasks();
        });
      },
    );

    fakeTest(
      'A26 If-None-Match: a fetched record without an ETag and an active record with one send the '
      'active ETag',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        final String fid = h.settle(env.installations.getId());
        final DateTime last = h.now().subtract(const Duration(hours: 1));
        _seed(h, env, 'meta', _metaText(last, fid: fid));
        _seed(h, env, 'fetched', _recordText(version: 2, fetchTime: last));
        _seed(
          h,
          env,
          'active',
          _recordText(
            version: 1,
            fetchTime: last.subtract(const Duration(hours: 1)),
            etag: '"etag-active"',
          ),
        );
        final FirebaseRemoteConfig remoteConfig = env.newRemoteConfig();
        h.settle(remoteConfig.ensureInitialized());

        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(state: 'NO_CHANGE'),
        );
        expect(
          h.settle(remoteConfig.fetch(minimumFetchInterval: _zero)),
          FetchResult.unchanged,
        );
        expect(
          env.backend
              .requestsTo(FakeRoute.fetch)
              .single
              .headers['if-none-match'],
          '"etag-active"',
        );
      },
    );
  });

  group('5.5 / A26 EMPTY_CONFIG and NO_TEMPLATE', () {
    fakeTest(
      'A26 EMPTY_CONFIG with templateVersion "4" stores v4 and its ETag; the next fetch sends it',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(
            state: 'EMPTY_CONFIG',
            templateVersion: '4',
            etag: '"e4"',
          ),
        );
        expect(h.settle(env.remoteConfig.fetch()), FetchResult.updated);
        expect(env.remoteConfig.info.fetchedTemplateVersion, 4);
        final Map<String, Object?> stored = h.settle(
          env.readRecord('fetched'),
        )!;
        expect(stored['templateVersion'], 4);
        expect(stored['etag'], '"e4"');
        expect(stored['entries'], isEmpty);

        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(state: 'NO_CHANGE'),
        );
        expect(
          h.settle(env.remoteConfig.fetch(minimumFetchInterval: _zero)),
          FetchResult.unchanged,
        );
        expect(
          env.backend.requestsTo(FakeRoute.fetch).last.headers['if-none-match'],
          '"e4"',
        );
      },
    );

    for (final String state in <String>['EMPTY_CONFIG', 'NO_TEMPLATE']) {
      fakeTest(
        'A14 / A26 a versionless $state replaces an active v7 on activate',
        (FakeAsync async, Harness h) {
          final RcEnv env = h.env();
          _seed(
            h,
            env,
            'active',
            _recordText(
              version: 7,
              fetchTime: h.now().subtract(const Duration(hours: 1)),
            ),
          );
          final FirebaseRemoteConfig remoteConfig = env.newRemoteConfig(
            defaults: const <String, Object>{'a': 'default'},
          );
          h.settle(remoteConfig.ensureInitialized());
          expect(remoteConfig.getString('a'), 'stored');

          env.backend.enqueue(FakeRoute.fetch, FakeAnswer.fetch(state: state));
          expect(
            h.settle(remoteConfig.fetch(minimumFetchInterval: _zero)),
            FetchResult.updated,
          );
          expect(h.settle(remoteConfig.activate()), isTrue);
          expect(remoteConfig.info.activeTemplateVersion, isNull);
          expect(remoteConfig.getString('a'), 'default');
          expect(
            h.settle(env.readRecord('active'))!.containsKey('templateVersion'),
            isFalse,
          );
        },
      );
    }
  });

  group('5.5 / A35 activate', () {
    /// Seeds an active and a fetched record, opens a new instance and returns it.
    FirebaseRemoteConfig open(
      Harness h,
      RcEnv env, {
      required String active,
      required String fetched,
    }) {
      _seed(h, env, 'active', active);
      _seed(h, env, 'fetched', fetched);
      final FirebaseRemoteConfig remoteConfig = env.newRemoteConfig();
      h.settle(remoteConfig.ensureInitialized());
      return remoteConfig;
    }

    fakeTest(
      'A35 an active v9 with a future fetch time and a fetched v8: true, v8 is active',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        final FirebaseRemoteConfig remoteConfig = open(
          h,
          env,
          active: _recordText(
            version: 9,
            fetchTime: h.now().add(const Duration(days: 1)),
            entries: const <String, String>{'a': 'nine'},
          ),
          fetched: _recordText(
            version: 8,
            fetchTime: h.now().subtract(const Duration(hours: 1)),
            entries: const <String, String>{'a': 'eight'},
          ),
        );
        expect(h.settle(remoteConfig.activate()), isTrue);
        expect(remoteConfig.info.activeTemplateVersion, 8);
        expect(remoteConfig.getString('a'), 'eight');
        expect(h.settle(env.readRecord('active'))!['templateVersion'], 8);
      },
    );

    for (final (int hours, bool activates) in <(int, bool)>[
      (25, true),
      (23, false),
    ]) {
      fakeTest(
        'A35 an active v9 fetched $hours h before a fetched v8: activate returns $activates',
        (FakeAsync async, Harness h) {
          final RcEnv env = h.env();
          final DateTime fetchedAt = h.now().subtract(const Duration(hours: 1));
          final String activeText = _recordText(
            version: 9,
            fetchTime: fetchedAt.subtract(Duration(hours: hours)),
            entries: const <String, String>{'a': 'nine'},
          );
          final FirebaseRemoteConfig remoteConfig = open(
            h,
            env,
            active: activeText,
            fetched: _recordText(
              version: 8,
              fetchTime: fetchedAt,
              entries: const <String, String>{'a': 'eight'},
            ),
          );
          expect(h.settle(remoteConfig.activate()), activates);
          expect(remoteConfig.info.activeTemplateVersion, activates ? 8 : 9);
          expect(remoteConfig.getString('a'), activates ? 'eight' : 'nine');
          if (!activates) {
            expect(
              h.settle(env.store.read(env.recordKey('active'))),
              activeText,
            );
          }
        },
      );
    }

    fakeTest(
      'A35 the same record in both slots with a future fetch time: false',
      (FakeAsync async, Harness h) {
        final RcEnv env = h.env();
        final String text = _recordText(
          version: 9,
          fetchTime: h.now().add(const Duration(days: 1)),
        );
        final FirebaseRemoteConfig remoteConfig = open(
          h,
          env,
          active: text,
          fetched: text,
        );
        expect(h.settle(remoteConfig.activate()), isFalse);
        expect(remoteConfig.info.activeTemplateVersion, 9);
        async.elapse(const Duration(minutes: 5));
        expect(h.settle(remoteConfig.activate()), isFalse);
      },
    );

    fakeTest(
      'A21 / A27 the store holds A (v5, future fetch time) and memory holds B (no version, its write '
      'failed): activate makes B active',
      (FakeAsync async, Harness h) {
        final ScriptedStore store = ScriptedStore();
        final RcEnv env = h.env(store: store);
        final String fetchedKey = env.recordKey('fetched');
        h.settle(
          store.inner.write(
            fetchedKey,
            _recordText(
              version: 5,
              fetchTime: h.now().add(const Duration(days: 1)),
              entries: const <String, String>{'a': 'five'},
            ),
          ),
        );
        final FirebaseRemoteConfig remoteConfig = env.newRemoteConfig();
        h.settle(remoteConfig.ensureInitialized());
        expect(remoteConfig.info.fetchedTemplateVersion, 5);

        store.before = (StoreOp op, String key) {
          if (key == fetchedKey && op != StoreOp.read) {
            throw StateError('fake write failure');
          }
        };
        env.backend.enqueue(
          FakeRoute.fetch,
          FakeAnswer.fetch(entries: <String, String>{'a': 'b'}),
        );
        expect(
          h.settle(remoteConfig.fetch(minimumFetchInterval: _zero)),
          FetchResult.updated,
        );
        expect(remoteConfig.info.fetchedTemplateVersion, isNull);

        // A21: a stored record with a fetch time in the future is impossible, so the memory record wins.
        expect(h.settle(remoteConfig.activate()), isTrue);
        expect(remoteConfig.info.activeTemplateVersion, isNull);
        expect(remoteConfig.getString('a'), 'b');
      },
    );
  });

  group('5.9.5 / A35 close during an ID change', () {
    test(
      'A35 an ID change waiting for the load when close() runs writes nothing: meta is unchanged',
      () {
        fakeAsync((FakeAsync async) {
          DateTime now() => rcEpoch.add(async.elapsed);
          final RealtimeServer server = RealtimeServer(now);
          final FirebaseApp app = FirebaseApp.withOptions(
            rcOptions,
            name: 'rc-r4-${_apps++}',
          );
          final ScriptedStore store = ScriptedStore();
          final _HeldInstallations installations = _HeldInstallations(
            app,
            store: store,
          );
          final String metaKey = 'remote_config/${app.persistenceKey}/meta';
          final String metaText = _metaText(
            now().subtract(const Duration(hours: 1)),
            fid: rcFirstFid,
          );
          async.settle(store.inner.write(metaKey, metaText));

          final Completer<void> loadGate = Completer<void>();
          bool closed = false;
          final List<String> afterClose = <String>[];
          store.before = (StoreOp op, String key) {
            if (closed && op != StoreOp.read) {
              afterClose.add('${op.name} $key');
            }
            if (op == StoreOp.read && !loadGate.isCompleted) {
              return loadGate.future;
            }
            return Future<void>.value();
          };

          final FirebaseRemoteConfig remoteConfig = _direct(
            app,
            installations,
            server,
            now,
          );
          async.flushMicrotasks();
          expect(remoteConfig.isInitialized, isFalse);

          installations.emitId(rcSecondFid);
          async.flushMicrotasks();

          closed = true;
          final Future<void> closing = remoteConfig.close();
          async.flushMicrotasks();
          loadGate.complete();
          async.settle(closing);
          async.elapse(const Duration(seconds: 1));

          expect(async.settle(store.inner.read(metaKey)), metaText);
          expect(afterClose, isEmpty);

          unawaited(app.delete());
          async.flushMicrotasks();
        });
      },
    );
  });
}
