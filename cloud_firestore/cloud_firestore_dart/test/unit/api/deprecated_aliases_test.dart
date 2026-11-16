// The names of 0.1 that 0.2 keeps as deprecated aliases (see docs/api_migration_0_2.md): `Firestore` and
// `FirestoreSettings`, in the main library and in Firestore Lite. This file is the only place that is allowed to
// use them.
// ignore_for_file: deprecated_member_use_from_same_package, deprecated_member_use

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/lite.dart' as lite;
import 'package:test/test.dart';

import '../../util/test_hygiene.dart';

void main() {
  checkTestsLeaveNothingBehind();

  group('main library', () {
    test('Firestore is FirebaseFirestore', () {
      expect(Firestore, FirebaseFirestore);
      expect(identical(Firestore.instanceFor, FirebaseFirestore.instanceFor),
          isTrue);
      expect(identical(Firestore.setLogLevel, FirebaseFirestore.setLogLevel),
          isTrue);
    });

    test('FirestoreSettings is Settings', () {
      expect(FirestoreSettings, Settings);
      final FirestoreSettings settings = FirestoreSettings(
        persistenceEnabled: false,
      );
      expect(settings, isA<Settings>());
      expect(settings, Settings(persistenceEnabled: false));
      expect(FirestoreSettings.defaultHost, Settings.defaultHost);
    });
  });

  group('Firestore Lite', () {
    test('Firestore is FirebaseFirestore', () {
      expect(lite.Firestore, lite.FirebaseFirestore);
    });

    test('FirestoreSettings is Settings', () {
      expect(lite.FirestoreSettings, lite.Settings);
      expect(lite.FirestoreSettings(), isA<lite.Settings>());
    });
  });

  test('ServerTimestampBehavior is exported from the library', () {
    expect(ServerTimestampBehavior.values, hasLength(3));
  });
}
