// An app deleted and created again on the Dart core of this package (the
// core of Linux), which deletes the firebase_app_dart app with the
// FlutterFire app.
//
// The safety group asserts the property: with an emulator set, or
// persistence turned off, before the delete, an app created again with
// another apiKey and the same databaseURL gets no client without that
// setting. Every path throws the StateError of DartFirebaseDatabase.forApp
// and DartFirebaseDatabase.client instead; no client is created after the
// delete.

import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:firebase_database_dart_platform/src/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'recreated_app_invariant.dart';
import 'recreated_app_other_options_cases.dart';
import 'recreated_app_pinned_cases.dart';
import 'recreated_app_pinned_support.dart';

void main() {
  registerForTests();
  checkClientsAfterEveryTest();

  test('the Dart core is in place', () {
    expect(FirebasePlatform.instance, isA<LinuxFirebaseCore>());
  });

  for (final BeforeDelete setting in BeforeDelete.values) {
    group('safety: ${setting.name} before the delete', () {
      /// The client of the cached object, created before the delete.
      final String first = setting == BeforeDelete.emulator
          ? 'null|localhost:9000|memory'
          : 'null|null|memory';

      /// App [name] with [options], its cached object set up with [setting],
      /// used, deleted, created again with [otherKey] (the same databaseURL,
      /// another apiKey).
      Future<Recreated> setUpK(String name) {
        Future<Recreated> run() => recreate(
          name,
          otherKey,
          beforeUse: setting == BeforeDelete.emulator
              ? emulator9000
              : persistenceOff,
        );
        return setting == BeforeDelete.persistenceOff
            ? withPersistenceFactory(run)
            : run();
      }

      test('K1 other apiKey, same databaseURL: instanceFor(app: again, '
          'databaseURL: the same URL) throws, no new client', () async {
        final Recreated r = await setUpK('k1-${setting.name}');

        expect(
          () => FirebaseDatabase.instanceFor(
            app: r.again,
            databaseURL: databaseUrl,
          ).ref('a'),
          throwsStateError,
        );
        expect(hosts(), <String>[first]);
      });

      test('K2 other apiKey, same databaseURL: clientFor(again) throws, no '
          'new client', () async {
        final Recreated r = await setUpK('k2-${setting.name}');

        expect(() => FirebaseDatabaseDart.clientFor(r.again), throwsStateError);
        expect(
          () =>
              FirebaseDatabaseDart.clientFor(r.again, databaseURL: databaseUrl),
          throwsStateError,
        );
        expect(hosts(), <String>[first]);
      });

      test('K3 other apiKey, same databaseURL: clientFor(old app object) '
          'throws, no new client', () async {
        final Recreated r = await setUpK('k3-${setting.name}');

        expect(() => FirebaseDatabaseDart.clientFor(r.old), throwsStateError);
        expect(hosts(), <String>[first]);
      });

      test('K0 the cached object throws, no new client', () async {
        final Recreated r = await setUpK('k0-${setting.name}');

        await expectLater(r.database.goOnline(), throwsStateError);
        expect(hosts(), <String>[first]);
      });
    });
  }
}
