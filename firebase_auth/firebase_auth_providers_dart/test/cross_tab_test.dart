// FirebaseUserAuth following the changes other tabs make to the stored session (an
// ObservableAuthStorage): sign-out, another user, new tokens and data of the same user, no write
// back, the check before an update is stored, and the life of the subscription. The tabs share a
// fake storage that tells each tab about the writes of the others.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fakes.dart';
import 'harness.dart';

const String _key = 'firebase_auth_providers_dart:$apiKey';

/// One browser storage shared by tabs; [tab] makes the storage object of one tab.
class _SharedStorage {
  final Map<String, String> values = <String, String>{};
  final List<_Tab> _tabs = <_Tab>[];

  /// While false, the tabs are not told about changes; [deliver] tells them later.
  bool delivering = true;
  final List<(_Tab, String)> _held = <(_Tab, String)>[];

  _Tab tab() {
    final _Tab tab = _Tab(this);
    _tabs.add(tab);
    return tab;
  }

  /// A write made by something that is not one of the tabs (another tab's raw code).
  void writeElsewhere(String key, String? value) {
    _store(key, value);
    _notify(null, key);
  }

  void deliver() {
    delivering = true;
    final List<(_Tab, String)> held = List<(_Tab, String)>.of(_held);
    _held.clear();
    for (final (_Tab tab, String key) in held) {
      tab._emit(key);
    }
  }

  void _store(String key, String? value) {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  void _notify(_Tab? writer, String key) {
    for (final _Tab tab in _tabs) {
      if (identical(tab, writer)) {
        continue;
      }
      if (delivering) {
        tab._emit(key);
      } else {
        _held.add((tab, key));
      }
    }
  }
}

/// A storage that does not report changes, counting its reads.
class _CountingStorage extends InMemoryAuthStorage {
  int reads = 0;
  int writes = 0;

  @override
  String? read(String key) {
    reads++;
    return super.read(key);
  }

  @override
  void write(String key, String? value) {
    writes++;
    super.write(key, value);
  }
}

class _Tab implements ObservableAuthStorage {
  _Tab(this._shared);

  final _SharedStorage _shared;
  final Map<String, Set<MultiStreamController<void>>> _listeners =
      <String, Set<MultiStreamController<void>>>{};
  int reads = 0;
  int writes = 0;
  StateError? readError;

  int get listeners => _listeners.values.fold(
    0,
    (int sum, Set<MultiStreamController<void>> set) => sum + set.length,
  );

  /// Tells this tab's listeners that [key] changed, as a storage that reports a rewrite may.
  void emitSpuriously(String key) => _emit(key);

  /// While set, a read takes the value at once but answers only when it completes, like a slow
  /// read whose transaction started before the writes that follow it.
  Completer<void>? readGate;

  @override
  FutureOr<String?> read(String key) {
    reads++;
    final Completer<void>? gate = readGate;
    final String? value = _readNow(key);
    if (gate != null) {
      return gate.future.then((_) => value);
    }
    return value;
  }

  String? _readNow(String key) {
    final StateError? error = readError;
    if (error != null) {
      throw error;
    }
    return _shared.values[key];
  }

  /// While set, a write is applied only when it completes; reads made meanwhile see the old
  /// value (no read waits behind a write), so a test does not rely on a storage's queueing.
  Completer<void>? writeGate;

  @override
  FutureOr<void> write(String key, String? value) {
    writes++;
    final Completer<void>? gate = writeGate;
    if (gate != null) {
      return gate.future.then((_) => _apply(key, value));
    }
    _apply(key, value);
  }

  void _apply(String key, String? value) {
    _shared._store(key, value);
    _shared._notify(this, key);
  }

  @override
  Stream<void> changes(String key) =>
      Stream<void>.multi((MultiStreamController<void> controller) {
        _listeners
            .putIfAbsent(key, () => <MultiStreamController<void>>{})
            .add(controller);
        controller.onCancel = () => _listeners[key]?.remove(controller);
      });

  void _emit(String key) {
    for (final MultiStreamController<void> c
        in List<MultiStreamController<void>>.of(
          _listeners[key] ?? <MultiStreamController<void>>{},
        )) {
      c.add(null);
    }
  }
}

/// Lets the change events and the reads they start run.
Future<void> settle() async {
  for (int i = 0; i < 5; i++) {
    await pump();
  }
}

/// Waits until [tab] has started [count] writes.
Future<void> _untilWrites(_Tab tab, int count) async {
  for (int i = 0; i < 100 && tab.writes < count; i++) {
    await pump();
  }
  expect(tab.writes, count, reason: 'the write never started');
}

/// Waits until [tab] has started [count] reads.
Future<void> _untilReads(_Tab tab, int count) async {
  for (int i = 0; i < 100 && tab.reads < count; i++) {
    await pump();
  }
  expect(tab.reads, count, reason: 'the read before the write never started');
}

void main() {
  late FakeBackend backend;
  late _SharedStorage shared;
  late _Tab storageA;
  late _Tab storageB;
  late FirebaseUserAuth tabA;
  late FirebaseUserAuth tabB;

  setUp(() {
    backend = FakeBackend();
    shared = _SharedStorage();
    storageA = shared.tab();
    storageB = shared.tab();
    tabA = backend.create(storage: storageA);
    tabB = backend.create(storage: storageB);
  });

  tearDown(() async {
    await tabA.dispose();
    await tabB.dispose();
  });

  /// Signs in [email] in tab A and lets tab B take it over.
  Future<void> signInBoth(String email) async {
    await tabA.signInWithEmailAndPassword(email: email, password: 'pw');
    await settle();
    expect(tabB.uid, 'uid-of-$email');
  }

  group('another tab', () {
    test('signs out: signed out here, nothing written back', () async {
      await signInBoth('a@x.com');
      final List<AuthUser?> states = <AuthUser?>[];
      final List<AuthUser?> users = <AuthUser?>[];
      final List<String> tokens = <String>[];
      final List<AuthUser?> idTokens = <AuthUser?>[];
      tabB.authStateChanges().skip(1).listen(states.add);
      tabB.userChanges().listen(users.add);
      tabB.onTokenChanged.listen((AuthTokenChange c) => tokens.add(c.token));
      tabB.idTokenChanges().skip(1).listen(idTokens.add);
      await settle();
      final int writes = storageB.writes;

      await tabA.signOut();
      await settle();

      expect(tabB.currentUser, isNull);
      expect(tabB.refreshToken, isNull);
      expect(states, <AuthUser?>[null]);
      expect(users, <AuthUser?>[null]);
      expect(tokens, <String>['']);
      expect(idTokens, <AuthUser?>[null]);
      expect(storageB.writes, writes);
      expect(shared.values[_key], isNull);
    });

    test('signs in another user: that user here, without a write', () async {
      await signInBoth('a@x.com');
      final List<String?> states = <String?>[];
      final List<String> tokens = <String>[];
      tabB
          .authStateChanges()
          .skip(1)
          .listen((AuthUser? u) => states.add(u?.uid));
      tabB.onTokenChanged.listen((AuthTokenChange c) => tokens.add(c.token));
      await settle();
      final int writes = storageB.writes;

      await tabA.signInWithEmailAndPassword(email: 'b@x.com', password: 'pw');
      await settle();

      expect(tabB.uid, 'uid-of-b@x.com');
      expect(tabB.refreshToken, 'refresh:uid-of-b@x.com');
      expect(states, <String?>['uid-of-b@x.com']);
      // The ID token comes with the first refresh, as after a restore.
      expect(tokens, <String>['']);
      expect(storageB.writes, writes);
      // The first token of the new user is fetched with the stored refresh token.
      final String token = (await tabB.getAccessToken(
        forceRefresh: false,
      )).token;
      expect(GetTokenResult(token).claims['sub'], 'uid-of-b@x.com');
      expect(storageB.writes, writes);
    });

    test('a sign-in while signed out here is taken over', () async {
      final List<String?> states = <String?>[];
      tabB.authStateChanges().listen((AuthUser? u) => states.add(u?.uid));
      await settle();

      await tabA.signInAnonymously();
      await settle();

      expect(tabB.uid, 'anon-user');
      expect(states, <String?>[null, 'anon-user']);
      expect(storageB.writes, 0);
    });

    test('rotates the refresh token: taken over, the ID token stays', () async {
      await signInBoth('a@x.com');
      final String tokenB = (await tabB.getAccessToken(
        forceRefresh: false,
      )).token;
      final List<AuthUser?> states = <AuthUser?>[];
      final List<AuthUser?> users = <AuthUser?>[];
      tabB.authStateChanges().skip(1).listen(states.add);
      tabB.userChanges().listen(users.add);
      await settle();
      final int writes = storageB.writes;
      backend.on(
        'token',
        (Map<String, Object?> body) => jsonResponse(<String, Object?>{
          'id_token': idToken(
            'uid-of-a@x.com',
            expires: backend.clock.now.add(const Duration(hours: 1)),
            tag: 'rotation',
          ),
          'refresh_token': 'refresh:uid-of-a@x.com:rotated',
          'expires_in': '3600',
        }),
      );

      await tabA.getAccessToken(forceRefresh: true);
      await settle();

      expect(tabB.refreshToken, 'refresh:uid-of-a@x.com:rotated');
      expect((await tabB.getAccessToken(forceRefresh: false)).token, tokenB);
      expect(states, isEmpty);
      expect(users, isEmpty);
      expect(storageB.writes, writes);
    });

    test('changes the data of the same user: userChanges emits', () async {
      await signInBoth('a@x.com');
      final List<AuthUser?> states = <AuthUser?>[];
      final List<String?> names = <String?>[];
      tabB.authStateChanges().skip(1).listen(states.add);
      tabB.userChanges().listen((AuthUser? u) => names.add(u?.displayName));
      await settle();
      final int writes = storageB.writes;
      backend.on(
        'accounts:update',
        (Map<String, Object?> body) => jsonResponse(<String, Object?>{
          'localId': 'uid-of-a@x.com',
          'displayName': body['displayName'],
        }),
      );

      await tabA.updateProfile(displayName: 'Ada');
      await settle();

      expect(tabB.currentUser!.displayName, 'Ada');
      expect(names, <String?>['Ada']);
      expect(states, isEmpty);
      expect(storageB.writes, writes);
    });

    test('no write goes back and forth between the tabs', () async {
      await signInBoth('a@x.com');
      await tabA.signInWithEmailAndPassword(email: 'b@x.com', password: 'pw');
      await settle();
      await tabA.signOut();
      await settle();
      await tabA.signInAnonymously();
      await settle();
      final int writesA = storageA.writes;
      final int writesB = storageB.writes;
      final int readsA = storageA.reads;

      await settle();
      await settle();

      expect(writesA, 4);
      expect(writesB, 0);
      expect(storageA.writes, writesA);
      expect(storageB.writes, writesB);
      // Tab A heard nothing: tab B never wrote.
      expect(storageA.reads, readsA);
      expect(tabA.uid, 'anon-user');
      expect(tabB.uid, 'anon-user');
    });

    test('a value this class did not write is ignored', () async {
      await signInBoth('a@x.com');
      shared.writeElsewhere(_key, 'not a session');
      await settle();
      expect(tabB.uid, 'uid-of-a@x.com');
      expect(storageB.writes, 0);
    });

    test('the beforeAuthStateChanged callbacks do not run', () async {
      await signInBoth('a@x.com');
      int calls = 0;
      tabB.beforeAuthStateChanged((AuthUser? _) {
        calls++;
        throw StateError('blocked');
      });
      await tabA.signOut();
      await settle();
      expect(calls, 0);
      expect(tabB.currentUser, isNull);
    });

    test('a change that cannot be read leaves the state as it was', () async {
      await signInBoth('a@x.com');
      storageB.readError = StateError('storage refused');
      await tabA.signOut();
      await settle();
      expect(tabB.uid, 'uid-of-a@x.com');
      // The next change is read again.
      storageB.readError = null;
      await tabA.signInAnonymously();
      await settle();
      expect(tabB.uid, 'anon-user');
    });
  });

  group('this tab', () {
    test('a report of its own stored session changes nothing', () async {
      await tabB.signInAnonymously();
      final List<AuthUser?> users = <AuthUser?>[];
      final List<String> tokens = <String>[];
      tabB.userChanges().listen(users.add);
      tabB.onTokenChanged.listen((AuthTokenChange c) => tokens.add(c.token));
      final int writes = storageB.writes;

      storageB.emitSpuriously(_key);
      await settle();

      expect(tabB.uid, 'anon-user');
      expect(users, isEmpty);
      expect(tokens, isEmpty);
      expect(storageB.writes, writes);
    });

    test(
      'an update does not write over a sign-out it has not heard of yet',
      () async {
        await signInBoth('a@x.com');
        shared.delivering = false;
        await tabA.signOut();
        backend.on(
          'token',
          (Map<String, Object?> body) => jsonResponse(<String, Object?>{
            'id_token': idToken(
              'uid-of-a@x.com',
              expires: backend.clock.now.add(const Duration(hours: 1)),
            ),
            'refresh_token': 'refresh:uid-of-a@x.com:rotated',
            'expires_in': '3600',
          }),
        );
        final int writes = storageB.writes;

        // A rotated refresh token would be stored: the storage holds a sign-out, which wins.
        await expectLater(
          tabB.getAccessToken(forceRefresh: true),
          throwsA(isA<FirebaseNoSignedInUserException>()),
        );

        expect(storageB.writes, writes);
        expect(shared.values[_key], isNull);
        expect(tabB.currentUser, isNull);
        shared.deliver();
        await settle();
        expect(tabB.currentUser, isNull);
        expect(storageB.writes, writes);
      },
    );

    test(
      'an update does not write over another user it has not heard of',
      () async {
        await signInBoth('a@x.com');
        shared.delivering = false;
        await tabA.signInWithEmailAndPassword(email: 'b@x.com', password: 'pw');
        final List<String?> states = <String?>[];
        tabB
            .authStateChanges()
            .skip(1)
            .listen((AuthUser? u) => states.add(u?.uid));
        await settle();
        backend.accounts['uid-of-a@x.com'] = <String, Object?>{
          ...?backend.accounts['uid-of-a@x.com'],
          'displayName': 'Ada',
        };
        final int writes = storageB.writes;

        await tabB.reload();
        await settle();

        expect(storageB.writes, writes);
        expect(tabB.uid, 'uid-of-b@x.com');
        expect(states, <String?>['uid-of-b@x.com']);
        expect(shared.values[_key], contains('uid-of-b@x.com'));
        shared.deliver();
      },
    );

    test('an update of the same user is still stored', () async {
      await signInBoth('a@x.com');
      backend.accounts['uid-of-a@x.com'] = <String, Object?>{
        ...?backend.accounts['uid-of-a@x.com'],
        'displayName': 'Ada',
      };
      final int writes = storageB.writes;
      await tabB.reload();
      expect(storageB.writes, writes + 1);
      expect(shared.values[_key], contains('Ada'));
      await settle();
      expect(tabA.currentUser!.displayName, 'Ada');
    });

    test(
      'an operation of the previous user does not land after a switch',
      () async {
        await signInBoth('a@x.com');
        await tabB.getAccessToken(forceRefresh: false);
        final Completer<http.Response> lookup = Completer<http.Response>();
        backend.on(
          'accounts:lookup',
          (Map<String, Object?> body) => lookup.future,
        );
        final Future<void> reloading = tabB.reload();
        await settle();

        await tabA.signOut();
        await settle();
        expect(tabB.currentUser, isNull);
        lookup.complete(
          jsonResponse(<String, Object?>{
            'users': <Object?>[
              <String, Object?>{
                'localId': 'uid-of-a@x.com',
                'displayName': 'Late',
              },
            ],
          }),
        );
        await reloading.then<void>((_) {}, onError: (Object _) {});

        expect(tabB.currentUser, isNull);
        expect(shared.values[_key], isNull);
      },
    );
  });

  // _setSession reads an observable storage before it stores an update of the session. Whatever
  // runs while that read is pending and replaces the session owns the storage afterwards.
  group('during the read before an update is stored', () {
    late Completer<void> gate;
    late int readsBefore;
    late Future<void> refreshing;

    /// Signs in in tab A, then starts a refresh that rotates the refresh token and holds the read
    /// it makes before storing it.
    Future<void> holdRotation() async {
      await tabA.signInWithEmailAndPassword(email: 'a@x.com', password: 'pw');
      await settle();
      backend.on(
        'token',
        (Map<String, Object?> body) => jsonResponse(<String, Object?>{
          'id_token': idToken(
            'uid-of-a@x.com',
            expires: backend.clock.now.add(const Duration(hours: 1)),
            tag: 'rotation',
          ),
          'refresh_token': 'refresh:uid-of-a@x.com:rotated',
          'expires_in': '3600',
        }),
      );
      gate = Completer<void>();
      storageA.readGate = gate;
      readsBefore = storageA.reads;
      refreshing = tabA
          .getAccessToken(forceRefresh: true)
          .then<void>((_) {}, onError: (Object _) {});
      await _untilReads(storageA, readsBefore + 1);
    }

    test('a sign-out keeps the storage empty', () async {
      await holdRotation();
      await tabA.signOut();
      expect(shared.values[_key], isNull);
      final int writes = storageA.writes;

      storageA.readGate = null;
      gate.complete();
      await refreshing;
      await settle();

      expect(shared.values[_key], isNull);
      expect(storageA.writes, writes);
      expect(tabA.currentUser, isNull);
    });

    test('a sign-in of another user keeps that user stored', () async {
      await holdRotation();
      await tabA.signInWithEmailAndPassword(email: 'b@x.com', password: 'pw');
      final String? stored = shared.values[_key];
      expect(stored, contains('uid-of-b@x.com'));
      final int writes = storageA.writes;

      storageA.readGate = null;
      gate.complete();
      await refreshing;
      await settle();

      expect(shared.values[_key], stored);
      expect(storageA.writes, writes);
      expect(tabA.uid, 'uid-of-b@x.com');
    });

    test('dispose writes nothing', () async {
      await holdRotation();
      final String? stored = shared.values[_key];
      final int writes = storageA.writes;
      await tabA.dispose();

      storageA.readGate = null;
      gate.complete();
      await refreshing;
      await settle();

      expect(storageA.writes, writes);
      expect(shared.values[_key], stored);
      expect(shared.values[_key], isNot(contains('rotated')));
    });
  });

  // _adoptStoredSession reads what another tab stored. A local change made while that read is
  // pending is newer than what the read returns.
  group('during the read that follows another tab', () {
    test(
      'a local sign-out is not undone by the value read before it',
      () async {
        await signInBoth('a@x.com');
        final Completer<void> gate = Completer<void>();
        storageB.readGate = gate;
        final int reads = storageB.reads;
        await tabA.signInWithEmailAndPassword(email: 'b@x.com', password: 'pw');
        await _untilReads(storageB, reads + 1);

        await tabB.signOut();
        expect(shared.values[_key], isNull);
        storageB.readGate = null;
        gate.complete();
        await settle();

        expect(tabB.currentUser, isNull);
        expect(shared.values[_key], isNull);
      },
    );

    test(
      'a local sign-in is not cancelled by the sign-out read before it',
      () async {
        await signInBoth('a@x.com');
        final Completer<void> gate = Completer<void>();
        storageB.readGate = gate;
        final int reads = storageB.reads;
        await tabA.signOut();
        await _untilReads(storageB, reads + 1);

        await tabB.signInWithEmailAndPassword(email: 'c@x.com', password: 'pw');
        expect(shared.values[_key], contains('uid-of-c@x.com'));
        storageB.readGate = null;
        gate.complete();
        await settle();

        expect(tabB.uid, 'uid-of-c@x.com');
        expect(shared.values[_key], contains('uid-of-c@x.com'));
      },
    );
  });

  test(
    'a storage that does not report changes is not read before an update',
    () async {
      final _CountingStorage plain = _CountingStorage();
      final FirebaseUserAuth auth = backend.create(storage: plain);
      addTearDown(auth.dispose);
      await auth.signInWithEmailAndPassword(email: 'a@x.com', password: 'pw');
      backend.accounts['uid-of-a@x.com'] = <String, Object?>{
        ...?backend.accounts['uid-of-a@x.com'],
        'displayName': 'Ada',
      };
      final int writes = plain.writes;

      await auth.reload();

      expect(plain.writes, writes + 1);
      expect(plain.reads, 0);
    },
  );

  // A change event that arrives while a write of this instance is pending: the storage still holds
  // the value before that write, and the fake does not order the read behind the write.
  group('while a local write is pending', () {
    test('a sign-out is not undone by the session still stored', () async {
      await signInBoth('a@x.com');
      final Completer<void> gate = Completer<void>();
      storageB.writeGate = gate;
      final int writes = storageB.writes;
      final Future<void> signingOut = tabB.signOut();
      await _untilWrites(storageB, writes + 1);
      expect(shared.values[_key], contains('uid-of-a@x.com'));

      storageB.emitSpuriously(_key);
      await settle();
      expect(tabB.currentUser, isNull);

      storageB.writeGate = null;
      gate.complete();
      await signingOut;
      await settle();

      expect(tabB.currentUser, isNull);
      expect(shared.values[_key], isNull);
    });

    test('a sign-in is not replaced by the session still stored', () async {
      await signInBoth('a@x.com');
      final Completer<void> gate = Completer<void>();
      storageB.writeGate = gate;
      final int writes = storageB.writes;
      final Future<void> signingIn = tabB.signInWithEmailAndPassword(
        email: 'c@x.com',
        password: 'pw',
      );
      await _untilWrites(storageB, writes + 1);
      expect(shared.values[_key], contains('uid-of-a@x.com'));

      storageB.emitSpuriously(_key);
      await settle();
      expect(tabB.uid, 'uid-of-c@x.com');

      storageB.writeGate = null;
      gate.complete();
      await signingIn;
      await settle();

      expect(tabB.uid, 'uid-of-c@x.com');
      expect(shared.values[_key], contains('uid-of-c@x.com'));
    });
  });

  group('the subscription', () {
    test('one listener per instance while it uses the storage', () async {
      expect(storageA.listeners, 1);
      expect(storageB.listeners, 1);
    });

    test('ends at dispose', () async {
      await tabB.dispose();
      expect(storageB.listeners, 0);
    });

    test(
      'moves with setStorage, and the old storage is no longer followed',
      () async {
        await signInBoth('a@x.com');
        final _SharedStorage other = _SharedStorage();
        final _Tab moved = other.tab();
        await tabB.setStorage(moved);
        expect(storageB.listeners, 0);
        expect(moved.listeners, 1);
        expect(tabB.uid, 'uid-of-a@x.com');
        // The move deleted the session from the shared storage, which tab A follows (as in JS,
        // where setPersistence removes the user from the persistence it leaves).
        await settle();
        expect(tabA.currentUser, isNull);

        // A sign-in in the old storage is not followed any more.
        shared.writeElsewhere(
          _key,
          '{"version":2,"uid":"u2","refreshToken":"r2"}',
        );
        await settle();
        expect(tabB.uid, 'uid-of-a@x.com');
        expect(tabA.uid, 'u2');

        // A change in the new storage is followed.
        other.writeElsewhere(_key, null);
        await settle();
        expect(tabB.currentUser, isNull);
      },
    );
  });
}
