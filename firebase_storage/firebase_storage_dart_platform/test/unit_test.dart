// Tests through the official firebase_storage API, against a fake backend:
// instances and settings, the mapping of each operation, and the errors.

import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart' as fs;
import 'package:firebase_storage_dart_platform/firebase_storage_dart_platform.dart';
import 'package:firebase_storage_dart_platform/src/reference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'harness.dart';

void main() {
  registerForTests();

  group('instances', () {
    test('one platform instance per app and bucket, gs:// or not', () async {
      final FirebaseApp app = await newApp();
      final FirebaseStorage storage = FirebaseStorage.instanceFor(app: app);
      final FirebaseStorage other = FirebaseStorage.instanceFor(
        app: app,
        bucket: 'gs://other-bucket',
      );
      expect(storage.bucket, bucket);
      expect(other.bucket, 'other-bucket');
      expect(
        FirebaseStorageDart.clientFor(app),
        same(FirebaseStorageDart.clientFor(app, bucket: 'gs://$bucket')),
      );
      expect(
        FirebaseStorageDart.clientFor(app, bucket: 'other-bucket').bucket,
        'other-bucket',
      );
    });

    test('an app without a bucket has no default client', () async {
      final FirebaseApp app = await newApp(
        appOptions: const FirebaseOptions(
          apiKey: 'k',
          appId: '1:1:web:1',
          messagingSenderId: '1',
          projectId: 'demo-unit',
        ),
      );
      expect(() => FirebaseStorageDart.clientFor(app), throwsArgumentError);
    });

    test('the requests of two buckets go to their own bucket', () async {
      final FirebaseApp app = await newApp();
      backend.put('other-bucket', 'x/y.txt', <int>[1, 2]);
      final Reference ref = FirebaseStorage.instanceFor(
        app: app,
      ).refFromURL('gs://other-bucket/x/y.txt');
      final FullMetadata metadata = await ref.getMetadata();
      expect(metadata.bucket, 'other-bucket');
      expect(
        backend.requests.single.url.path,
        '/v0/b/other-bucket/o/x%2Fy.txt',
      );
    });

    test('the requests carry the token of tokenProviderFor', () async {
      final FirebaseApp app = await newApp();
      tokens[app.name] = 'the-token';
      backend.put(bucket, 'a', <int>[1]);
      await FirebaseStorage.instanceFor(app: app).ref('a').getMetadata();
      expect(
        backend.requests.single.headers['Authorization'],
        'Firebase the-token',
      );
      expect(backend.requests.single.headers['X-Firebase-GMPID'], '1:1:web:1');
    });

    test('without a token the requests carry no user', () async {
      final FirebaseApp app = await newApp();
      backend.put(bucket, 'a', <int>[1]);
      await FirebaseStorage.instanceFor(app: app).ref('a').getMetadata();
      expect(
        backend.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
    });
  });

  group('settings', () {
    test('the retry times start at the defaults of the native SDKs', () async {
      final FirebaseStorage storage = FirebaseStorage.instanceFor(
        app: await newApp(),
      );
      expect(storage.maxOperationRetryTime, const Duration(minutes: 2));
      expect(storage.maxUploadRetryTime, const Duration(minutes: 10));
      expect(storage.maxDownloadRetryTime, const Duration(minutes: 10));
    });

    test('setMax*RetryTime gives the next operations a client with the new '
        'policy', () async {
      final FirebaseApp app = await newApp();
      final FirebaseStorage storage = FirebaseStorage.instanceFor(app: app);
      final fs.FirebaseStorage before = FirebaseStorageDart.clientFor(app);

      storage.setMaxOperationRetryTime(const Duration(seconds: 5));
      expect(
        FirebaseStorageDart.clientFor(app).retry.operation,
        const Duration(seconds: 5),
      );
      storage.setMaxUploadRetryTime(const Duration(seconds: 6));
      expect(
        FirebaseStorageDart.clientFor(app).retry.upload,
        const Duration(seconds: 6),
      );
      storage.setMaxDownloadRetryTime(const Duration(seconds: 7));

      expect(storage.maxOperationRetryTime, const Duration(seconds: 5));
      expect(storage.maxUploadRetryTime, const Duration(seconds: 6));
      expect(storage.maxDownloadRetryTime, const Duration(seconds: 7));
      expect(
        FirebaseStorageDart.clientFor(app).retry,
        const fs.StorageRetryPolicy(
          operation: Duration(seconds: 5),
          upload: Duration(seconds: 6),
          download: Duration(seconds: 7),
        ),
      );
      expect(before.retry, const fs.StorageRetryPolicy(), reason: 'kept');
    });

    test('useStorageEmulator sends the requests to the emulator', () async {
      final FirebaseApp app = await newApp();
      final FirebaseStorage storage = FirebaseStorage.instanceFor(app: app);
      await storage.useStorageEmulator('127.0.0.1', 9199);
      backend.put(bucket, 'a', <int>[1]);
      await storage.ref('a').getMetadata();
      expect(
        backend.requests.single.url.toString(),
        'http://127.0.0.1:9199/v0/b/$bucket/o/a',
      );
      expect(FirebaseStorageDart.clientFor(app).emulatorHost, '127.0.0.1:9199');
    });

    test('useStorageEmulator brackets an IPv6 host', () async {
      final FirebaseApp app = await newApp();
      await FirebaseStorage.instanceFor(
        app: app,
      ).useStorageEmulator('::1', 9199);
      expect(FirebaseStorageDart.clientFor(app).emulatorHost, '[::1]:9199');
    });

    test('the requests go to FIREBASE_STORAGE_EMULATOR_HOST when it is set, '
        'else to Google', () async {
      final FirebaseApp app = await newApp();
      backend.put(bucket, 'a', <int>[1]);
      await FirebaseStorage.instanceFor(app: app).ref('a').getMetadata();
      final String? fromEnvironment =
          fs.FirebaseStorage.emulatorHostFromEnvironment;
      expect(
        backend.requests.single.url.origin,
        fromEnvironment == null
            ? 'https://firebasestorage.googleapis.com'
            : 'http://$fromEnvironment',
      );
    });
  });

  group('references', () {
    test('paths, names and parents are those of FlutterFire', () async {
      final FirebaseStorage storage = FirebaseStorage.instanceFor(
        app: await newApp(),
      );
      final Reference ref = storage.ref('/photos/2026/cat.png');
      expect(ref.fullPath, 'photos/2026/cat.png');
      expect(ref.name, 'cat.png');
      expect(ref.bucket, bucket);
      expect(ref.parent!.fullPath, 'photos/2026');
      expect(ref.root.fullPath, '/');
      expect(storage.ref().parent, isNull);
      expect(storage.ref('photos').child('a/b.png').fullPath, 'photos/a/b.png');
    });

    test('getMetadata maps every field', () async {
      final FirebaseApp app = await newApp();
      backend.put(
        bucket,
        'docs/a.txt',
        utf8.encode('hello'),
        metadata: <String, Object?>{
          'cacheControl': 'no-cache',
          'contentDisposition': 'inline',
          'contentEncoding': 'identity',
          'contentLanguage': 'en',
          'contentType': 'text/plain',
          'metadata': <String, Object?>{'owner': 'me'},
        },
      );
      final FullMetadata metadata = await FirebaseStorage.instanceFor(
        app: app,
      ).ref('docs/a.txt').getMetadata();
      expect(metadata.bucket, bucket);
      expect(metadata.fullPath, 'docs/a.txt');
      expect(metadata.name, 'a.txt');
      expect(metadata.size, 5);
      expect(metadata.generation, isNotNull);
      expect(metadata.metageneration, '1');
      expect(metadata.metadataGeneration, '1');
      expect(metadata.md5Hash, 'aGFzaA==');
      // FlutterFire builds the dates from milliseconds, in local time.
      expect(
        metadata.timeCreated!.isAtSameMomentAs(DateTime.utc(2026, 11, 20, 10)),
        isTrue,
      );
      expect(
        metadata.updated!.isAtSameMomentAs(
          DateTime.utc(2026, 11, 21, 11, 30, 0, 500),
        ),
        isTrue,
      );
      expect(metadata.cacheControl, 'no-cache');
      expect(metadata.contentDisposition, 'inline');
      expect(metadata.contentEncoding, 'identity');
      expect(metadata.contentLanguage, 'en');
      expect(metadata.contentType, 'text/plain');
      expect(metadata.customMetadata, <String, String>{'owner': 'me'});
    });

    test('updateMetadata sends the fields that are set and returns the new '
        'metadata', () async {
      final FirebaseApp app = await newApp();
      backend.put(bucket, 'a.txt', <int>[1]);
      final FullMetadata updated = await FirebaseStorage.instanceFor(app: app)
          .ref('a.txt')
          .updateMetadata(
            SettableMetadata(
              contentType: 'text/csv',
              customMetadata: <String, String>{'k': 'v'},
            ),
          );
      final http.Request request = backend.requests.single;
      expect(request.method, 'PATCH');
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      expect(body['contentType'], 'text/csv');
      expect(body['metadata'], <String, Object?>{'k': 'v'});
      expect(body.containsKey('cacheControl'), isFalse);
      expect(updated.contentType, 'text/csv');
      expect(updated.customMetadata, <String, String>{'k': 'v'});
    });

    test('getDownloadURL builds the URL with the download token', () async {
      final FirebaseApp app = await newApp();
      backend.put(bucket, 'a b.png', <int>[1]);
      final String url = await FirebaseStorage.instanceFor(
        app: app,
      ).ref('a b.png').getDownloadURL();
      expect(url, contains('/v0/b/$bucket/o/a%20b.png?'));
      expect(Uri.parse(url).queryParameters, <String, String>{
        'alt': 'media',
        'token': 'token-1',
      });
    });

    test('delete removes the object', () async {
      final FirebaseApp app = await newApp();
      backend.put(bucket, 'a', <int>[1]);
      await FirebaseStorage.instanceFor(app: app).ref('a').delete();
      expect(backend.objects, isEmpty);
    });

    test('getData returns the bytes', () async {
      final FirebaseApp app = await newApp();
      backend.put(bucket, 'a', <int>[1, 2, 3]);
      final Uint8List? data = await FirebaseStorage.instanceFor(
        app: app,
      ).ref('a').getData();
      expect(data, <int>[1, 2, 3]);
    });

    test('getData of an object larger than maxSize fails with '
        'download-size-exceeded', () async {
      final FirebaseApp app = await newApp();
      backend.put(bucket, 'a', <int>[1, 2, 3]);
      await expectLater(
        FirebaseStorage.instanceFor(app: app).ref('a').getData(2),
        throwsStorageCode('download-size-exceeded'),
      );
    });
  });

  group('list', () {
    Future<FirebaseStorage> withFolder() async {
      final FirebaseStorage storage = FirebaseStorage.instanceFor(
        app: await newApp(),
      );
      for (final String name in <String>['d/1', 'd/2', 'd/3', 'd/e/4']) {
        backend.put(bucket, name, <int>[0]);
      }
      return storage;
    }

    test('list maps the options, items, prefixes and page token', () async {
      final FirebaseStorage storage = await withFolder();
      final ListResult first = await storage
          .ref('d')
          .list(const ListOptions(maxResults: 2));
      expect(backend.requests.single.url.queryParameters, <String, String>{
        'prefix': 'd/',
        'delimiter': '/',
        'maxResults': '2',
      });
      expect(first.items.map((Reference r) => r.fullPath), <String>[
        'd/1',
        'd/2',
      ]);
      expect(first.prefixes.map((Reference r) => r.fullPath), <String>['d/e']);
      expect(first.nextPageToken, '2');
      expect(first.items.first.storage, same(storage));

      final ListResult second = await storage
          .ref('d')
          .list(ListOptions(pageToken: first.nextPageToken));
      expect(second.items.map((Reference r) => r.fullPath), <String>['d/3']);
      expect(second.nextPageToken, isNull);
    });

    test('list of the root lists the bucket', () async {
      final FirebaseStorage storage = await withFolder();
      final ListResult root = await storage.ref().list();
      expect(backend.requests.single.url.queryParameters['prefix'], '');
      expect(root.prefixes.single.fullPath, 'd');
    });

    test('listAll follows the pages', () async {
      final FirebaseStorage storage = await withFolder();
      final ListResult all = await storage.ref('d').listAll();
      expect(all.items, hasLength(3));
      expect(all.prefixes, hasLength(1));
      expect(all.nextPageToken, isNull);
    });
  });

  group('errors', () {
    test('a missing object fails with object-not-found', () async {
      final FirebaseApp app = await newApp();
      await expectLater(
        FirebaseStorage.instanceFor(app: app).ref('missing').getMetadata(),
        throwsStorageCode('object-not-found'),
      );
    });

    test('a 403 fails with unauthorized', () async {
      final FirebaseApp app = await newApp();
      backend.failWith = 403;
      await expectLater(
        FirebaseStorage.instanceFor(app: app).ref('a').delete(),
        throwsStorageCode('unauthorized'),
      );
      await expectLater(
        FirebaseStorage.instanceFor(app: app).ref('a').list(),
        throwsStorageCode('unauthorized'),
      );
    });

    test('putBlob is not supported', () async {
      final FirebaseApp app = await newApp();
      expect(
        () => FirebaseStorage.instanceFor(app: app).ref('a').putBlob(Object()),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });

  group('decodeString', () {
    test('decodes each format', () {
      expect(decodeString('hé', PutStringFormat.raw).bytes, utf8.encode('hé'));
      expect(decodeString('AQID', PutStringFormat.base64).bytes, <int>[
        1,
        2,
        3,
      ]);
      expect(decodeString('AQI', PutStringFormat.base64).bytes, <int>[1, 2]);
      expect(decodeString('-_8', PutStringFormat.base64Url).bytes, <int>[
        251,
        255,
      ]);
      final ({Uint8List bytes, String? contentType}) dataUrl = decodeString(
        'data:image/png;base64,AQID',
        PutStringFormat.dataUrl,
      );
      expect(dataUrl.bytes, <int>[1, 2, 3]);
      expect(dataUrl.contentType, 'image/png');
      expect(
        decodeString('data:,a%20b', PutStringFormat.dataUrl).bytes,
        utf8.encode('a b'),
      );
    });

    test('a string that does not match its format is invalid-format', () {
      expect(
        () => decodeString('***', PutStringFormat.base64),
        throwsStorageCode('invalid-format'),
      );
      expect(
        () => decodeString('not a data url', PutStringFormat.dataUrl),
        throwsStorageCode('invalid-format'),
      );
    });
  });
}
