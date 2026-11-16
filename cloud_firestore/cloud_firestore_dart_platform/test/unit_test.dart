// Tests that need no emulator: registration, the Dart core, settings, the
// value codec and the error mapping.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as fs;
import 'package:cloud_firestore_dart_platform/cloud_firestore_dart_platform.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    show FieldValueFactoryPlatform, FirebaseFirestorePlatform;
import 'package:cloud_firestore_dart_platform/src/errors.dart';
import 'package:cloud_firestore_dart_platform/src/value_codec.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    show FirebasePlatform;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const FirebaseOptions _options = FirebaseOptions(
  apiKey: 'test-api-key',
  appId: '1:1:web:1',
  messagingSenderId: '1',
  projectId: 'demo-unit',
);

void main() {
  setUpAll(() {
    // Pretend to be on Linux, where registerWith also installs the Dart core.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    CloudFirestoreDart.registerWith();
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('registration', () {
    test(
      'registerWith on Linux installs the Firestore and core implementations',
      () {
        expect(CloudFirestoreDart.isRegistered, isTrue);
        expect(
          FirebaseFirestorePlatform.instance,
          isA<DartFirebaseFirestore>(),
        );
        expect(
          FieldValueFactoryPlatform.instance,
          isA<DartFieldValueFactory>(),
        );
        expect(FirebasePlatform.instance, isA<DartFirebaseCore>());
      },
    );

    test('FirebaseFirestore.instanceFor uses this package', () async {
      final FirebaseApp app = await Firebase.initializeApp(
        name: 'registration',
        options: _options,
      );
      final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
        app: app,
      );
      expect(firestore.collection('a').doc('b').path, 'a/b');
      expect(FieldValue.serverTimestamp(), isA<FieldValue>());
    });
  });

  group('DartFirebaseCore', () {
    test(
      'initializeApp needs options and refuses other options for a name',
      () async {
        await expectLater(
          Firebase.initializeApp(name: 'no-options'),
          throwsA(
            isA<FirebaseException>().having(
              (FirebaseException e) => e.code,
              'code',
              'no-options',
            ),
          ),
        );
        final FirebaseApp app = await Firebase.initializeApp(
          name: 'core',
          options: _options,
        );
        final FirebaseApp again = await Firebase.initializeApp(
          name: 'core',
          options: _options,
        );
        expect(again.name, app.name);
        await expectLater(
          Firebase.initializeApp(
            name: 'core',
            options: const FirebaseOptions(
              apiKey: 'other',
              appId: '1:1:web:1',
              messagingSenderId: '1',
              projectId: 'demo-unit',
            ),
          ),
          throwsA(
            isA<FirebaseException>().having(
              (FirebaseException e) => e.code,
              'code',
              'duplicate-app',
            ),
          ),
        );
        expect(Firebase.apps.map((FirebaseApp a) => a.name), contains('core'));
        await app.delete();
        expect(
          () => Firebase.app('core'),
          throwsA(
            isA<FirebaseException>().having(
              (FirebaseException e) => e.code,
              'code',
              'no-app',
            ),
          ),
        );
      },
    );

    test('maps the options to firebase_app_dart', () {
      final dart_app.FirebaseOptions options = dartOptionsOf(_options);
      expect(options.apiKey, 'test-api-key');
      expect(options.appId, '1:1:web:1');
      expect(options.messagingSenderId, '1');
      expect(options.projectId, 'demo-unit');
      expect(options.databaseURL, isNull);
    });
  });

  group('settings', () {
    test('host with a port, as useFirestoreEmulator sets it', () {
      final fs.Settings settings = DartFirebaseFirestore.dartSettingsOf(
        const Settings(host: '127.0.0.1:8144', sslEnabled: false),
      );
      expect(settings.host, '127.0.0.1');
      expect(settings.port, 8144);
      expect(settings.sslEnabled, isFalse);
    });

    test('defaults and unlimited cache', () {
      final fs.Settings settings = DartFirebaseFirestore.dartSettingsOf(
        const Settings(cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED),
      );
      expect(settings.host, fs.Settings.defaultHost);
      expect(settings.port, fs.Settings.defaultPort);
      expect(settings.sslEnabled, isTrue);
      expect(settings.cacheSizeBytes, fs.Settings.cacheSizeUnlimited);
    });

    test('a host without a port keeps the default port', () {
      final fs.Settings settings = DartFirebaseFirestore.dartSettingsOf(
        const Settings(host: 'firestore.example.com'),
      );
      expect(settings.host, 'firestore.example.com');
      expect(settings.port, fs.Settings.defaultPort);
    });
  });

  group('value codec', () {
    test('encodes the platform interface types', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final Object? encoded = ValueCodec.encode(<String, Object?>{
        'timestamp': Timestamp(10, 20),
        'date': DateTime.utc(2026, 11, 16),
        'geo': const GeoPoint(1.5, -2.5),
        'blob': Blob(bytes),
        'vector': const VectorValue(<double>[0.5, 1]),
        'list': <Object?>[1, 'two', null],
        'nested': <String, Object?>{'a': true},
      });
      expect(encoded, <String, Object?>{
        'timestamp': const fs.Timestamp(10, 20),
        'date': fs.Timestamp.fromDate(DateTime.utc(2026, 11, 16)),
        'geo': fs.GeoPoint(1.5, -2.5),
        'blob': fs.Blob(bytes),
        'vector': fs.VectorValue(<double>[0.5, 1]),
        'list': <Object?>[1, 'two', null],
        'nested': <String, Object?>{'a': true},
      });
    });

    test('rejects types Firestore cannot store', () {
      expect(() => ValueCodec.encode(Object()), throwsArgumentError);
      expect(
        () => ValueCodec.encode(<Object, Object?>{1: 'a'}),
        throwsArgumentError,
      );
    });

    test(
      'encodes FieldValue sentinels to cloud_firestore_dart FieldValues',
      () {
        expect(ValueCodec.encode(FieldValue.delete()), isA<fs.FieldValue>());
        expect(
          ValueCodec.encode(FieldValue.increment(2)),
          isA<fs.FieldValue>(),
        );
        expect(
          ValueCodec.encode(FieldValue.arrayUnion(<Object?>[Timestamp(1, 2)])),
          isA<fs.FieldValue>(),
        );
      },
    );

    test('field paths', () {
      expect(
        ValueCodec.encodeField(FieldPath(const <String>['a.b', 'c'])),
        fs.FieldPath(<String>['a.b', 'c']),
      );
      expect(
        ValueCodec.encodeField(FieldPath.documentId),
        fs.FieldPath.documentId,
      );
    });
  });

  group('errors', () {
    test(
      'FirestoreException becomes the FirebaseException of firebase_core',
      () {
        final Object converted = convertError(
          fs.FirestoreException(
            errorCode: fs.FirestoreErrorCode.notFound,
            message: 'gone',
          ),
        );
        expect(
          converted,
          isA<FirebaseException>()
              .having(
                (FirebaseException e) => e.plugin,
                'plugin',
                'cloud_firestore',
              )
              .having((FirebaseException e) => e.code, 'code', 'not-found')
              .having((FirebaseException e) => e.message, 'message', 'gone'),
        );
      },
    );

    test('every code keeps the FlutterFire string', () {
      for (final fs.FirestoreErrorCode code in fs.FirestoreErrorCode.values) {
        final Object converted = convertError(
          fs.FirestoreException(errorCode: code, message: 'm'),
        );
        expect((converted as FirebaseException).code, code.code);
      }
      expect(fs.FirestoreErrorCode.values.map((c) => c.code).toList(), <String>[
        'ok',
        'cancelled',
        'unknown',
        'invalid-argument',
        'deadline-exceeded',
        'not-found',
        'already-exists',
        'permission-denied',
        'resource-exhausted',
        'failed-precondition',
        'aborted',
        'out-of-range',
        'unimplemented',
        'internal',
        'unavailable',
        'data-loss',
        'unauthenticated',
      ]);
    });
  });

  group('not implemented', () {
    test('pipelines throw UnimplementedError', () {
      final DartFirebaseFirestore platform = DartFirebaseFirestore();
      expect(
        () => platform.pipeline(<Map<String, dynamic>>[]),
        throwsUnimplementedError,
      );
    });
  });
}
