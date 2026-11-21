// The registration, in a file of its own: it must run before anything else
// installs the package.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    show FirebasePlatform, MethodChannelFirebase;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_dart_platform/firebase_storage_dart_platform.dart';
import 'package:firebase_storage_dart_platform/src/core.dart';
import 'package:firebase_storage_platform_interface/firebase_storage_platform_interface.dart'
    show FirebaseStoragePlatform;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';
import 'harness.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'registerWith on Linux under flutter test leaves firebase_core alone; '
    'use installs the Dart core; use after the first request throws',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(FirebaseStorageDart.isRegistered, isFalse);

      FirebaseStorageDart.registerWith();
      expect(FirebaseStorageDart.isRegistered, isTrue);
      expect(FirebaseStoragePlatform.instance, isA<DartFirebaseStorage>());
      expect(FirebasePlatform.instance, isA<MethodChannelFirebase>());

      final FakeBackend fake = FakeBackend();
      FirebaseStorageDart.use(httpClient: fake.client);
      expect(FirebasePlatform.instance, isA<LinuxFirebaseCore>());
      final FirebasePlatform core = FirebasePlatform.instance;
      installCoreIfNeeded(force: true);
      expect(FirebasePlatform.instance, same(core), reason: 'kept, with apps');

      final FirebaseApp app = await Firebase.initializeApp(options: options);
      fake.put(bucket, 'a.txt', <int>[1]);
      await FirebaseStorage.instanceFor(app: app).ref('a.txt').getMetadata();
      expect(fake.requests, hasLength(1));
      expect(FirebaseStorageDart.use, throwsStateError);
    },
  );
}
