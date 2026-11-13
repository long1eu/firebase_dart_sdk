// Regression tests for the Low findings of reviews/review_followups.md that
// were fixed (L4, L6, L9, L10, L14). L13 is in core/transaction_runner_test.dart.

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/emulator_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_multi_db_component.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

/// A timestamp outside the valid range, as `const Timestamp(...)` yields in a
/// build without asserts.
class _InvalidTimestamp extends Fake implements Timestamp {
  _InvalidTimestamp(this.seconds, this.nanoseconds);

  @override
  final int seconds;
  @override
  final int nanoseconds;
}

class _FailingShutdownClient extends Mock implements FirestoreClient {
  @override
  Future<void> shutdown() => Future<void>.error(StateError('shutdown failed'));
}

void main() {
  test('L4: writing an out-of-range Timestamp is rejected with an ArgumentError',
      () {
    final UserDataConverter converter =
        UserDataConverter(DatabaseId.forProject('p'));
    for (final Timestamp invalid in <Timestamp>[
      _InvalidTimestamp(0, -1),
      _InvalidTimestamp(0, 1000000000),
      _InvalidTimestamp(253402300800, 0),
      _InvalidTimestamp(-62135596801, 0),
    ]) {
      expect(
          () => converter.parseSetData(<String, Object?>{'t': invalid}),
          throwsA(isA<ArgumentError>()),
          reason: '${invalid.seconds}/${invalid.nanoseconds}');
    }
  });

  test('L6: a Blob cannot be changed through the bytes it returns', () {
    final Blob blob = Blob(Uint8List.fromList(<int>[1, 2, 3]));
    final int hash = blob.hashCode;

    blob.bytes[0] = 9;

    expect(blob.bytes, <int>[1, 2, 3]);
    expect(blob.hashCode, hash);
    expect(blob, Blob(Uint8List.fromList(<int>[1, 2, 3])));
  });

  group('L9: copyWith(cacheSettings:) on settings that used the old flags', () {
    test('reports the mixed APIs instead of dropping persistenceEnabled', () {
      expect(
          () => FirestoreSettings(persistenceEnabled: false)
              .copyWith(cacheSettings: PersistentCacheSettings()),
          throwsStateError);
    });

    test('reports the mixed APIs instead of dropping cacheSizeBytes', () {
      expect(
          () => FirestoreSettings(cacheSizeBytes: 2 * 1024 * 1024)
              .copyWith(cacheSettings: PersistentCacheSettings()),
          throwsStateError);
    });

    test('still works on default settings and on settings with a cache', () {
      final FirestoreSettings memory = FirestoreSettings()
          .copyWith(cacheSettings: const MemoryCacheSettings());
      expect(memory.persistenceEnabled, isFalse);
      // The flags derived from the cache settings are not "mixed" flags.
      final FirestoreSettings persistent =
          memory.copyWith(cacheSettings: PersistentCacheSettings());
      expect(persistent.persistenceEnabled, isTrue);
      expect(memory.copyWith(host: 'localhost').persistenceEnabled, isFalse);
    });
  });

  test('L10: an empty sub falls back to user_id for the user, as for the token',
      () async {
    final EmulatorCredentialsProvider provider =
        EmulatorCredentialsProvider.forMockUserToken(
            <String, Object?>{'sub': '', 'user_id': 'alice'}, 'p');
    expect(await provider.onChange.first, User('alice'));
  });

  test('L14: a failing shutdown on app deletion is not an unhandled error',
      () async {
    final List<Object> unhandled = <Object>[];
    await runZonedGuarded(() async {
      final FirebaseApp app = FirebaseApp.withOptions(
        const FirebaseOptions(
            apiKey: 'key', applicationId: 'appId', projectId: 'p'),
        dependencies: null,
        name: 'reviewDeleteAppShutdownFails',
      );
      final Firestore firestore = FirestoreInternal.create(DatabaseId.forProject('p'), app,
          _FailingShutdownClient(), TaskScheduler('test'));
      FirestoreMultiDbComponent.register(
          app, DatabaseId.defaultDatabaseId, firestore);

      app.delete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (Object error, StackTrace stackTrace) => unhandled.add(error));

    expect(unhandled, isEmpty);
  });
}
