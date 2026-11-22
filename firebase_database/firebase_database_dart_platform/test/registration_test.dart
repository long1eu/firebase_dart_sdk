// The registration, in a file of its own: it must run before anything else
// installs the package.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    show FirebasePlatform, MethodChannelFirebase;
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:firebase_database_dart_platform/src/core.dart';
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart'
    show DatabasePlatform;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  late FakeDatabaseServer fake;

  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    fake = FakeDatabaseServer();
    DartFirebaseDatabase.clientFactory = (app, settings) =>
        databaseWithFakeServer(
          app,
          fake,
          logger: settings.logger,
          reconnectDelay: reconnectDelay,
        );
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
    DartFirebaseDatabase.clientFactory = createClient;
  });

  test('isRegistered is false before registration', () {
    expect(FirebaseDatabaseDart.isRegistered, isFalse);
  });

  test('registerWith under flutter test registers the package and leaves '
      'firebase_core alone', () {
    FirebaseDatabaseDart.registerWith();

    expect(FirebaseDatabaseDart.isRegistered, isTrue);
    expect(DatabasePlatform.instance, isA<DartFirebaseDatabase>());
    expect(DatabasePlatform.instance.app, isNull);
    expect(FirebasePlatform.instance, isA<MethodChannelFirebase>());
  });

  test('use installs the Dart core once and keeps the registered instance', () {
    final DatabasePlatform registered = DatabasePlatform.instance;

    FirebaseDatabaseDart.use(useDartCore: true);
    final FirebasePlatform core = FirebasePlatform.instance;
    FirebaseDatabaseDart.use(useDartCore: true);

    expect(core, isA<LinuxFirebaseCore>());
    expect(
      FirebasePlatform.instance,
      same(core),
      reason: 'kept, with its apps',
    );
    expect(DatabasePlatform.instance, same(registered));
  });

  test('use(useDartCore: true) keeps a core another package installed', () {
    final FirebasePlatform dartCore = FirebasePlatform.instance;
    final FirebasePlatform foreign = _ForeignCore();
    FirebasePlatform.instance = foreign;
    addTearDown(() => FirebasePlatform.instance = dartCore);

    FirebaseDatabaseDart.use(useDartCore: true);

    expect(FirebasePlatform.instance, same(foreign));
  });

  test('the official FirebaseDatabase runs on the client', () async {
    final FirebaseApp app = await Firebase.initializeApp(options: options);

    final Future<void> write = FirebaseDatabase.instanceFor(
      app: app,
    ).ref('a').set(1);
    await settle();
    fake.ackLastWrite();
    await write;

    expect(fake.requests, contains('p /a'));
  });

  test('use after the first client throws a StateError', () {
    expect(DartFirebaseDatabase.anyStarted, isTrue);
    expect(FirebaseDatabaseDart.use, throwsStateError);
    expect(FirebaseDatabaseDart.registerWith, throwsStateError);
  });
}

/// A `firebase_core` implementation of another package.
class _ForeignCore extends FirebasePlatform {}
