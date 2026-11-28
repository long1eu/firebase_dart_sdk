@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/io.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/r3_fis_rig.dart';
import 'support/r4_fis_hooks.dart';

typedef _IdToken = ({String id, String token});

DateTime? _retryAfter(Object? error) =>
    (error! as FirebaseInstallationsException).retryAfter;

/// Registers [installations] (create answered with refresh-a / auth-a, living 7 days) and returns its
/// FID.
String _register(R3Rig rig, FakeFis fis, FirebaseInstallations installations) {
  fis.answer(
    FisRoute.create,
    FisAnswer.create(refreshToken: 'refresh-a', token: 'auth-a'),
  );
  final Outcome<_IdToken> first = Outcome<_IdToken>(
    installations.getIdAndToken(),
  );
  rig.async.flushMicrotasks();
  expect(first.value.token, 'auth-a');
  return first.value.id;
}

/// The record of [r3Fid] registered by another instance, with a token valid for 7 days.
String _registeredByOther(R3Rig rig) => r3Record(
  fid: r3Fid,
  status: 'registered',
  refreshToken: 'refresh-b',
  token: 'auth-b',
  tokenCreatedAt: rig.clock(),
  tokenExpiresIn: const Duration(days: 7),
);

/// A 409 recovery waiting behind another instance's marker, inside a long backoff window.
///
/// Four create 429s (each call made once the window before it ended) leave four recoverable failures,
/// so the 409 that follows opens a window of 2^5 + 0.5 = 32.5 s, longer than a marker stays fresh.
/// Then getToken's create gets that 409; when the recovery creates its new FID, another instance (owner
/// `tab-x.0`) stamps a fresh registration marker on it, so the retry waits. [retryAnswers] answer the
/// creates after the 409. Returns the call, the new FID and the end of the 409's window.
({Outcome<String> call, String fid, DateTime window}) _recoveryBehindMarker(
  R3Rig rig,
  FakeFis fis,
  R4HookStore store,
  FirebaseInstallations a,
  List<FisAnswer> retryAnswers,
) {
  for (int i = 0; i < 4; i++) {
    fis.answer(FisRoute.create, FisAnswer.status(429));
    final Outcome<String> failed = Outcome<String>(a.getToken());
    rig.async.flushMicrotasks();
    expect(failed.error, isFisException('too-many-requests', httpStatus: 429));
    rig.async.elapse(_retryAfter(failed.error)!.difference(rig.clock()));
  }
  final String fid1 = rig.stored()!['fid']! as String;
  fis.answer(FisRoute.create, FisAnswer.status(409), retryAnswers);

  bool removed = false;
  String? fid2;
  store.afterUpdate = (String key, String? value) {
    if (value == null) {
      removed = true;
      return;
    }
    if (!removed) {
      return;
    }
    store.afterUpdate = null;
    final String fid =
        (jsonDecode(value) as Map<String, Object?>)['fid']! as String;
    fid2 = fid;
    unawaited(
      rig.memory.write(
        key,
        r3Record(
          fid: fid,
          status: 'registering',
          registrationStartedAt: rig.clock(),
          registrationOwner: 'tab-x.0',
        ),
      ),
    );
  };

  final Outcome<String> call = Outcome<String>(a.getToken());
  rig.async.flushMicrotasks();
  final DateTime window = rig.clock().add(const Duration(milliseconds: 32500));
  expect(fis.count(FisRoute.create), 5);
  expect(fid2, isNotNull, reason: 'the recovery made a new FID');
  expect(fid2, isNot(fid1));
  expect(call.isDone, isFalse, reason: 'the retry waits for the marker');
  final Map<String, Object?> stored = rig.stored()!;
  expect(stored['fid'], fid2);
  expect(stored['registrationOwner'], 'tab-x.0');
  return (call: call, fid: fid2!, window: window);
}

void main() {
  group('A31 the 409 pass is spent only by a sent create', () {
    test('5.3 (A31): the 409 retry waits on a fresh foreign marker; once the '
        'marker is stale (16 s), still inside the 32.5 s window, it sends its '
        'create and the call succeeds', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final R4HookStore store = R4HookStore(rig.memory);
        final FirebaseInstallations a = rig.instance(fis, store: store);
        final (
          :Outcome<String> call,
          :String fid,
          :DateTime window,
        ) = _recoveryBehindMarker(rig, fis, store, a, <FisAnswer>[
          FisAnswer.create(refreshToken: 'refresh-r', token: 'auth-r'),
        ]);

        async.elapse(const Duration(seconds: 14));
        expect(fis.count(FisRoute.create), 5, reason: 'the marker is fresh');
        expect(call.isDone, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(rig.clock().isBefore(window), isTrue);
        expect(fis.count(FisRoute.create), 6);
        expect(fis.requestsTo(FisRoute.create).last.fid, fid);
        expect(call.value, 'auth-r');
        final Map<String, Object?> stored = rig.stored()!;
        expect(stored['fid'], fid);
        expect(stored['status'], 'registered');
        expect(stored['refreshToken'], 'refresh-r');
        rig.dispose();
      });
    });

    test('5.3 (A31): once the retry sent its create the pass is gone: a later '
        'look inside the window is too-many-requests', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final R4HookStore store = R4HookStore(rig.memory);
        final FirebaseInstallations a = rig.instance(fis, store: store);
        final Completer<void> gate = Completer<void>();
        final (
          :Outcome<String> call,
          :String fid,
          :DateTime window,
        ) = _recoveryBehindMarker(rig, fis, store, a, <FisAnswer>[
          FisAnswer.status(409, gate: gate.future),
        ]);

        async.elapse(const Duration(seconds: 16));
        expect(fis.count(FisRoute.create), 6, reason: 'the retry sent it');
        expect(call.isDone, isFalse);

        // Another attempt takes the marker over while the create is in flight, so its 409 leaves
        // the record and the loop looks again; that look has no pass left.
        rig.put(
          r3Record(
            fid: fid,
            status: 'registering',
            registrationStartedAt: rig.clock(),
            registrationOwner: 'tab-y.0',
          ),
        );
        gate.complete();
        async.flushMicrotasks();
        expect(call.error, isFisException('too-many-requests'));
        expect(_retryAfter(call.error), window);
        expect(rig.clock().isBefore(window), isTrue);
        expect(fis.count(FisRoute.create), 6);
        expect(rig.stored()!['registrationOwner'], 'tab-y.0');
        rig.dispose();
      });
    });

    test('5.3 (A31): the other instance registers the record while the 409 '
        'retry waits: the retry returns it and sends nothing', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final R4HookStore store = R4HookStore(rig.memory);
        final FirebaseInstallations a = rig.instance(fis, store: store);
        final (:Outcome<String> call, :String fid, :DateTime window) =
            _recoveryBehindMarker(rig, fis, store, a, <FisAnswer>[]);

        async.elapse(const Duration(seconds: 5));
        final String registered = r3Record(
          fid: fid,
          status: 'registered',
          refreshToken: 'refresh-x',
          token: 'auth-x',
          tokenCreatedAt: rig.clock(),
          tokenExpiresIn: const Duration(days: 7),
        );
        rig.put(registered);
        async.elapse(const Duration(milliseconds: 200));
        expect(call.value, 'auth-x');
        expect(rig.clock().isBefore(window), isTrue);
        expect(fis.count(FisRoute.create), 5, reason: 'nothing sent');
        expect(fis.count(FisRoute.generate), 0);
        expect(rig.storedText(), registered);
        rig.dispose();
      });
    });
  });

  group('A31 the 409 recovery passes its own window, once', () {
    test('5.3 (A31): the 409 retry finds a record another instance '
        'registered; a later call inside the 409 window is '
        'too-many-requests and sends no create', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis()
          ..answer(FisRoute.create, FisAnswer.status(409));
        final R4HookStore store = R4HookStore(rig.memory);
        final FirebaseInstallations a = rig.instance(fis, store: store);
        // Right after the 409 removes the record, another instance stores its registration.
        store.afterUpdate = (String key, String? value) {
          if (value == null) {
            store.afterUpdate = null;
            unawaited(rig.memory.write(key, _registeredByOther(rig)));
          }
        };

        final Outcome<_IdToken> first = Outcome<_IdToken>(a.getIdAndToken());
        async.flushMicrotasks();
        expect(first.value, (id: r3Fid, token: 'auth-b'));
        expect(fis.count(FisRoute.create), 1);
        expect(fis.count(FisRoute.generate), 0);

        // The other instance deletes its installation; the next call needs a create.
        rig.put(null);
        final Outcome<String> later = Outcome<String>(a.getToken());
        async.flushMicrotasks();
        expect(later.error, isFisException('too-many-requests'));
        // One recoverable failure at t = 0 with jitter 0.5: 2^1 + 0.5 s.
        expect(
          _retryAfter(later.error),
          rig.clock().add(const Duration(milliseconds: 2500)),
        );
        expect(fis.count(FisRoute.create), 1, reason: 'nothing sent');
        rig.dispose();
      });
    });

    test('5.3 (A31): a generate 400 of the other token operation before the '
        '409 retry looks: the retry create is not sent and the call gets '
        'bad-config with the 24 h retryAfter', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis()
          ..answer(FisRoute.create, FisAnswer.status(409))
          ..answer(FisRoute.generate, FisAnswer.status(400));
        final R4HookStore store = R4HookStore(rig.memory);
        final FirebaseInstallations a = rig.instance(fis, store: store);
        // After the 409 removes the record, the next store update of the retry waits for the gate.
        final Completer<void> gate = Completer<void>();
        store.afterUpdate = (String key, String? value) {
          if (value == null) {
            store
              ..afterUpdate = null
              ..holdNextUpdate = gate.future;
          }
        };

        final Outcome<String> first = Outcome<String>(a.getToken());
        async.flushMicrotasks();
        expect(fis.count(FisRoute.create), 1);
        expect(store.held, 1, reason: 'the retry waits before its create');
        expect(first.isDone, isFalse);

        // Past the 409 window, another instance stores its registration, and the forced token
        // operation of this instance gets a 400 on generate: the 24 h block.
        async.elapse(const Duration(seconds: 3));
        rig.put(_registeredByOther(rig));
        final Outcome<String> forced = Outcome<String>(
          a.getToken(forceRefresh: true),
        );
        async.flushMicrotasks();
        expect(forced.error, isFisException('bad-config', httpStatus: 400));
        final DateTime blockedUntil = rig.clock().add(
          const Duration(hours: 24),
        );
        expect(_retryAfter(forced.error), blockedUntil);
        expect(fis.count(FisRoute.generate), 1);

        // The other instance deletes its installation; the retry goes on and needs a create.
        rig.put(null);
        gate.complete();
        async.flushMicrotasks();
        expect(first.error, isFisException('bad-config', httpStatus: 400));
        expect(_retryAfter(first.error), blockedUntil);
        expect(fis.count(FisRoute.create), 1, reason: 'the retry is not sent');
        rig.dispose();
      });
    });
  });

  group('A31 unexpected 4xx', () {
    for (final int status in <int>[405, 408, 410]) {
      test('5.3 (A31): create $status is invalid-response ($status); the next '
          'call inside the window is too-many-requests and sends nothing', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fis = FakeFis()
            ..answer(FisRoute.create, FisAnswer.status(status));
          final FirebaseInstallations a = rig.instance(fis);

          final Outcome<String> first = Outcome<String>(a.getToken());
          async.flushMicrotasks();
          expect(
            first.error,
            isFisException('invalid-response', httpStatus: status),
          );
          expect(fis.count(FisRoute.create), 1, reason: 'a 4xx is not retried');
          expect(rig.stored()!['status'], 'unregistered');

          final Outcome<String> second = Outcome<String>(a.getToken());
          async.flushMicrotasks();
          expect(second.error, isFisException('too-many-requests'));
          expect(
            _retryAfter(second.error),
            rig.clock().add(const Duration(milliseconds: 2500)),
          );
          expect(fis.count(FisRoute.create), 1);
          rig.dispose();
        });
      });
    }

    for (final int status in <int>[409, 410]) {
      test('5.3 (A31): generate $status is invalid-response ($status); the '
          'record stays registered with its refresh token, no new FID', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fis = FakeFis();
          final FirebaseInstallations a = rig.instance(fis);
          final String fid = _register(rig, fis, a);
          final List<String> events = <String>[];
          a.onIdChange.listen(events.add);
          fis.answer(FisRoute.generate, FisAnswer.status(status));

          final Outcome<String> forced = Outcome<String>(
            a.getToken(forceRefresh: true),
          );
          async.flushMicrotasks();
          expect(
            forced.error,
            isFisException('invalid-response', httpStatus: status),
          );
          final Map<String, Object?> stored = rig.stored()!;
          expect(stored['fid'], fid);
          expect(stored['status'], 'registered');
          expect(stored['refreshToken'], 'refresh-a');
          expect(stored['token'], 'auth-a');
          expect(stored['tokenRequestOwner'], isNull, reason: 'released');

          final Outcome<String> again = Outcome<String>(
            a.getToken(forceRefresh: true),
          );
          async.flushMicrotasks();
          expect(again.error, isFisException('too-many-requests'));
          expect(fis.count(FisRoute.generate), 1);

          final Outcome<_IdToken> pair = Outcome<_IdToken>(a.getIdAndToken());
          async.flushMicrotasks();
          expect(pair.value, (id: fid, token: 'auth-a'));
          expect(fis.count(FisRoute.create), 1);
          expect(events, isEmpty);
          rig.dispose();
        });
      });
    }

    for (final int status in <int>[400, 403]) {
      test(
        '5.3 (A31): create $status stays bad-config with the 24 h block',
        () {
          fakeAsync((FakeAsync async) {
            final R3Rig rig = R3Rig(async);
            final FakeFis fis = FakeFis()
              ..answer(FisRoute.create, FisAnswer.status(status));
            final FirebaseInstallations a = rig.instance(fis);

            final Outcome<String> first = Outcome<String>(a.getToken());
            async.flushMicrotasks();
            expect(
              first.error,
              isFisException('bad-config', httpStatus: status),
            );
            final DateTime until = rig.clock().add(const Duration(hours: 24));
            expect(_retryAfter(first.error), until);

            rig.clock.offset =
                const Duration(hours: 24) - const Duration(seconds: 1);
            final Outcome<String> second = Outcome<String>(a.getToken());
            async.flushMicrotasks();
            expect(
              second.error,
              isFisException('bad-config', httpStatus: status),
            );
            expect(_retryAfter(second.error), until);
            expect(fis.count(FisRoute.create), 1);
            rig.dispose();
          });
        },
      );

      test(
        '5.3 (A31): generate $status stays bad-config with the 24 h block',
        () {
          fakeAsync((FakeAsync async) {
            final R3Rig rig = R3Rig(async);
            final FakeFis fis = FakeFis();
            final FirebaseInstallations a = rig.instance(fis);
            final String fid = _register(rig, fis, a);
            fis.answer(FisRoute.generate, FisAnswer.status(status));

            final Outcome<String> first = Outcome<String>(
              a.getToken(forceRefresh: true),
            );
            async.flushMicrotasks();
            expect(
              first.error,
              isFisException('bad-config', httpStatus: status),
            );
            final DateTime until = rig.clock().add(const Duration(hours: 24));
            expect(_retryAfter(first.error), until);

            final Outcome<String> second = Outcome<String>(
              a.getToken(forceRefresh: true),
            );
            async.flushMicrotasks();
            expect(
              second.error,
              isFisException('bad-config', httpStatus: status),
            );
            expect(_retryAfter(second.error), until);
            expect(fis.count(FisRoute.generate), 1);
            expect(rig.stored()!['fid'], fid);
            expect(rig.stored()!['refreshToken'], 'refresh-a');
            rig.dispose();
          });
        },
      );
    }

    for (final int status in <int>[401, 404]) {
      test('5.3 (A31): create $status is bad-config with a growing window '
          '(2.5 s, then 4.5 s)', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fis = FakeFis()
            ..answer(FisRoute.create, FisAnswer.status(status), <FisAnswer>[
              FisAnswer.status(status),
            ]);
          final FirebaseInstallations a = rig.instance(fis);

          final Outcome<String> first = Outcome<String>(a.getToken());
          async.flushMicrotasks();
          expect(first.error, isFisException('bad-config', httpStatus: status));
          expect(
            _retryAfter(first.error),
            rig.clock().add(const Duration(milliseconds: 2500)),
          );

          async.elapse(const Duration(milliseconds: 2500));
          final Outcome<String> second = Outcome<String>(a.getToken());
          async.flushMicrotasks();
          expect(
            second.error,
            isFisException('bad-config', httpStatus: status),
          );
          final DateTime until = rig.clock().add(
            const Duration(milliseconds: 4500),
          );
          expect(_retryAfter(second.error), until);
          expect(fis.count(FisRoute.create), 2);

          final Outcome<String> third = Outcome<String>(a.getToken());
          async.flushMicrotasks();
          expect(third.error, isFisException('bad-config', httpStatus: status));
          expect(_retryAfter(third.error), until);
          expect(fis.count(FisRoute.create), 2, reason: 'inside the window');
          rig.dispose();
        });
      });
    }
  });

  group('A32 FileKeyValueStore clock', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('fis_r4_clock_');
      addTearDown(() {
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
      });
    });

    /// A store directory under [root] holding one temporary file of the store's naming whose mtime is
    /// 2 h old; returns the directory, the file and the mtime the file system kept.
    ({Directory dir, File file, DateTime mtime}) withOldTemporary(String name) {
      final Directory dir = Directory(
        '${root.path}${Platform.pathSeparator}$name',
      )..createSync();
      final File file = File(
        '${dir.path}${Platform.pathSeparator}.${'a' * 64}.json.${'0' * 32}.tmp',
      )..writeAsStringSync('x');
      file.setLastModifiedSync(
        DateTime.now().subtract(const Duration(hours: 2)),
      );
      return (dir: dir, file: file, mtime: file.statSync().modified);
    }

    test('5.2.1 (A32): a 2 h old temporary file survives when the injected '
        'clock is 30 min after its mtime', () async {
      final (:Directory dir, :File file, :DateTime mtime) = withOldTemporary(
        'kept',
      );
      final FileKeyValueStore store = FileKeyValueStore(
        dir.path,
        clock: () => mtime.add(const Duration(minutes: 30)),
      );
      addTearDown(store.close);

      expect(await store.read('anything'), isNull);
      expect(file.existsSync(), isTrue);
    });

    test('5.2.1 (A32): the same file is deleted when the injected clock is '
        '61 min after its mtime', () async {
      final (:Directory dir, :File file, :DateTime mtime) = withOldTemporary(
        'deleted',
      );
      final FileKeyValueStore store = FileKeyValueStore(
        dir.path,
        clock: () => mtime.add(const Duration(minutes: 61)),
      );
      addTearDown(store.close);

      expect(await store.read('anything'), isNull);
      expect(file.existsSync(), isFalse);
    });
  });

  group('A33 replayed removals', () {
    test('5.3 (A33): delete() removes a stale foreign marker and the write '
        'fails; its owner re-stamps it (same owner, fresh time); the replay '
        "keeps it and the owner's create result is stored", () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fisA = FakeFis();
        final FakeFis fisX = FakeFis();
        final R3Store store = rig.flakyStore();
        final FirebaseInstallations a = rig.instance(fisA, store: store);
        final FirebaseInstallations x = rig.instance(fisX);
        final Completer<void> firstGate = Completer<void>();
        final Completer<void> retryGate = Completer<void>();
        fisX.answer(
          FisRoute.create,
          FisAnswer.status(503, gate: firstGate.future),
          <FisAnswer>[
            FisAnswer.create(
              refreshToken: 'refresh-x',
              token: 'auth-x',
              gate: retryGate.future,
            ),
          ],
        );

        final Outcome<String> fromX = Outcome<String>(x.getToken());
        async.flushMicrotasks();
        final String fid = fisX.requestsTo(FisRoute.create).single.fid!;
        final Map<String, Object?> marker = rig.stored()!;
        expect(marker['status'], 'registering');

        // 20 s later X's marker is stale: delete() removes it, and the write fails.
        rig.clock.offset = const Duration(seconds: 20);
        store.failUpdates = true;
        final Outcome<void> deleted = Outcome<void>(a.delete());
        async.flushMicrotasks();
        expect(deleted.isDone, isTrue);
        expect(deleted.error, isNull);
        expect(store.updateFailures, greaterThan(0));
        expect(fisA.requests, isEmpty, reason: 'nothing registered to delete');
        expect(
          rig.stored()!['registrationStartedAt'],
          marker['registrationStartedAt'],
        );

        // X's 503 is retried after 1 s; X re-stamps its marker first.
        firstGate.complete();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        expect(fisX.count(FisRoute.create), 2);
        final Map<String, Object?> restamped = rig.stored()!;
        expect(restamped['registrationOwner'], marker['registrationOwner']);
        expect(
          restamped['registrationStartedAt'],
          rig.clock().millisecondsSinceEpoch,
        );
        final String? restampedText = rig.storedText();

        store.failUpdates = false;
        final Outcome<String> id = Outcome<String>(a.getId());
        async.flushMicrotasks();
        expect(id.value, fid);
        expect(rig.storedText(), restampedText, reason: "X's marker stays");

        retryGate.complete();
        async.flushMicrotasks();
        expect(fromX.value, 'auth-x');
        final Map<String, Object?> stored = rig.stored()!;
        expect(stored['fid'], fid);
        expect(stored['status'], 'registered');
        expect(stored['refreshToken'], 'refresh-x');

        async.elapse(const Duration(milliseconds: 200));
        final Outcome<String> tokenOfA = Outcome<String>(a.getToken());
        async.flushMicrotasks();
        expect(tokenOfA.value, 'auth-x');
        expect(fisA.requests, isEmpty);
        rig.dispose();
      });
    });

    test('5.3 (A33): counter-test: the removed marker, still there with the '
        'same owner and the same start time, is removed by the replay', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final R3Store store = rig.flakyStore();
        final FirebaseInstallations a = rig.instance(fis, store: store);
        final String foreign = r3Record(
          fid: r3Fid,
          status: 'registering',
          registrationStartedAt: rig.clock(),
          registrationOwner: 'tab-x.0',
        );
        rig.put(foreign);

        rig.clock.offset = const Duration(seconds: 20);
        store.failUpdates = true;
        final Outcome<void> deleted = Outcome<void>(a.delete());
        async.flushMicrotasks();
        expect(deleted.isDone, isTrue);
        expect(deleted.error, isNull);
        expect(rig.storedText(), foreign, reason: 'the write failed');

        // The clock is turned back, so the unchanged marker looks fresh again: only its owner and
        // start time say it is the marker that was removed.
        rig.clock.offset = Duration.zero;
        store.failUpdates = false;
        final Outcome<void> again = Outcome<void>(a.delete());
        async.flushMicrotasks();
        expect(again.isDone, isTrue);
        expect(again.error, isNull);
        expect(rig.storedText(), isNull);
        expect(fis.requests, isEmpty);
        rig.dispose();
      });
    });

    for (final bool transformFirst in <bool>[true, false]) {
      final String mode = transformFirst
          ? 'the write fails after its transform'
          : 'the update fails before its transform';

      test('5.3 (A33): a removal of R fails to write, then a new FID made in '
          'memory is removed by a 409 while writes still fail; once the store '
          'recovers it no longer holds R ($mode)', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fis = FakeFis();
          final R3Store store = rig.flakyStore()
            ..transformBeforeFailing = transformFirst;
          final FirebaseInstallations a = rig.instance(fis, store: store);
          final String fid1 = _register(rig, fis, a);

          store.failUpdates = true;
          final Outcome<void> deleted = Outcome<void>(a.delete());
          async.flushMicrotasks();
          expect(deleted.error, isNull);
          expect(deleted.isDone, isTrue);
          expect(fis.count(FisRoute.delete), 1);
          expect(rig.stored()!['fid'], fid1, reason: 'the removal failed');

          fis.answer(FisRoute.create, FisAnswer.status(409));
          final Outcome<String> second = Outcome<String>(a.getId());
          async.flushMicrotasks();
          final String fid2 = second.value;
          expect(fid2, isNot(fid1));
          expect(fis.count(FisRoute.create), 2);
          expect(fis.requestsTo(FisRoute.create).last.fid, fid2);
          expect(rig.stored()!['fid'], fid1, reason: 'nothing written yet');

          store.failUpdates = false;
          final Outcome<String> third = Outcome<String>(a.getId());
          async.flushMicrotasks();
          final String fid3 = third.value;
          expect(fid3, isNot(fid1));
          expect(fid3, isNot(fid2));
          final Map<String, Object?> stored = rig.stored()!;
          expect(stored['fid'], fid3);
          expect(stored['refreshToken'], isNull);
          expect(
            fis.count(FisRoute.create),
            2,
            reason: "the 409's window holds the new FID back",
          );
          rig.dispose();
        });
      });
    }
  });

  group('A33 onIdChange for a FID kept only in memory', () {
    test('5.3 (A33): the first getId with failing writes emits F1; another '
        'instance stores F2; the next call returns F2 and emits it', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final R3Store store = rig.flakyStore()..failUpdates = true;
        final FirebaseInstallations a = rig.instance(fis, store: store);
        final List<String> events = <String>[];
        a.onIdChange.listen(events.add);

        final Outcome<String> first = Outcome<String>(a.getId());
        async.flushMicrotasks();
        final String fid1 = first.value;
        expect(events, <String>[fid1]);
        expect(rig.storedText(), isNull);

        final String other = _registeredByOther(rig);
        rig.put(other);
        store.failUpdates = false;
        final Outcome<String> next = Outcome<String>(a.getId());
        async.flushMicrotasks();
        expect(next.value, r3Fid);
        expect(events, <String>[fid1, r3Fid]);
        expect(rig.storedText(), other);

        final Outcome<String> token = Outcome<String>(a.getToken());
        async.flushMicrotasks();
        expect(token.value, 'auth-b');
        expect(fis.count(FisRoute.generate), 0);
        expect(events, <String>[fid1, r3Fid], reason: 'nothing more');
        rig.dispose();
      });
    });

    test('5.3 (A33): counter-test: the same FID written once the store '
        'recovers emits nothing more', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final R3Store store = rig.flakyStore()..failUpdates = true;
        final FirebaseInstallations a = rig.instance(fis, store: store);
        final List<String> events = <String>[];
        a.onIdChange.listen(events.add);

        final Outcome<String> first = Outcome<String>(a.getId());
        async.flushMicrotasks();
        final String fid1 = first.value;
        expect(events, <String>[fid1]);

        store.failUpdates = false;
        final Outcome<String> next = Outcome<String>(a.getId());
        async.flushMicrotasks();
        expect(next.value, fid1);
        expect(rig.stored()!['fid'], fid1);
        expect(events, <String>[fid1]);
        rig.dispose();
      });
    });
  });
}
