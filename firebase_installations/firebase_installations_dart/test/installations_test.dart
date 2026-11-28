@TestOn('vm')
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

/// The jitter every instance of this file gets: backoff waits are `2^n + 0.25` seconds.
const double _jitter = 0.25;

/// A token lifetime that needs a generate at once (less than the hour of margin).
const String _shortLife = '1800s';

/// One test's world: a fake server, a fake clock, an app, a store and an instance over them.
final class _Env {
  _Env(this.async, {KeyValueStore? store})
    : clock = FisClock(async),
      app = newFisApp(),
      store = store ?? MemoryKeyValueStore() {
    installations = instance();
  }

  final FakeAsync async;
  final FakeFis fis = FakeFis();
  final FisClock clock;
  final FirebaseApp app;
  final KeyValueStore store;
  final List<(InstallationsLogLevel, String)> logs =
      <(InstallationsLogLevel, String)>[];
  late final FirebaseInstallations installations;

  /// Another instance over the same app, store, server and clock.
  FirebaseInstallations instance() => newFisInstance(
    fis: fis,
    app: app,
    store: store,
    clock: clock,
    random: _jitter,
    logger: (InstallationsLogLevel level, String message) =>
        logs.add((level, message)),
  );

  Outcome<String> getId() => Outcome<String>(installations.getId());

  Outcome<String> getToken({bool forceRefresh = false}) =>
      Outcome<String>(installations.getToken(forceRefresh: forceRefresh));

  /// Registers the installation (the create answer queued by the caller, if any) and returns its FID.
  String register() {
    final Outcome<({String id, String token})> pair =
        Outcome<({String id, String token})>(installations.getIdAndToken());
    async.flushMicrotasks();
    return pair.value.id;
  }

  void finish() {
    installations.close();
    app.delete();
    async.flushMicrotasks();
  }
}

void _fake(void Function(_Env env) body, {KeyValueStore? store}) {
  fakeAsync((FakeAsync async) {
    final _Env env = _Env(async, store: store);
    body(env);
    env.finish();
  });
}

/// A store whose calls never complete.
final class _HangingStore implements KeyValueStore {
  @override
  Future<String?> read(String key) => Completer<String?>().future;

  @override
  Future<void> write(String key, String? value) => Completer<void>().future;

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) => Completer<String?>().future;

  @override
  Stream<String> get changes => const Stream<String>.empty();

  @override
  Future<void> close() async {}
}

/// A store that forwards to a [MemoryKeyValueStore] but is not one.
final class _ForwardingStore implements KeyValueStore {
  // Late: the store is built before fakeAsync starts, and a MemoryKeyValueStore made there would chain its
  // futures in the root zone, which fake time never runs.
  late final MemoryKeyValueStore _inner = MemoryKeyValueStore();

  @override
  Future<String?> read(String key) => _inner.read(key);

  @override
  Future<void> write(String key, String? value) => _inner.write(key, value);

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) => _inner.update(key, transform);

  @override
  Stream<String> get changes => _inner.changes;

  @override
  Future<void> close() => _inner.close();
}

/// The backoff after the n-th consecutive recoverable failure (429, 5xx, 3xx, or 401, 404 or 409 on
/// create): `min(2^n + random, 1800)` seconds.
Duration _backoff(int n) {
  final double seconds = math.min(math.pow(2, n) + _jitter, 1800.0);
  return Duration(milliseconds: (seconds * 1000).round());
}

void main() {
  group('5.3 getId', () {
    test('5.3 offline getId returns at once; registration runs in the '
        'background', () {
      _fake((_Env env) {
        env.fis.answerAll(FisRoute.create, FisAnswer.transportError);
        final Outcome<String> id = env.getId();
        env.async.flushMicrotasks();
        expect(id.isDone, isTrue);
        expect(id.value, matches(RegExp(r'^[cdef][A-Za-z0-9_-]{21}$')));
        expect(env.async.elapsed, Duration.zero);
        expect(env.fis.count(FisRoute.create), 1);
        expect(env.fis.requestsTo(FisRoute.create).single.fid, id.value);

        env.async.elapse(const Duration(seconds: 1));
        expect(env.fis.count(FisRoute.create), 2);
        expect(
          env.logs.where(
            ((InstallationsLogLevel, String) log) =>
                log.$1 == InstallationsLogLevel.warning &&
                log.$2.contains('network-error'),
          ),
          hasLength(1),
        );

        final Outcome<String> again = env.getId();
        env.async.flushMicrotasks();
        expect(again.value, id.value);
      });
    });
  });

  group('5.3 token validity', () {
    test('5.3 token: valid while at least 1 h of life is left '
        '(1 h - 1 ms, 1 h, 1 h + 1 ms)', () {
      _fake((_Env env) {
        env.fis.answer(FisRoute.create, FisAnswer.create(expiresIn: '7200s'));
        final Outcome<String> first = env.getToken();
        env.async.flushMicrotasks();
        final String token = first.value;
        expect(env.fis.count(FisRoute.generate), 0);

        env.async.elapse(
          const Duration(hours: 1) - const Duration(milliseconds: 1),
        );
        final Outcome<String> before = env.getToken();
        env.async.flushMicrotasks();
        expect(before.value, token);
        expect(env.fis.count(FisRoute.generate), 0);

        env.async.elapse(const Duration(milliseconds: 1));
        final Outcome<String> at = env.getToken();
        env.async.flushMicrotasks();
        expect(at.value, token);
        expect(env.fis.count(FisRoute.generate), 0);

        env.async.elapse(const Duration(milliseconds: 1));
        final Outcome<String> after = env.getToken();
        env.async.flushMicrotasks();
        expect(env.fis.count(FisRoute.generate), 1);
        expect(after.value, isNot(token));
      });
    });

    test('5.3 token: a creation time in the future refreshes it', () {
      _fake((_Env env) {
        final Outcome<String> first = env.getToken();
        env.async.flushMicrotasks();
        final String token = first.value;
        expect(env.fis.count(FisRoute.generate), 0);

        env.clock.offset = const Duration(seconds: -1);
        final Outcome<String> second = env.getToken();
        env.async.flushMicrotasks();
        expect(env.fis.count(FisRoute.generate), 1);
        expect(second.value, isNot(token));
      });
    });

    test('5.3 token: a forced refresh during a normal one sends a second '
        'request', () {
      _fake((_Env env) {
        final Completer<void> gate = Completer<void>();
        env.fis.answer(
          FisRoute.create,
          FisAnswer.create(expiresIn: _shortLife),
        );
        env.fis.answer(FisRoute.generate, FisAnswer.token(gate: gate.future));
        final Outcome<String> normal = env.getToken();
        env.async.flushMicrotasks();
        expect(env.fis.count(FisRoute.generate), 1);
        expect(normal.isDone, isFalse);

        final Outcome<String> forced = env.getToken(forceRefresh: true);
        env.async.flushMicrotasks();
        expect(env.fis.count(FisRoute.generate), 2);
        expect(forced.isDone, isTrue);

        gate.complete();
        env.async.flushMicrotasks();
        expect(normal.value, isNotEmpty);
        expect(forced.value, isNotEmpty);
      });
    });

    test('5.3 sharing: 100 concurrent getToken calls send one create and one '
        'generate', () {
      _fake((_Env env) {
        env.fis.answer(
          FisRoute.create,
          FisAnswer.create(expiresIn: _shortLife),
        );
        final List<Outcome<String>> tokens = <Outcome<String>>[
          for (int i = 0; i < 100; i++) env.getToken(),
        ];
        env.async.flushMicrotasks();
        expect(env.fis.count(FisRoute.create), 1);
        expect(env.fis.count(FisRoute.generate), 1);
        final Set<String> values = <String>{
          for (final Outcome<String> token in tokens) token.value,
        };
        expect(values, hasLength(1));
      });
    });
  });

  group('5.3 register', () {
    test(
      '5.3 register (A4): 409 discards the FID and feeds the recoverable '
      'backoff; the next getId gives a new one, registered after the window',
      () {
        _fake((_Env env) {
          env.fis.answer(FisRoute.create, FisAnswer.status(409));
          final Outcome<String> first = env.getId();
          env.async.flushMicrotasks();
          expect(env.fis.requestsTo(FisRoute.create).single.fid, first.value);
          expect(
            env.logs.where(
              ((InstallationsLogLevel, String) log) =>
                  log.$1 == InstallationsLogLevel.warning &&
                  log.$2.contains('409'),
            ),
            hasLength(1),
          );

          final Outcome<String> second = env.getId();
          env.async.flushMicrotasks();
          expect(second.value, isNot(first.value));
          expect(
            env.fis.count(FisRoute.create),
            1,
            reason:
                'the window of the first recoverable failure (2 + 0.25 s) runs',
          );

          env.async.elapse(_backoff(1));
          final Outcome<String> third = env.getId();
          env.async.flushMicrotasks();
          expect(third.value, second.value);
          expect(env.fis.count(FisRoute.create), 2);
          expect(env.fis.requestsTo(FisRoute.create).last.fid, second.value);
        });
      },
    );

    test('5.3 register (A4): a getToken caller whose registration gets 409 '
        'restarts once with a new FID despite the window', () {
      _fake((_Env env) {
        env.fis.answer(FisRoute.create, FisAnswer.status(409));
        final Outcome<({String id, String token})> pair =
            Outcome<({String id, String token})>(
              env.installations.getIdAndToken(),
            );
        env.async.flushMicrotasks();
        final List<FisRequest> creates = env.fis.requestsTo(FisRoute.create);
        expect(creates, hasLength(2));
        expect(creates[1].fid, isNot(creates[0].fid));
        expect(pair.value.id, creates[1].fid);
        expect(
          env.logs.where(
            ((InstallationsLogLevel, String) log) =>
                log.$1 == InstallationsLogLevel.warning &&
                log.$2.contains('409'),
          ),
          hasLength(1),
        );
      });
    });

    test('5.3 register (A4): a second 409 in the same call is '
        'invalid-response', () {
      _fake((_Env env) {
        env.fis.answerAll(FisRoute.create, () => FisAnswer.status(409));
        final Outcome<String> token = env.getToken();
        env.async.flushMicrotasks();
        expect(
          token.error,
          isFisException('invalid-response', httpStatus: 409),
        );
        expect(env.fis.count(FisRoute.create), 2);
      });
    });

    test(
      '5.3 register (A4): a 3xx on create feeds the recoverable backoff',
      () {
        _fake((_Env env) {
          env.fis.answer(FisRoute.create, FisAnswer.status(302));
          final DateTime start = env.clock();
          final Outcome<String> first = env.getToken();
          env.async.flushMicrotasks();
          expect(
            first.error,
            isFisException('invalid-response', httpStatus: 302),
          );

          final Outcome<String> blocked = env.getToken();
          env.async.flushMicrotasks();
          expect(blocked.error, isFisException('too-many-requests'));
          expect(
            (blocked.error! as FirebaseInstallationsException).retryAfter,
            start.add(_backoff(1)),
          );
          expect(env.fis.count(FisRoute.create), 1);

          env.async.elapse(_backoff(1));
          final Outcome<String> later = env.getToken();
          env.async.flushMicrotasks();
          expect(later.value, isNotEmpty);
          expect(env.fis.count(FisRoute.create), 2);
        });
      },
    );
  });

  group('5.3 401/404 recovery', () {
    test('5.3 recovery: 401 on generate creates a new FID and generates once '
        'more', () {
      _fake((_Env env) {
        env.fis.answer(
          FisRoute.create,
          FisAnswer.create(expiresIn: _shortLife),
        );
        env.fis.answer(FisRoute.generate, FisAnswer.status(401));
        final Outcome<({String id, String token})> pair =
            Outcome<({String id, String token})>(
              env.installations.getIdAndToken(),
            );
        env.async.flushMicrotasks();
        final List<FisRoute?> routes = <FisRoute?>[
          for (final FisRequest request in env.fis.requests) request.route,
        ];
        expect(routes, <FisRoute>[
          FisRoute.create,
          FisRoute.generate,
          FisRoute.create,
          FisRoute.generate,
        ]);
        final List<FisRequest> creates = env.fis.requestsTo(FisRoute.create);
        final List<FisRequest> generates = env.fis.requestsTo(
          FisRoute.generate,
        );
        expect(creates[1].fid, isNot(creates[0].fid));
        expect(generates[0].fid, creates[0].fid);
        expect(generates[1].fid, creates[1].fid);
        expect(pair.value.id, creates[1].fid);

        final Outcome<String> id = env.getId();
        env.async.flushMicrotasks();
        expect(id.value, creates[1].fid);
      });
    });

    test('5.3 recovery: a second 404 throws installation-not-found', () {
      _fake((_Env env) {
        env.fis.answer(
          FisRoute.create,
          FisAnswer.create(expiresIn: _shortLife),
        );
        env.fis.answerAll(FisRoute.generate, () => FisAnswer.status(404));
        final Outcome<String> token = env.getToken();
        env.async.flushMicrotasks();
        expect(
          token.error,
          isFisException('installation-not-found', httpStatus: 404),
        );
        expect(env.fis.count(FisRoute.create), 2);
        expect(env.fis.count(FisRoute.generate), 2);
      });
    });
  });

  group('5.3 retries and backoff', () {
    test('5.3 backoff: 403 blocks create for 24 h; a new instance retries', () {
      _fake((_Env env) {
        env.fis.answer(FisRoute.create, FisAnswer.status(403));
        final DateTime start = env.clock();
        final Outcome<String> first = env.getToken();
        env.async.flushMicrotasks();
        expect(first.error, isFisException('bad-config', httpStatus: 403));
        expect(
          (first.error! as FirebaseInstallationsException).retryAfter,
          start.add(const Duration(hours: 24)),
        );
        expect(env.fis.count(FisRoute.create), 1);

        env.async.elapse(
          const Duration(hours: 24) - const Duration(milliseconds: 1),
        );
        final Outcome<String> blocked = env.getToken();
        env.async.flushMicrotasks();
        expect(blocked.error, isFisException('bad-config', httpStatus: 403));
        expect(
          (blocked.error! as FirebaseInstallationsException).retryAfter,
          start.add(const Duration(hours: 24)),
        );
        expect(env.fis.count(FisRoute.create), 1);

        final FirebaseInstallations other = env.instance();
        final Outcome<String> retried = Outcome<String>(other.getToken());
        env.async.flushMicrotasks();
        expect(env.fis.count(FisRoute.create), 2);
        expect(retried.value, isNotEmpty);
        other.close();
      });
    });

    for (final int status in <int>[401, 404]) {
      test('5.3 backoff (A4): create $status is bad-config with a recoverable '
          'window, not the 24 h block', () {
        _fake((_Env env) {
          env.fis.answer(FisRoute.create, FisAnswer.status(status));
          final DateTime start = env.clock();
          final Outcome<String> first = env.getToken();
          env.async.flushMicrotasks();
          expect(first.error, isFisException('bad-config', httpStatus: status));
          expect(
            (first.error! as FirebaseInstallationsException).retryAfter,
            start.add(_backoff(1)),
          );

          final Outcome<String> blocked = env.getToken();
          env.async.flushMicrotasks();
          expect(
            blocked.error,
            isFisException('bad-config', httpStatus: status),
          );
          expect(env.fis.count(FisRoute.create), 1);

          env.async.elapse(_backoff(1));
          final Outcome<String> later = env.getToken();
          env.async.flushMicrotasks();
          expect(later.value, isNotEmpty);
          expect(env.fis.count(FisRoute.create), 2);
        });
      });
    }

    test('5.3 backoff: 429 waits min(2^n + random, 1800) s for the n-th '
        'failure; a success resets it', () {
      _fake((_Env env) {
        env.fis.answerAll(FisRoute.create, () => FisAnswer.status(429));
        for (int n = 1; n <= 12; n++) {
          final DateTime now = env.clock();
          final Outcome<String> failed = env.getToken();
          env.async.flushMicrotasks();
          expect(env.fis.count(FisRoute.create), n);
          expect(
            failed.error,
            isFisException('too-many-requests', httpStatus: 429),
          );
          final DateTime? retryAfter =
              (failed.error! as FirebaseInstallationsException).retryAfter;
          expect(retryAfter, now.add(_backoff(n)), reason: 'failure $n');

          final Outcome<String> blocked = env.getToken();
          env.async.flushMicrotasks();
          expect(blocked.error, isFisException('too-many-requests'));
          expect(
            (blocked.error! as FirebaseInstallationsException).retryAfter,
            retryAfter,
          );
          expect(env.fis.count(FisRoute.create), n);
          env.async.elapse(retryAfter!.difference(env.clock()));
        }

        env.fis.answerAll(FisRoute.create, FisAnswer.create);
        final Outcome<String> success = env.getToken();
        env.async.flushMicrotasks();
        expect(success.value, isNotEmpty);

        env.fis.answer(FisRoute.generate, FisAnswer.status(429));
        final DateTime now = env.clock();
        final Outcome<String> forced = env.getToken(forceRefresh: true);
        env.async.flushMicrotasks();
        expect(forced.error, isFisException('too-many-requests'));
        expect(
          (forced.error! as FirebaseInstallationsException).retryAfter,
          now.add(_backoff(1)),
        );
      });
    });

    test('5.3 backoff: a 5xx after its retry opens the window of the first '
        'failure', () {
      _fake((_Env env) {
        env.fis.answerAll(FisRoute.create, () => FisAnswer.status(503));
        final Outcome<String> failed = env.getToken();
        env.async.flushMicrotasks();
        env.async.elapse(const Duration(seconds: 1));
        expect(failed.error, isFisException('unavailable', httpStatus: 503));
        final DateTime failedAt = env.clock();

        final Outcome<String> blocked = env.getToken();
        env.async.flushMicrotasks();
        expect(blocked.error, isFisException('too-many-requests'));
        expect(
          (blocked.error! as FirebaseInstallationsException).retryAfter,
          failedAt.add(_backoff(1)),
        );
        expect(env.fis.count(FisRoute.create), 2);
      });
    });

    test('5.3 retries: a 5xx is retried once after 1 s', () {
      _fake((_Env env) {
        env.fis.answer(FisRoute.create, FisAnswer.status(503));
        final Outcome<String> token = env.getToken();
        env.async.flushMicrotasks();
        expect(env.fis.count(FisRoute.create), 1);

        env.async.elapse(const Duration(milliseconds: 999));
        expect(env.fis.count(FisRoute.create), 1);
        expect(token.isDone, isFalse);

        env.async.elapse(const Duration(milliseconds: 1));
        expect(env.fis.count(FisRoute.create), 2);
        expect(token.value, isNotEmpty);
        final List<FisRequest> creates = env.fis.requestsTo(FisRoute.create);
        expect(creates[1].fid, creates[0].fid);
      });
    });

    test('5.3 retries: a transport error is retried once after 1 s, then '
        'network-error; it opens no backoff window', () {
      _fake((_Env env) {
        env.fis.answer(FisRoute.create, FisAnswer.transportError(), <FisAnswer>[
          FisAnswer.transportError(),
        ]);
        final Outcome<String> token = env.getToken();
        env.async.flushMicrotasks();
        env.async.elapse(const Duration(seconds: 1));
        expect(env.fis.count(FisRoute.create), 2);
        expect(token.error, isFisException('network-error'));

        final Outcome<String> next = env.getToken();
        env.async.flushMicrotasks();
        expect(env.fis.count(FisRoute.create), 3);
        expect(next.value, isNotEmpty);
      });
    });
  });

  group('5.3 delete', () {
    for (final int status in <int>[200, 401, 404]) {
      test('5.3 delete: $status counts as done and removes the record', () {
        _fake((_Env env) {
          env.fis.answer(
            FisRoute.create,
            FisAnswer.create(refreshToken: 'refresh-delete-$status'),
          );
          final String fid = env.register();
          env.fis.answer(FisRoute.delete, FisAnswer.status(status));
          final Outcome<void> deleted = Outcome<void>(
            env.installations.delete(),
          );
          env.async.flushMicrotasks();
          expect(deleted.isDone, isTrue);
          expect(deleted.error, isNull);
          final FisRequest request = env.fis.requestsTo(FisRoute.delete).single;
          expect(request.method, 'DELETE');
          expect(request.fid, fid);
          expect(request.authorization, 'FIS_v2 refresh-delete-$status');

          final Outcome<String> id = env.getId();
          env.async.flushMicrotasks();
          expect(id.value, isNot(fid));
        });
      });
    }

    test('5.3 delete: 500 (after its retry) fails and keeps the record', () {
      _fake((_Env env) {
        final String fid = env.register();
        env.fis.answerAll(FisRoute.delete, () => FisAnswer.status(500));
        final Outcome<void> deleted = Outcome<void>(env.installations.delete());
        env.async.flushMicrotasks();
        env.async.elapse(const Duration(seconds: 1));
        expect(env.fis.count(FisRoute.delete), 2);
        expect(deleted.error, isFisException('unavailable', httpStatus: 500));

        final Outcome<String> id = env.getId();
        env.async.flushMicrotasks();
        expect(id.value, fid);
      });
    });

    test('5.3 delete: an unregistered installation is removed without a '
        'request', () {
      _fake((_Env env) {
        env.fis.answerAll(FisRoute.create, () => FisAnswer.status(503));
        final Outcome<String> first = env.getId();
        env.async.flushMicrotasks();
        env.async.elapse(const Duration(seconds: 1));
        expect(env.fis.count(FisRoute.create), 2);

        final Outcome<void> deleted = Outcome<void>(env.installations.delete());
        env.async.flushMicrotasks();
        expect(deleted.isDone, isTrue);
        expect(deleted.error, isNull);
        expect(env.fis.count(FisRoute.delete), 0);

        final Outcome<String> second = env.getId();
        env.async.flushMicrotasks();
        expect(second.value, isNot(first.value));
      });
    });

    test('5.3 delete: waits for a registration in flight, then deletes it', () {
      _fake((_Env env) {
        final Completer<void> gate = Completer<void>();
        env.fis.answer(
          FisRoute.create,
          FisAnswer.create(refreshToken: 'refresh-held', gate: gate.future),
        );
        final Outcome<String> id = env.getId();
        env.async.flushMicrotasks();
        expect(env.fis.count(FisRoute.create), 1);

        final Outcome<void> deleted = Outcome<void>(env.installations.delete());
        env.async.flushMicrotasks();
        expect(deleted.isDone, isFalse);
        expect(env.fis.count(FisRoute.delete), 0);

        gate.complete();
        env.async.flushMicrotasks();
        expect(deleted.isDone, isTrue);
        expect(deleted.error, isNull);
        final FisRequest request = env.fis.requestsTo(FisRoute.delete).single;
        expect(request.fid, id.value);
        expect(request.authorization, 'FIS_v2 refresh-held');
      });
    });
  });

  group('5.3 onIdChange', () {
    test('5.3 onIdChange: emits on creation, for a server FID, and for a '
        'replacement', () {
      _fake((_Env env) {
        final List<String> events = <String>[];
        env.installations.onIdChange.listen(events.add);
        const String serverFid = 'fAAAAAAAAAAAAAAAAAAAAA';
        env.fis.answer(FisRoute.create, FisAnswer.create(fid: serverFid));

        final Outcome<String> created = env.getId();
        env.async.flushMicrotasks();
        expect(events, <String>[created.value, serverFid]);
        expect(created.value, isNot(serverFid));

        final Outcome<String> stored = env.getId();
        env.async.flushMicrotasks();
        expect(stored.value, serverFid);

        env.fis.answer(FisRoute.generate, FisAnswer.status(401));
        final Outcome<({String id, String token})> pair =
            Outcome<({String id, String token})>(
              env.installations.getIdAndToken(forceRefresh: true),
            );
        env.async.flushMicrotasks();
        expect(pair.value.id, isNot(serverFid));
        expect(events, <String>[created.value, serverFid, pair.value.id]);
      });
    });
  });

  group('5.3 deadline and lifecycle', () {
    test('5.3 deadline: a call fails with unavailable after 60 s', () {
      _fake((_Env env) {
        final Outcome<String> id = env.getId();
        final Outcome<String> token = env.getToken();
        env.async.elapse(
          const Duration(seconds: 60) - const Duration(milliseconds: 1),
        );
        expect(id.isDone, isFalse);
        expect(token.isDone, isFalse);

        env.async.elapse(const Duration(milliseconds: 1));
        expect(id.error, isFisException('unavailable'));
        expect(token.error, isFisException('unavailable'));
      }, store: _HangingStore());
    });

    test('5.3 close: pending and later calls fail with installations-closed; '
        'onIdChange ends; idempotent; an injected client stays open', () {
      _fake((_Env env) {
        final Completer<void> gate = Completer<void>();
        env.fis.answer(FisRoute.create, FisAnswer.create(gate: gate.future));
        bool ended = false;
        env.installations.onIdChange.listen((_) {}, onDone: () => ended = true);
        final Outcome<String> pending = env.getToken();
        env.async.flushMicrotasks();
        expect(pending.isDone, isFalse);

        final Outcome<void> closed = Outcome<void>(env.installations.close());
        env.async.flushMicrotasks();
        expect(closed.isDone, isTrue);
        expect(pending.error, isFisException('installations-closed'));
        expect(ended, isTrue);

        final Outcome<String> later = env.getId();
        final Outcome<void> laterDelete = Outcome<void>(
          env.installations.delete(),
        );
        final Outcome<void> again = Outcome<void>(env.installations.close());
        env.async.flushMicrotasks();
        expect(later.error, isFisException('installations-closed'));
        expect(laterDelete.error, isFisException('installations-closed'));
        expect(again.error, isNull);
        expect(again.isDone, isTrue);
        expect(env.fis.clientClosed, isFalse);

        gate.complete();
        env.async.flushMicrotasks();
      });
    });

    test('5.3 lifecycle: deleting the app closes the instance', () {
      _fake((_Env env) {
        bool ended = false;
        env.installations.onIdChange.listen((_) {}, onDone: () => ended = true);
        env.app.delete();
        env.async.flushMicrotasks();
        expect(ended, isTrue);

        final Outcome<String> id = env.getId();
        env.async.flushMicrotasks();
        expect(id.error, isFisException('installations-closed'));
        expect(env.fis.requests, isEmpty);
      });
    });
  });

  group('5.11 rule 11 memory-store warning', () {
    bool isMemoryWarning((InstallationsLogLevel, String) log) =>
        log.$1 == InstallationsLogLevel.warning &&
        log.$2.contains('MemoryKeyValueStore');

    test('5.11 rule 11: MemoryKeyValueStore logs one warning, without '
        'values, at the first registration only', () {
      _fake((_Env env) {
        env.fis.answer(
          FisRoute.create,
          FisAnswer.create(
            refreshToken: 'refresh-secret',
            token: 'auth-secret',
          ),
        );
        final String fid = env.register();
        expect(env.logs.where(isMemoryWarning), hasLength(1));
        final String warning = env.logs.firstWhere(isMemoryWarning).$2;
        expect(warning, isNot(contains(fid)));
        expect(warning, isNot(contains('refresh-secret')));
        expect(warning, isNot(contains('auth-secret')));
        expect(warning, isNot(contains(fisApiKey)));

        final Outcome<void> deleted = Outcome<void>(env.installations.delete());
        env.async.flushMicrotasks();
        expect(deleted.error, isNull);
        env.register();
        expect(env.fis.count(FisRoute.create), 2);
        expect(env.logs.where(isMemoryWarning), hasLength(1));
      });
    });

    test('5.11 rule 11: another store logs no memory-store warning', () {
      _fake((_Env env) {
        env.register();
        expect(env.logs.where(isMemoryWarning), isEmpty);
      }, store: _ForwardingStore());
    });
  });
}
