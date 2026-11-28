@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/r3_fis_rig.dart';

typedef _IdToken = ({String id, String token});

DateTime? _retryAfter(Object? error) =>
    (error! as FirebaseInstallationsException).retryAfter;

/// Registers [installations] (create answered with [refreshToken], [token] and [expiresIn]) and
/// returns its FID.
String _register(
  R3Rig rig,
  FakeFis fis,
  FirebaseInstallations installations, {
  String refreshToken = 'refresh-a',
  String token = 'auth-a',
  String expiresIn = '604800s',
}) {
  fis.answer(
    FisRoute.create,
    FisAnswer.create(
      refreshToken: refreshToken,
      token: token,
      expiresIn: expiresIn,
    ),
  );
  final Outcome<_IdToken> first = Outcome<_IdToken>(
    installations.getIdAndToken(),
  );
  rig.async.flushMicrotasks();
  expect(first.value.token, token);
  return first.value.id;
}

void main() {
  group('A2 / A3 transient write failures and another instance', () {
    test('5.3 (A2): a no-op update fails once, another instance deletes; the '
        'next call leaves the store empty and getId makes a new FID', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fisA = FakeFis();
        final FakeFis fisB = FakeFis();
        final R3Store store = rig.flakyStore();
        final FirebaseInstallations a = rig.instance(fisA, store: store);
        final FirebaseInstallations b = rig.instance(fisB);
        // The token lives 3700 s: after 101 s it is inside its last hour.
        final String fid1 = _register(rig, fisA, a, expiresIn: '3700s');
        async.elapse(const Duration(seconds: 101));
        fisB.answer(FisRoute.generate, FisAnswer.token(token: 'auth-b'));
        final Outcome<String> refreshed = Outcome<String>(
          b.getToken(forceRefresh: true),
        );
        async.flushMicrotasks();
        expect(refreshed.value, 'auth-b');

        // A reads its stale copy (the read fails), then its claim finds B's valid token and returns it
        // unchanged: a no-op update, and that update fails.
        store
          ..failNextReads = 1
          ..failNextUpdates = 1;
        final Outcome<String> viaA = Outcome<String>(a.getToken());
        async.flushMicrotasks();
        expect(viaA.value, 'auth-b');
        expect(store.updateFailures, 1);
        expect(fisA.count(FisRoute.generate), 0);

        final Outcome<void> deletedByB = Outcome<void>(b.delete());
        async.flushMicrotasks();
        expect(deletedByB.isDone, isTrue);
        expect(deletedByB.error, isNull);
        expect(fisB.count(FisRoute.delete), 1);
        expect(rig.storedText(), isNull);

        final Outcome<void> deletedByA = Outcome<void>(a.delete());
        async.flushMicrotasks();
        expect(deletedByA.isDone, isTrue);
        expect(deletedByA.error, isNull);
        expect(fisA.count(FisRoute.delete), 0, reason: 'nothing to delete');
        expect(rig.storedText(), isNull, reason: 'nothing written back');

        final Outcome<String> id = Outcome<String>(a.getId());
        async.flushMicrotasks();
        expect(id.value, isNot(fid1));
        expect(rig.stored()!['fid'], id.value);
        rig.dispose();
      });
    });

    test('5.3 (A3): a new token that failed to write is not written back '
        'after another instance deleted the record', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fisA = FakeFis();
        final FakeFis fisB = FakeFis();
        final R3Store store = rig.flakyStore();
        final FirebaseInstallations a = rig.instance(fisA, store: store);
        final FirebaseInstallations b = rig.instance(fisB);
        final String fid1 = _register(rig, fisA, a);

        store.failUpdates = true;
        fisA.answer(FisRoute.generate, FisAnswer.token(token: 'auth-a2'));
        final Outcome<String> forced = Outcome<String>(
          a.getToken(forceRefresh: true),
        );
        async.flushMicrotasks();
        expect(forced.value, 'auth-a2');
        expect(rig.stored()!['token'], 'auth-a', reason: 'the write failed');
        store.failUpdates = false;

        final Outcome<void> deletedByB = Outcome<void>(b.delete());
        async.flushMicrotasks();
        expect(deletedByB.error, isNull);
        expect(fisB.count(FisRoute.delete), 1);
        expect(rig.storedText(), isNull);

        final Outcome<void> deletedByA = Outcome<void>(a.delete());
        async.flushMicrotasks();
        expect(deletedByA.isDone, isTrue);
        expect(deletedByA.error, isNull);
        expect(fisA.count(FisRoute.delete), 0);
        expect(rig.storedText(), isNull, reason: 'the new token stays unsaved');

        final Outcome<String> id = Outcome<String>(a.getId());
        async.flushMicrotasks();
        expect(id.value, isNot(fid1));
        expect(rig.stored()!['fid'], id.value);
        rig.dispose();
      });
    });

    for (final bool transformFirst in <bool>[true, false]) {
      final String mode = transformFirst
          ? 'the write fails after its transform'
          : 'the update fails before its transform';

      test('5.3 (A3): first-ever getId with a failing write; the same FID is '
          'written once the store works ($mode)', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fis = FakeFis();
          final R3Store store = rig.flakyStore()
            ..transformBeforeFailing = transformFirst
            ..failUpdates = true;
          final FirebaseInstallations a = rig.instance(fis, store: store);

          final Outcome<String> id = Outcome<String>(a.getId());
          async.flushMicrotasks();
          final String fid = id.value;
          expect(store.updateFailures, greaterThan(0));
          expect(rig.storedText(), isNull);

          store.failUpdates = false;
          final Outcome<String> again = Outcome<String>(a.getId());
          async.flushMicrotasks();
          expect(again.value, fid);
          final Map<String, Object?> stored = rig.stored()!;
          expect(stored['fid'], fid);
          expect(stored['status'], 'registered');
          expect(
            fis.requestsTo(FisRoute.create).map((FisRequest r) => r.fid),
            <String?>[fid],
          );
          rig.dispose();
        });
      });

      test('5.3 (A3): a 409 removal fails to write, another instance takes the '
          'marker over; the replay leaves its marker ($mode)', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fisA = FakeFis();
          final FakeFis fisB = FakeFis();
          final R3Store store = rig.flakyStore()
            ..transformBeforeFailing = transformFirst;
          final FirebaseInstallations a = rig.instance(fisA, store: store);
          final FirebaseInstallations b = rig.instance(fisB);
          final Completer<void> gateA = Completer<void>();
          fisA.answer(
            FisRoute.create,
            FisAnswer.status(409, gate: gateA.future),
          );

          final Outcome<String> id = Outcome<String>(a.getId());
          async.flushMicrotasks();
          final String fid = id.value;
          expect(fisA.count(FisRoute.create), 1);
          store.failUpdates = true;
          gateA.complete();
          async.flushMicrotasks();
          expect(store.updateFailures, greaterThan(0));
          expect(rig.stored()!['status'], 'registering', reason: 'not removed');

          // 20 s later A's marker is stale: B takes it over and sends its own create.
          rig.clock.offset = const Duration(seconds: 20);
          final Completer<void> gateB = Completer<void>();
          fisB.answer(
            FisRoute.create,
            FisAnswer.create(
              refreshToken: 'refresh-b',
              token: 'auth-b',
              gate: gateB.future,
            ),
          );
          final Outcome<String> fromB = Outcome<String>(b.getToken());
          async.flushMicrotasks();
          expect(fisB.requestsTo(FisRoute.create).single.fid, fid);
          final String? takenOver = rig.storedText();
          expect(
            rig.stored()!['registrationStartedAt'],
            rig.clock().millisecondsSinceEpoch,
          );

          store.failUpdates = false;
          final Outcome<String> again = Outcome<String>(a.getId());
          async.flushMicrotasks();
          expect(again.value, fid);
          expect(rig.storedText(), takenOver, reason: "B's marker stays");
          expect(fisA.count(FisRoute.create), 1);

          gateB.complete();
          async.flushMicrotasks();
          expect(fromB.value, 'auth-b');
          final Map<String, Object?> stored = rig.stored()!;
          expect(stored['status'], 'registered');
          expect(stored['refreshToken'], 'refresh-b');
          rig.dispose();
        });
      });

      test('5.3 (A3): a 409 removal fails to write, another instance registers '
          'the FID; the replay leaves that record ($mode)', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fisA = FakeFis();
          final FakeFis fisB = FakeFis();
          final R3Store store = rig.flakyStore()
            ..transformBeforeFailing = transformFirst;
          final FirebaseInstallations a = rig.instance(fisA, store: store);
          final FirebaseInstallations b = rig.instance(fisB);
          final Completer<void> gateA = Completer<void>();
          fisA.answer(
            FisRoute.create,
            FisAnswer.status(409, gate: gateA.future),
          );

          final Outcome<String> id = Outcome<String>(a.getId());
          async.flushMicrotasks();
          final String fid = id.value;
          store.failUpdates = true;
          gateA.complete();
          async.flushMicrotasks();
          expect(rig.stored()!['status'], 'registering', reason: 'not removed');

          rig.clock.offset = const Duration(seconds: 20);
          fisB.answer(
            FisRoute.create,
            FisAnswer.create(refreshToken: 'refresh-b', token: 'auth-b'),
          );
          final Outcome<String> fromB = Outcome<String>(b.getToken());
          async.flushMicrotasks();
          expect(fromB.value, 'auth-b');
          final String? registeredByB = rig.storedText();

          store.failUpdates = false;
          final Outcome<String> again = Outcome<String>(a.getId());
          async.flushMicrotasks();
          expect(again.value, fid);
          expect(rig.storedText(), registeredByB);
          final Outcome<String> tokenOfA = Outcome<String>(a.getToken());
          async.flushMicrotasks();
          expect(tokenOfA.value, 'auth-b');
          expect(fisA.count(FisRoute.create), 1);
          expect(fisA.count(FisRoute.generate), 0);
          rig.dispose();
        });
      });

      test('5.3 (A3): a failed delete() removal leaves a record registered '
          'since with another refresh token ($mode)', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fisA = FakeFis();
          final R3Store store = rig.flakyStore()
            ..transformBeforeFailing = transformFirst;
          final FirebaseInstallations a = rig.instance(fisA, store: store);
          final String fid = _register(rig, fisA, a);

          store.failUpdates = true;
          final Outcome<void> deleted = Outcome<void>(a.delete());
          async.flushMicrotasks();
          expect(deleted.isDone, isTrue);
          expect(deleted.error, isNull);
          expect(fisA.count(FisRoute.delete), 1);
          expect(rig.stored()!['refreshToken'], 'refresh-a', reason: 'kept');

          // Another instance registered the same FID since, with its own refresh token.
          final String registeredSince = r3Record(
            fid: fid,
            status: 'registered',
            refreshToken: 'refresh-b',
            token: 'auth-b',
            tokenCreatedAt: rig.clock(),
            tokenExpiresIn: const Duration(days: 7),
          );
          rig.put(registeredSince);

          store.failUpdates = false;
          final Outcome<String> id = Outcome<String>(a.getId());
          async.flushMicrotasks();
          expect(id.value, fid);
          expect(rig.storedText(), registeredSince);
          final Outcome<String> token = Outcome<String>(a.getToken());
          async.flushMicrotasks();
          expect(token.value, 'auth-b');
          expect(fisA.count(FisRoute.create), 1);
          expect(fisA.count(FisRoute.generate), 0);
          rig.dispose();
        });
      });

      test('5.3 (A3): a 409 removal fails to write, a new FID is made in '
          'memory, the store recovers: the store ends with the new FID '
          '($mode)', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fis = FakeFis();
          final R3Store store = rig.flakyStore()
            ..transformBeforeFailing = transformFirst;
          final FirebaseInstallations a = rig.instance(fis, store: store);
          final Completer<void> gate = Completer<void>();
          fis.answer(FisRoute.create, FisAnswer.status(409, gate: gate.future));

          final Outcome<String> first = Outcome<String>(a.getId());
          async.flushMicrotasks();
          final String fid1 = first.value;
          store.failUpdates = true;
          gate.complete();
          async.flushMicrotasks();

          final Outcome<String> second = Outcome<String>(a.getId());
          async.flushMicrotasks();
          final String fid2 = second.value;
          expect(fid2, isNot(fid1));
          expect(rig.stored()!['fid'], fid1, reason: 'nothing written yet');

          store.failUpdates = false;
          final Outcome<String> third = Outcome<String>(a.getId());
          async.flushMicrotasks();
          expect(third.value, fid2);
          expect(rig.stored()!['fid'], fid2);
          expect(
            fis.count(FisRoute.create),
            1,
            reason: "the 409's backoff window holds the new FID back",
          );
          rig.dispose();
        });
      });
    }
  });

  group('A4 statuses per endpoint and the backoff', () {
    test('5.3 (A4): a server always answering 409 gets two creates, then '
        'nothing inside the window', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis()
          ..answerAll(FisRoute.create, () => FisAnswer.status(409));
        final FirebaseInstallations a = rig.instance(fis);

        final Outcome<String> first = Outcome<String>(a.getToken());
        async.flushMicrotasks();
        expect(
          first.error,
          isFisException('invalid-response', httpStatus: 409),
        );
        final List<String?> sent = <String?>[
          for (final FisRequest r in fis.requestsTo(FisRoute.create)) r.fid,
        ];
        expect(sent, hasLength(2));
        expect(
          sent[0],
          isNot(sent[1]),
          reason: 'the second create has a new FID',
        );

        final Outcome<String> second = Outcome<String>(a.getToken());
        async.flushMicrotasks();
        expect(fis.count(FisRoute.create), 2, reason: 'nothing sent');
        // A 409 is `invalid-response` (A31), not `bad-config`: the window it started reports
        // `too-many-requests`.
        expect(second.error, isFisException('too-many-requests'));
        // Two recoverable failures at t = 0 with jitter 0.5: 2^2 + 0.5 s.
        expect(
          _retryAfter(second.error),
          rig.clock().add(const Duration(milliseconds: 4500)),
        );
        rig.dispose();
      });
    });

    test('5.3 (A4): repeated getId against 409s gives FID1, FID2, then FID2 '
        'with no further create inside the window', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis()
          ..answerAll(FisRoute.create, () => FisAnswer.status(409));
        final FirebaseInstallations a = rig.instance(fis);

        final Outcome<String> first = Outcome<String>(a.getId());
        async.flushMicrotasks();
        expect(fis.requestsTo(FisRoute.create).single.fid, first.value);
        expect(rig.storedText(), isNull, reason: 'the 409 removed the record');

        final Outcome<String> second = Outcome<String>(a.getId());
        async.flushMicrotasks();
        expect(second.value, isNot(first.value));
        expect(fis.count(FisRoute.create), 1);

        final Outcome<String> third = Outcome<String>(a.getId());
        async.flushMicrotasks();
        expect(third.value, second.value);
        expect(fis.count(FisRoute.create), 1);
        expect(rig.stored()!['fid'], second.value);
        rig.dispose();
      });
    });

    test('5.3 (A4): a 302 on create opens a window; the next call inside it '
        'sends no request', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis()
          ..answer(FisRoute.create, FisAnswer.status(302));
        final FirebaseInstallations a = rig.instance(fis);

        final Outcome<String> first = Outcome<String>(a.getToken());
        async.flushMicrotasks();
        expect(
          first.error,
          isFisException('invalid-response', httpStatus: 302),
        );

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

    test('5.3 (A4): a 302 on generate opens a window; the next call inside it '
        'sends no request', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final FirebaseInstallations a = rig.instance(fis);
        _register(rig, fis, a);
        fis.answer(FisRoute.generate, FisAnswer.status(302));

        final Outcome<String> first = Outcome<String>(
          a.getToken(forceRefresh: true),
        );
        async.flushMicrotasks();
        expect(
          first.error,
          isFisException('invalid-response', httpStatus: 302),
        );

        final Outcome<String> second = Outcome<String>(
          a.getToken(forceRefresh: true),
        );
        async.flushMicrotasks();
        expect(second.error, isFisException('too-many-requests'));
        expect(
          _retryAfter(second.error),
          rig.clock().add(const Duration(milliseconds: 2500)),
        );
        expect(fis.count(FisRoute.generate), 1);
        rig.dispose();
      });
    });

    for (final int status in <int>[401, 404]) {
      test('5.3 (A4): create $status is bad-config with retryAfter; the next '
          'call rethrows it without a request', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fis = FakeFis()
            ..answer(FisRoute.create, FisAnswer.status(status));
          final FirebaseInstallations a = rig.instance(fis);

          final Outcome<String> first = Outcome<String>(a.getToken());
          async.flushMicrotasks();
          expect(first.error, isFisException('bad-config', httpStatus: status));
          final DateTime until = rig.clock().add(
            const Duration(milliseconds: 2500),
          );
          expect(_retryAfter(first.error), until);

          final Outcome<String> second = Outcome<String>(a.getToken());
          async.flushMicrotasks();
          expect(
            second.error,
            isFisException('bad-config', httpStatus: status),
          );
          expect(_retryAfter(second.error), until);
          expect(fis.count(FisRoute.create), 1);

          // A recoverable window, not the 24 h block of 400/403.
          async.elapse(const Duration(milliseconds: 2500));
          final Outcome<String> later = Outcome<String>(a.getToken());
          async.flushMicrotasks();
          expect(later.error, isNull);
          expect(later.isDone, isTrue);
          expect(fis.count(FisRoute.create), 2);
          rig.dispose();
        });
      });

      test('5.3 (A4): generate $status still recovers once with a new FID', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fis = FakeFis();
          final FirebaseInstallations a = rig.instance(fis);
          final String fid1 = _register(rig, fis, a);
          fis.answer(FisRoute.generate, FisAnswer.status(status));

          final Outcome<_IdToken> forced = Outcome<_IdToken>(
            a.getIdAndToken(forceRefresh: true),
          );
          async.flushMicrotasks();
          expect(forced.value.id, isNot(fid1));
          expect(fis.count(FisRoute.create), 2);
          expect(fis.count(FisRoute.generate), 2);
          expect(fis.requestsTo(FisRoute.generate).last.fid, forced.value.id);
          expect(rig.stored()!['fid'], forced.value.id);
          rig.dispose();
        });
      });

      test('5.3 (A4): generate $status twice in one call is '
          'installation-not-found', () {
        fakeAsync((FakeAsync async) {
          final R3Rig rig = R3Rig(async);
          final FakeFis fis = FakeFis();
          final FirebaseInstallations a = rig.instance(fis);
          _register(rig, fis, a);
          fis.answer(FisRoute.generate, FisAnswer.status(status), <FisAnswer>[
            FisAnswer.status(status),
          ]);

          final Outcome<String> forced = Outcome<String>(
            a.getToken(forceRefresh: true),
          );
          async.flushMicrotasks();
          expect(
            forced.error,
            isFisException('installation-not-found', httpStatus: status),
          );
          expect(fis.count(FisRoute.generate), 2);
          expect(fis.count(FisRoute.create), 2);
          rig.dispose();
        });
      });
    }
  });

  group('A5 marker owners', () {
    test("5.3 (A5): A's create succeeds after B took the marker over; the "
        "record has A's refresh token, B's 409 leaves it and does not feed "
        "B's backoff", () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fisA = FakeFis();
        final FakeFis fisB = FakeFis();
        final FirebaseInstallations a = rig.instance(fisA);
        final FirebaseInstallations b = rig.instance(fisB);
        final Completer<void> gateA = Completer<void>();
        final Completer<void> gateB = Completer<void>();
        fisA.answer(
          FisRoute.create,
          FisAnswer.create(
            refreshToken: 'refresh-a',
            token: 'auth-a',
            gate: gateA.future,
          ),
        );
        fisB.answer(FisRoute.create, FisAnswer.status(409, gate: gateB.future));

        final Outcome<String> fromA = Outcome<String>(a.getToken());
        async.flushMicrotasks();
        final String fid = fisA.requestsTo(FisRoute.create).single.fid!;

        // The clock moves 20 s without firing timers: A's request is still in flight, its marker stale.
        rig.clock.offset = const Duration(seconds: 20);
        final Outcome<String> fromB = Outcome<String>(b.getToken());
        async.flushMicrotasks();
        expect(fisB.requestsTo(FisRoute.create).single.fid, fid);

        gateA.complete();
        async.flushMicrotasks();
        expect(fromA.value, 'auth-a');
        final String? registeredByA = rig.storedText();
        final Map<String, Object?> stored = rig.stored()!;
        expect(stored['status'], 'registered');
        expect(stored['fid'], fid);
        expect(stored['refreshToken'], 'refresh-a');

        gateB.complete();
        async.flushMicrotasks();
        expect(fromB.value, 'auth-a');
        expect(rig.storedText(), registeredByA);
        expect(fisB.count(FisRoute.create), 1);

        final Outcome<String> forcedByB = Outcome<String>(
          b.getToken(forceRefresh: true),
        );
        async.flushMicrotasks();
        expect(forcedByB.error, isNull, reason: 'no backoff window');
        expect(forcedByB.isDone, isTrue);
        expect(fisB.count(FisRoute.generate), 1);
        rig.dispose();
      });
    });

    test('5.11 deadline: a caller joining a getToken at t = 50 s fails at '
        't = 110 s; the first caller still fails at 60 s', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final FirebaseInstallations a = rig.instance(fis);
        // Another tab holds a fresh registration marker and keeps re-stamping it.
        void stamp() => rig.put(
          r3Record(
            fid: r3Fid,
            status: 'registering',
            registrationStartedAt: rig.clock(),
            registrationOwner: 'tab-b.0',
          ),
        );
        void advanceTo(Duration target) {
          while (async.elapsed < target) {
            stamp();
            final Duration left = target - async.elapsed;
            async.elapse(
              left < const Duration(seconds: 5)
                  ? left
                  : const Duration(seconds: 5),
            );
          }
        }

        stamp();
        final Outcome<String> first = Outcome<String>(a.getToken());
        advanceTo(const Duration(seconds: 50));
        expect(first.isDone, isFalse);
        final Outcome<String> joined = Outcome<String>(a.getToken());

        advanceTo(const Duration(milliseconds: 59999));
        expect(first.isDone, isFalse);
        advanceTo(const Duration(seconds: 60));
        expect(first.error, isFisException('unavailable'));
        expect(joined.isDone, isFalse, reason: 'its own 60 s run to 110 s');

        advanceTo(const Duration(milliseconds: 109999));
        expect(joined.isDone, isFalse);
        advanceTo(const Duration(seconds: 110));
        expect(joined.error, isFisException('unavailable'));
        expect(fis.requests, isEmpty);
        rig.dispose();
      });
    });

    test('5.3 (A5): a fresh registration marker of a foreign owner means '
        'wait; its registration is then used without a request', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final FirebaseInstallations a = rig.instance(fis);
        rig.put(
          r3Record(
            fid: r3Fid,
            status: 'registering',
            registrationStartedAt: rig.clock(),
            registrationOwner: 'tab-b.0',
          ),
        );

        final Outcome<_IdToken> token = Outcome<_IdToken>(a.getIdAndToken());
        async.elapse(const Duration(seconds: 5));
        expect(token.isDone, isFalse);
        expect(fis.requests, isEmpty);

        rig.put(
          r3Record(
            fid: r3Fid,
            status: 'registered',
            refreshToken: 'refresh-b',
            token: 'auth-b',
            tokenCreatedAt: rig.clock(),
            tokenExpiresIn: const Duration(days: 7),
          ),
        );
        async.elapse(const Duration(milliseconds: 200));
        expect(token.value, (id: r3Fid, token: 'auth-b'));
        expect(fis.requests, isEmpty);
        rig.dispose();
      });
    });

    test('5.3 (A5): a fresh token marker of a foreign owner means wait; its '
        'token is then used without a request', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final FirebaseInstallations a = rig.instance(fis);
        final String fid = _register(rig, fis, a, expiresIn: '3700s');
        async.elapse(const Duration(seconds: 101));
        final Map<String, Object?> marked = rig.stored()!
          ..['tokenRequestStartedAt'] = rig.clock().millisecondsSinceEpoch
          ..['tokenRequestOwner'] = 'tab-b.3';
        rig.put(jsonEncode(marked));

        final Outcome<String> token = Outcome<String>(a.getToken());
        async.elapse(const Duration(seconds: 5));
        expect(token.isDone, isFalse);
        expect(fis.count(FisRoute.generate), 0);

        rig.put(
          r3Record(
            fid: fid,
            status: 'registered',
            refreshToken: 'refresh-a',
            token: 'auth-b',
            tokenCreatedAt: rig.clock(),
            tokenExpiresIn: const Duration(days: 7),
          ),
        );
        async.elapse(const Duration(milliseconds: 200));
        expect(token.value, 'auth-b');
        expect(fis.count(FisRoute.generate), 0);
        rig.dispose();
      });
    });

    /// Starts A's create with [answer] held by a gate, then lets a foreign owner take the marker over;
    /// returns the token call, the gate and the record the foreign owner wrote.
    ({Outcome<String> token, Completer<void> gate, String foreign}) supersede(
      R3Rig rig,
      FakeFis fis,
      FirebaseInstallations a,
      int status,
    ) {
      final Completer<void> gate = Completer<void>();
      fis.answer(FisRoute.create, FisAnswer.status(status, gate: gate.future));
      final Outcome<String> token = Outcome<String>(a.getToken());
      rig.async.flushMicrotasks();
      final String fid = fis.requestsTo(FisRoute.create).single.fid!;
      final String foreign = r3Record(
        fid: fid,
        status: 'registering',
        registrationStartedAt: rig.clock(),
        registrationOwner: 'tab-b.7',
      );
      rig.put(foreign);
      return (token: token, gate: gate, foreign: foreign);
    }

    test("5.3 (A5): a superseded holder's 409 does not change the record", () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final FirebaseInstallations a = rig.instance(fis);
        final (:Outcome<String> token, :Completer<void> gate, :String foreign) =
            supersede(rig, fis, a, 409);

        gate.complete();
        async.flushMicrotasks();
        expect(rig.storedText(), foreign);
        async.elapse(const Duration(seconds: 1));
        expect(rig.storedText(), foreign);
        expect(token.isDone, isFalse, reason: 'it waits for the fresh marker');
        expect(fis.count(FisRoute.create), 1);
        rig.dispose();
      });
    });

    test("5.3 (A5): a superseded holder's failure (429) does not change the "
        'record', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final FirebaseInstallations a = rig.instance(fis);
        final (:Outcome<String> token, :Completer<void> gate, :String foreign) =
            supersede(rig, fis, a, 429);

        gate.complete();
        async.flushMicrotasks();
        expect(
          token.error,
          isFisException('too-many-requests', httpStatus: 429),
        );
        expect(rig.storedText(), foreign);
        expect(fis.count(FisRoute.create), 1);
        rig.dispose();
      });
    });

    test("5.3 (A5): a superseded holder's re-stamp before its retry does not "
        'change the record', () {
      fakeAsync((FakeAsync async) {
        final R3Rig rig = R3Rig(async);
        final FakeFis fis = FakeFis();
        final FirebaseInstallations a = rig.instance(fis);
        final (:Outcome<String> token, :Completer<void> gate, :String foreign) =
            supersede(rig, fis, a, 503);

        gate.complete();
        async.flushMicrotasks();
        // The 503 is retried after 1 s; the re-stamp before it finds the foreign marker.
        async.elapse(const Duration(seconds: 1));
        expect(rig.storedText(), foreign);
        expect(fis.count(FisRoute.create), 1, reason: 'no retry sent');
        expect(token.isDone, isFalse, reason: 'it waits for the fresh marker');
        rig.dispose();
      });
    });
  });
}
