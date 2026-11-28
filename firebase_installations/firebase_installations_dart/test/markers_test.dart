@TestOn('vm')
library;

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:test/test.dart';

import 'support/fis_store_fakes.dart';

final DateTime _base = DateTime.utc(2026, 3, 1, 12);

/// One app, one shared [MemoryKeyValueStore] and a way to make instances over them in fake time.
final class _Rig {
  _Rig(this.async) : app = newFakeApp(), store = MemoryKeyValueStore();

  final FakeAsync async;
  final FirebaseApp app;
  final MemoryKeyValueStore store;
  final List<FirebaseInstallations> _instances = <FirebaseInstallations>[];

  DateTime now() => _base.add(async.elapsed);

  FirebaseInstallations instance(FakeFisServer server, {int seed = 1}) {
    final FirebaseInstallations installations = FirebaseInstallations(
      app,
      store: store,
      httpClient: server.client,
      clock: now,
      random: () => 0,
      randomBytes: countingBytes(seed),
    );
    _instances.add(installations);
    return installations;
  }

  void seed(String json) {
    store.write(recordKey(app), json);
    async.flushMicrotasks();
  }

  String? stored() {
    String? text;
    store.read(recordKey(app)).then((String? value) => text = value);
    async.flushMicrotasks();
    return text;
  }

  void dispose() {
    for (final FirebaseInstallations installations in _instances) {
      installations.close();
    }
    app.delete();
    async.flushMicrotasks();
  }
}

/// The outcome of a future watched in fake time.
final class _Watch<T> {
  _Watch(Future<T> future) {
    future.then(
      (T value) {
        this.value = value;
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    );
  }

  bool done = false;
  T? value;
  Object? error;
}

void main() {
  test('5.3 markers: slow attempt not duplicated across two instances on one '
      'MemoryKeyValueStore', () {
    fakeAsync((FakeAsync async) {
      final _Rig rig = _Rig(async);
      // The first create attempt outlives the 10 s request deadline; the retry answers in 3 s.
      final FakeFisServer serverA = FakeFisServer(
        createDelay: const Duration(seconds: 12),
      );
      final FakeFisServer serverB = FakeFisServer();
      final FirebaseInstallations a = rig.instance(serverA, seed: 1);
      final FirebaseInstallations b = rig.instance(serverB, seed: 9);

      final _Watch<({String id, String token})> fromA =
          _Watch<({String id, String token})>(a.getIdAndToken());
      async.flushMicrotasks();
      expect(serverA.of('create'), hasLength(1));
      final String fid = serverA.of('create').single.fid;
      serverA.createDelay = const Duration(seconds: 3);

      async.elapse(const Duration(seconds: 1));
      final _Watch<({String id, String token})> fromB =
          _Watch<({String id, String token})>(b.getIdAndToken());

      // t = 10.5 s: the first marker is 10.5 s old (stale under a 10 s rule); the second attempt
      // has not started yet.
      async.elapse(const Duration(milliseconds: 9500));
      expect(serverB.requests, isEmpty);
      expect(fromB.done, isFalse);

      // t = 12.5 s: the retry (sent at 11 s, after the 1 s retry delay) re-stamped the marker.
      async.elapse(const Duration(seconds: 2));
      final Map<String, Object?> during =
          decodeRecord(rig.stored()) ?? <String, Object?>{};
      expect(during['status'], 'registering');
      expect(
        during['registrationStartedAt'],
        _base.add(const Duration(seconds: 11)).millisecondsSinceEpoch,
      );
      expect(serverA.of('create'), hasLength(2));
      expect(serverB.requests, isEmpty);

      async.elapse(const Duration(seconds: 3));
      expect(fromA.error, isNull);
      expect(fromB.error, isNull);
      expect(fromA.value, (id: fid, token: 'create-$fid'));
      expect(fromB.value, (id: fid, token: 'create-$fid'));
      expect(serverB.requests, isEmpty, reason: 'B never sent anything');
      expect(serverA.of('create').map((FisRequest r) => r.fid), <String>[
        fid,
        fid,
      ]);
      rig.dispose();
    });
  });

  group('5.3 markers: registration marker', () {
    final String fid = fakeFid(3);

    /// Seeds a registering record whose marker is [offset] from t = 0 and starts getToken.
    ({_Rig rig, FakeFisServer server, _Watch<String> token}) start(
      FakeAsync async,
      Duration offset,
    ) {
      final _Rig rig = _Rig(async);
      final FakeFisServer server = FakeFisServer();
      rig.seed(
        recordJson(
          fid: fid,
          status: 'registering',
          registrationStartedAt: _base.add(offset),
        ),
      );
      final _Watch<String> token = _Watch<String>(
        rig.instance(server).getToken(),
      );
      async.flushMicrotasks();
      return (rig: rig, server: server, token: token);
    }

    test('5.3 a marker 16 s old is stale and taken over at once', () {
      fakeAsync((FakeAsync async) {
        final s = start(async, const Duration(seconds: -16));
        expect(s.server.of('create').map((FisRequest r) => r.fid), <String>[
          fid,
        ]);
        async.elapse(const Duration(milliseconds: 10));
        expect(s.token.value, 'create-$fid');
        s.rig.dispose();
      });
    });

    test('5.3 a marker exactly 15 s old is fresh; taken over once older', () {
      fakeAsync((FakeAsync async) {
        final s = start(async, const Duration(seconds: -15));
        expect(s.server.requests, isEmpty);
        async.elapse(const Duration(milliseconds: 150));
        expect(s.server.of('create').map((FisRequest r) => r.fid), <String>[
          fid,
        ]);
        async.elapse(const Duration(milliseconds: 10));
        expect(s.token.value, 'create-$fid');
        s.rig.dispose();
      });
    });

    test('5.3 a marker 1 s in the future is fresh until 15 s past it', () {
      fakeAsync((FakeAsync async) {
        final s = start(async, const Duration(seconds: 1));
        async.elapse(const Duration(milliseconds: 15900));
        expect(s.server.requests, isEmpty);
        async.elapse(const Duration(milliseconds: 400));
        expect(s.server.of('create').map((FisRequest r) => r.fid), <String>[
          fid,
        ]);
        async.elapse(const Duration(milliseconds: 10));
        expect(s.token.value, 'create-$fid');
        s.rig.dispose();
      });
    });

    test('5.3 a marker more than 1 s in the future is taken over at once', () {
      fakeAsync((FakeAsync async) {
        final s = start(async, const Duration(milliseconds: 1001));
        expect(s.server.of('create').map((FisRequest r) => r.fid), <String>[
          fid,
        ]);
        async.elapse(const Duration(milliseconds: 10));
        expect(s.token.value, 'create-$fid');
        s.rig.dispose();
      });
    });
  });

  group('5.3 markers: token marker', () {
    final String fid = fakeFid(4);

    ({_Rig rig, FakeFisServer server, _Watch<String> token}) start(
      FakeAsync async,
      Duration offset,
    ) {
      final _Rig rig = _Rig(async);
      final FakeFisServer server = FakeFisServer();
      rig.seed(
        recordJson(
          fid: fid,
          status: 'registered',
          refreshToken: 'rt-$fid',
          token: 'expired',
          tokenCreatedAt: _base.subtract(const Duration(hours: 2)),
          tokenExpiresIn: const Duration(hours: 1),
          tokenRequestStartedAt: _base.add(offset),
        ),
      );
      final _Watch<String> token = _Watch<String>(
        rig.instance(server).getToken(),
      );
      async.flushMicrotasks();
      return (rig: rig, server: server, token: token);
    }

    test('5.3 a token marker 16 s old is stale and taken over at once', () {
      fakeAsync((FakeAsync async) {
        final s = start(async, const Duration(seconds: -16));
        expect(s.server.of('generate').map((FisRequest r) => r.fid), <String>[
          fid,
        ]);
        expect(s.server.of('create'), isEmpty);
        async.elapse(const Duration(milliseconds: 10));
        expect(s.token.value, 'gen-$fid-0');
        s.rig.dispose();
      });
    });

    test(
      '5.3 a token marker 5 s old makes a caller wait until it is stale',
      () {
        fakeAsync((FakeAsync async) {
          final s = start(async, const Duration(seconds: -5));
          expect(s.server.requests, isEmpty);
          async.elapse(const Duration(milliseconds: 9900));
          expect(s.server.requests, isEmpty);
          async.elapse(const Duration(milliseconds: 400));
          expect(s.server.of('generate'), hasLength(1));
          async.elapse(const Duration(milliseconds: 10));
          expect(s.token.value, 'gen-$fid-0');
          s.rig.dispose();
        });
      },
    );

    test('5.3 a token marker 1 s in the future is fresh', () {
      fakeAsync((FakeAsync async) {
        final s = start(async, const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 5));
        expect(s.server.requests, isEmpty);
        s.rig.dispose();
      });
    });

    test('5.3 a token marker 2 s in the future is taken over at once', () {
      fakeAsync((FakeAsync async) {
        final s = start(async, const Duration(seconds: 2));
        expect(s.server.of('generate'), hasLength(1));
        async.elapse(const Duration(milliseconds: 10));
        expect(s.token.value, 'gen-$fid-0');
        s.rig.dispose();
      });
    });
  });

  group('5.3 markers: late response for an old FID', () {
    test('5.3 a create answer for a FID no longer stored is dropped', () {
      fakeAsync((FakeAsync async) {
        final _Rig rig = _Rig(async);
        final FakeFisServer server = FakeFisServer(
          createDelay: const Duration(seconds: 5),
        );
        final _Watch<({String id, String token})> result =
            _Watch<({String id, String token})>(
              rig.instance(server).getIdAndToken(),
            );
        async.flushMicrotasks();
        final String oldFid = server.of('create').single.fid;
        final String newFid = fakeFid(5);
        expect(newFid, isNot(oldFid));

        // Another writer replaces the record while the create for oldFid is in flight.
        async.elapse(const Duration(seconds: 1));
        server.createDelay = Duration.zero;
        rig.seed(recordJson(fid: newFid, status: 'unregistered'));

        async.elapse(const Duration(seconds: 5));
        expect(result.error, isNull);
        expect(result.value, (id: newFid, token: 'create-$newFid'));
        expect(server.of('create').map((FisRequest r) => r.fid), <String>[
          oldFid,
          newFid,
        ]);
        final String text = rig.stored()!;
        expect(text, isNot(contains(oldFid)));
        expect(decodeRecord(text)!['refreshToken'], 'rt-$newFid');
        rig.dispose();
      });
    });

    test('5.3 a generate answer for a FID no longer stored is dropped', () {
      fakeAsync((FakeAsync async) {
        final _Rig rig = _Rig(async);
        final String oldFid = fakeFid(6);
        final String newFid = fakeFid(7);
        rig.seed(
          recordJson(
            fid: oldFid,
            status: 'registered',
            refreshToken: 'rt-$oldFid',
            token: 'expired',
            tokenCreatedAt: _base.subtract(const Duration(hours: 2)),
            tokenExpiresIn: const Duration(hours: 1),
          ),
        );
        final FakeFisServer server = FakeFisServer(
          generateDelay: const Duration(seconds: 5),
        );
        final _Watch<({String id, String token})> result =
            _Watch<({String id, String token})>(
              rig.instance(server).getIdAndToken(),
            );
        async.flushMicrotasks();
        expect(server.of('generate').single.fid, oldFid);

        async.elapse(const Duration(seconds: 1));
        rig.seed(
          recordJson(
            fid: newFid,
            status: 'registered',
            refreshToken: 'rt-$newFid',
            token: 'valid-$newFid',
            tokenCreatedAt: rig.now(),
            tokenExpiresIn: const Duration(days: 7),
          ),
        );

        async.elapse(const Duration(seconds: 5));
        expect(result.error, isNull);
        expect(result.value, (id: newFid, token: 'valid-$newFid'));
        expect(server.of('generate'), hasLength(1));
        final String text = rig.stored()!;
        expect(text, isNot(contains('gen-')));
        expect(decodeRecord(text)!['fid'], newFid);
        rig.dispose();
      });
    });
  });
}
