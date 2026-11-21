// FirebaseUserAuth.setStorage: moving the session to another storage (setPersistence of the JS SDK).

import 'dart:async';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late FakeBackend backend;
  late InMemoryAuthStorage first;
  late FirebaseUserAuth auth;
  const String key = 'firebase_auth_providers_dart:$apiKey';

  setUp(() {
    backend = FakeBackend();
    first = InMemoryAuthStorage();
    auth = backend.create(storage: first);
  });

  tearDown(() => auth.dispose());

  test('moves the session and deletes it from the old storage', () async {
    await auth.signInAnonymously();
    final String? stored = first.read(key);
    expect(stored, isNotNull);

    final InMemoryAuthStorage second = InMemoryAuthStorage();
    await auth.setStorage(second);
    expect(second.read(key), stored);
    expect(first.read(key), isNull);

    await auth.signOut();
    expect(second.read(key), isNull);
  });

  test('later session changes go to the new storage only', () async {
    final InMemoryAuthStorage second = InMemoryAuthStorage();
    await auth.setStorage(second);
    expect(second.read(key), isNull);
    await auth.signInAnonymously();
    expect(second.read(key), isNotNull);
    expect(first.read(key), isNull);
  });

  test('a new instance restores the session from the new storage', () async {
    await auth.signInAnonymously();
    final InMemoryAuthStorage second = InMemoryAuthStorage();
    await auth.setStorage(second);
    final FirebaseUserAuth again = backend.create(storage: second);
    addTearDown(again.dispose);
    await again.restore();
    expect(again.currentUser?.uid, auth.currentUser!.uid);
  });

  test('a failed write to the new storage changes nothing', () async {
    await auth.signInAnonymously();
    final String? stored = first.read(key);
    await expectLater(
      auth.setStorage(_FailingStorage()),
      throwsA(isA<StateError>()),
    );
    expect(first.read(key), stored);
    await auth.signOut();
    expect(first.read(key), isNull, reason: 'the old storage is still in use');
  });

  test(
    'waits for a restore in progress and moves the restored session',
    () async {
      await auth.signInAnonymously();
      final String uid = auth.currentUser!.uid;
      final _SlowStorage slow = _SlowStorage(first.read(key));
      final FirebaseUserAuth restored = backend.create(storage: slow);
      addTearDown(restored.dispose);
      final Future<void> restoring = restored.restore();
      final InMemoryAuthStorage second = InMemoryAuthStorage();
      final Future<void> moving = restored.setStorage(second);
      slow.release.complete();
      await Future.wait(<Future<void>>[restoring, moving]);
      expect(restored.currentUser?.uid, uid);
      expect(second.read(key), isNotNull);
      expect(slow.value, isNull);
    },
  );

  test('a sign-in during the move ends up in the new storage', () async {
    await auth.signInAnonymously();
    final _GatedStorage second = _GatedStorage();
    final Future<void> moving = auth.setStorage(second);
    await pumpEventQueue();
    // The first write to the new storage is in flight; a new session starts.
    await auth.createUserWithEmailAndPassword(
      email: 'b@example.com',
      password: 'secret1',
    );
    second.gate.complete();
    await moving;
    expect(second.values.last, contains('uid-of-b@example.com'));
    expect(first.read(key), isNull);
  });

  test('the same storage is a no-op', () async {
    await auth.signInAnonymously();
    final String? stored = first.read(key);
    await auth.setStorage(first);
    expect(first.read(key), stored);
  });

  test('throws after dispose', () async {
    await auth.dispose();
    expect(() => auth.setStorage(InMemoryAuthStorage()), throwsStateError);
  });
}

class _FailingStorage implements AuthStorage {
  @override
  String? read(String key) => null;

  @override
  void write(String key, String? value) => throw StateError('read-only');
}

/// Holds one value; its read waits for [release].
class _SlowStorage implements AuthStorage {
  _SlowStorage(this.value);

  String? value;
  final Completer<void> release = Completer<void>();

  @override
  Future<String?> read(String key) async {
    await release.future;
    return value;
  }

  @override
  void write(String key, String? value) => this.value = value;
}

/// Records its writes; the first one waits for [gate].
class _GatedStorage implements AuthStorage {
  final List<String?> values = <String?>[];
  final Completer<void> gate = Completer<void>();

  @override
  String? read(String key) => values.isEmpty ? null : values.last;

  @override
  Future<void> write(String key, String? value) async {
    if (values.isEmpty) {
      values.add(value);
      await gate.future;
      return;
    }
    values.add(value);
  }
}
