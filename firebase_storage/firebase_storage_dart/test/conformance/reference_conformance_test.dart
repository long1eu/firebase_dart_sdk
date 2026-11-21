import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../fakes.dart';
import 'conformance.dart';

// Conformance with reference.test.ts, service.test.ts and location.test.ts of the JS SDK, through the public
// API. JS `makeStorage(url)` / `ref(service, url)` is `refFromUrl`, JS `ref(reference, path)` is `child`,
// `new FirebaseStorageImpl(app, ..., bucketUrl)` is the `bucket` argument.
void main() {
  late FirebaseApp app;
  late List<Recorded> requests;
  final List<FirebaseStorage> instances = <FirebaseStorage>[];

  FirebaseStorage storage({
    String? bucket,
    String? emulatorHost,
    String? mockUserToken,
    FirebaseApp? on,
  }) {
    final FirebaseStorage instance = storageWith(
      on ?? app,
      (_) => json(serverResource),
      requests: requests,
      bucket: bucket,
      emulatorHost: emulatorHost,
      mockUserToken: mockUserToken,
    );
    instances.add(instance);
    return instance;
  }

  setUp(() {
    app = newApp(storageBucket: 'test-bucket');
    requests = <Recorded>[];
  });

  tearDown(() async {
    for (final FirebaseStorage instance in instances) {
      instance.close();
    }
    instances.clear();
    await app.delete();
  });

  Reference make(String url) => storage().refFromUrl(url);

  group('reference.test.ts', () {
    group('Path constructor', () {
      final Map<String, String> cases = <String, String>{
        'root': 'gs://test-bucket/|gs://test-bucket/',
        'keeps characters after ? on a gs:// string':
            'gs://test-bucket/this/ismyobject?hello|gs://test-bucket/this/ismyobject?hello',
        "doesn't URL-decode on a gs:// string":
            'gs://test-bucket/%3F|gs://test-bucket/%3F',
        'ignores URL params and fragments on an http URL':
            'http://firebasestorage.googleapis.com/v0/b/test-bucket/o/my/object.txt?ignoreme#please'
            '|gs://test-bucket/my/object.txt',
        'URL-decodes and ignores fragment on an http URL':
            'http://firebasestorage.googleapis.com/v0/b/test-bucket/o/%3F?ignore|gs://test-bucket/?',
        'ignores URL params and fragments on an https URL':
            'https://firebasestorage.googleapis.com/v0/b/test-bucket/o/my/object.txt?ignoreme#please'
            '|gs://test-bucket/my/object.txt',
        'URL-decodes and ignores fragment on an https URL':
            'https://firebasestorage.googleapis.com/v0/b/test-bucket/o/%3F?ignore|gs://test-bucket/?',
      };
      for (final MapEntry<String, String> entry in cases.entries) {
        test(entry.key, () {
          final [String url, String expected] = entry.value.split('|');
          expect(make(url).toString(), expected);
        });
      }
    });

    group('toString', () {
      test("Doesn't add trailing slash", () {
        expect(make('gs://test-bucket/foo').toString(), 'gs://test-bucket/foo');
      });
      test('Strips trailing slash', () {
        expect(
          make('gs://test-bucket/foo/').toString(),
          'gs://test-bucket/foo',
        );
      });
    });

    group('parentReference', () {
      test('Returns null at root', () {
        expect(make('gs://test-bucket/').parent, isNull);
      });
      test('Returns root one level down', () {
        expect(
          make('gs://test-bucket/hello').parent.toString(),
          'gs://test-bucket/',
        );
      });
      test('Works correctly with empty levels', () {
        expect(
          make('gs://test-bucket/a///').parent.toString(),
          'gs://test-bucket/a/',
        );
      });
    });

    group('root', () {
      test('Returns self at root', () {
        expect(make('gs://test-bucket/').root.toString(), 'gs://test-bucket/');
      });
      test('Returns root multiple levels down', () {
        expect(
          make('gs://test-bucket/a/b/c/d').root.toString(),
          'gs://test-bucket/',
        );
      });
    });

    test('bucket: Returns bucket name', () {
      expect(make('gs://test-bucket/').bucket, 'test-bucket');
    });

    test('fullPath: Returns full path without leading slash', () {
      expect(make('gs://test-bucket/full/path').fullPath, 'full/path');
    });

    group('name', () {
      test('Works at top level', () {
        expect(make('gs://test-bucket/toplevel.txt').name, 'toplevel.txt');
      });
      test('Works at not the top level', () {
        expect(make('gs://test-bucket/not/toplevel.txt').name, 'toplevel.txt');
      });
    });

    group('get child with ref()', () {
      Reference root() => make('gs://test-bucket/');
      test('works with a simple string', () {
        expect(root().child('a').toString(), 'gs://test-bucket/a');
      });
      test('drops a trailing slash', () {
        expect(root().child('ab/').toString(), 'gs://test-bucket/ab');
      });
      test('compresses repeated slashes', () {
        expect(root().child('//a///b/////').toString(), 'gs://test-bucket/a/b');
      });
      test('works chained multiple times with leading slashes', () {
        expect(
          root().child('a').child('/b').child('c').child('d/e').toString(),
          'gs://test-bucket/a/b/c/d/e',
        );
      });
    });

    test("Doesn't send Authorization on null auth token", () async {
      app.authProvider = FakeAuth(<String?>[null]);
      await storage().ref('foo').metadata();
      expect(headersOf(requests.single).containsKey('authorization'), isFalse);
    });

    test(
      'Works if the user logs in before creating the storage reference',
      () async {
        app.authProvider = FakeAuth(<String?>['user-token']);
        await storage().ref('foo').metadata();
        expect(
          headersOf(requests.single)['authorization'],
          'Firebase user-token',
        );
      },
    );

    group('uploadString', () {
      test('Uses metadata.contentType for RAW format', () async {
        await storage()
            .ref('test')
            .putString(
              'hello',
              metadata: const SettableMetadata(contentType: 'lol/wut'),
            );
        expect(
          multipartParts(requests.single).metadata,
          contains('"contentType":"lol/wut"'),
        );
      });
      test('Uses embedded content type in DATA_URL format', () async {
        await storage()
            .ref('test')
            .putString(
              'data:lol/wat;base64,aaaa',
              format: StringFormat.dataUrl,
            );
        expect(
          multipartParts(requests.single).metadata,
          contains('"contentType":"lol/wat"'),
        );
      });
      test(
        'Lets metadata.contentType override embedded content type in DATA_URL format',
        () async {
          await storage()
              .ref('test')
              .putString(
                'data:ignore/me;base64,aaaa',
                format: StringFormat.dataUrl,
                metadata: const SettableMetadata(contentType: 'tomato/soup'),
              );
          expect(
            multipartParts(requests.single).metadata,
            contains('"contentType":"tomato/soup"'),
          );
        },
      );
    });

    group('uploadBytes', () {
      test('Uses metadata.contentType', () async {
        await storage()
            .ref('hello')
            .putBytes(
              Uint8List(0),
              metadata: const SettableMetadata(contentType: 'lol/wut'),
            );
        expect(
          multipartParts(requests.single).metadata,
          contains('"contentType":"lol/wut"'),
        );
      });
      test('uploads without error', () async {
        // JS checks result.ref; Dart returns FullMetadata, whose path names the object of the response.
        final FullMetadata result = await storage()
            .ref('child')
            .putBytes(Uint8List.fromList(<int>[97]));
        expect(result.fullPath, serverResource['name']);
      });
    });

    group('Argument verification: list', () {
      test('throws on invalid maxResults', () async {
        final Reference child = make('gs://test-bucket/hello');
        for (final int maxResults in <int>[0, -4, 1001]) {
          await expectLater(
            child.list(maxResults: maxResults),
            throwsStorageCode('invalid-argument'),
          );
        }
        expect(requests, isEmpty);
      });
      test('accepts the bounds 1 and 1000', () async {
        final Reference child = make('gs://test-bucket/hello');
        await child.list(maxResults: 1);
        await child.list(maxResults: 1000);
        expect(requests, hasLength(2));
      });
    });

    group('root operations', () {
      // JS throws synchronously from the call; the Dart operations are async and their future fails. JS
      // uploadBytesResumable is startUpload, whose root check is in the upload conformance tests.
      Reference root() => make('gs://test-bucket/');
      final Map<String, Future<Object?> Function(Reference root)> operations =
          <String, Future<Object?> Function(Reference root)>{
            'uploadString': (Reference r) => r.putString('raw'),
            'uploadBytes': (Reference r) => r.putBytes(Uint8List(0)),
            'deleteObject': (Reference r) => r.delete(),
            'getMetadata': (Reference r) => r.metadata(),
            'updateMetadata': (Reference r) =>
                r.updateMetadata(const SettableMetadata()),
            'getDownloadURL': (Reference r) => r.downloadUrl(),
            'getBytes': (Reference r) => r.getBytes(),
          };
      for (final MapEntry<String, Future<Object?> Function(Reference root)>
          entry
          in operations.entries) {
        test('${entry.key} throws', () async {
          await expectLater(
            () => entry.value(root()),
            throwsStorageCode('invalid-root-operation'),
          );
          expect(requests, isEmpty);
        });
      }
    });
  });

  group('service.test.ts', () {
    group('simple constructor', () {
      test('Root refs point to the right place', () {
        expect(storage().ref().toString(), 'gs://test-bucket/');
      });
      test('Child refs point to the right place', () {
        expect(
          storage().ref('path/to/child').toString(),
          'gs://test-bucket/path/to/child',
        );
      });
    });

    group('custom bucket constructor', () {
      final Map<String, String> specs = <String, String>{
        'gs://': 'gs://foo-bar.appspot.com',
        'http://':
            'http://firebasestorage.googleapis.com/v1/b/foo-bar.appspot.com/o',
        'https://':
            'https://firebasestorage.googleapis.com/v1/b/foo-bar.appspot.com/o',
        'Bare bucket name': 'foo-bar.appspot.com',
      };
      for (final MapEntry<String, String> entry in specs.entries) {
        test(
          '${entry.key} custom bucket constructor refs point to the right place',
          () {
            final FirebaseStorage instance = storage(bucket: entry.value);
            expect(instance.bucket, 'foo-bar.appspot.com');
            expect(instance.ref().toString(), 'gs://foo-bar.appspot.com/');
          },
        );
      }
      test('Child refs point to the right place', () {
        expect(
          storage(
            bucket: 'foo-bar.appspot.com',
          ).ref('path/to/child').toString(),
          'gs://foo-bar.appspot.com/path/to/child',
        );
      });
      test(
        'Throws trying to construct with a gs:// URL containing an object path',
        () {
          // Contract: a configuration error is an ArgumentError, where JS throws storage/invalid-default-bucket.
          expect(
            () => storage(bucket: 'gs://bucket/object/'),
            throwsArgumentError,
          );
        },
      );
    });

    group('default bucket config', () {
      Future<void> withBucket(
        String spec,
        void Function(FirebaseApp app) body,
      ) async {
        final FirebaseApp configured = newApp(storageBucket: spec);
        try {
          body(configured);
        } finally {
          await configured.delete();
        }
      }

      test('gs:// works without ending slash', () async {
        await withBucket('gs://mybucket', (FirebaseApp a) {
          expect(storage(on: a).ref().toString(), 'gs://mybucket/');
        });
      });
      test('gs:// works with ending slash', () async {
        await withBucket('gs://mybucket/', (FirebaseApp a) {
          expect(storage(on: a).ref().toString(), 'gs://mybucket/');
        });
      });
      test('Throws when config bucket is gs:// with an object path', () async {
        // ArgumentError where JS throws storage/invalid-default-bucket (see above).
        await withBucket('gs://mybucket/hello', (FirebaseApp a) {
          expect(() => storage(on: a), throwsArgumentError);
        });
      });
      test(
        'no bucket at all is an ArgumentError (JS: no-default-bucket on ref())',
        () async {
          final FirebaseApp none = newApp(storageBucket: null);
          addTearDown(none.delete);
          expect(() => storage(on: none), throwsArgumentError);
        },
      );
    });

    group('ref(service, url)', () {
      final Map<String, String> cases = <String, String>{
        'Works with gs:// URLs':
            'gs://mybucket/child/path/image.png|gs://mybucket/child/path/image.png',
        'Works with http:// URLs':
            'http://firebasestorage.googleapis.com/v0/b/mybucket/o/child%2Fpath%2Fimage.png?downloadToken=hello'
            '|gs://mybucket/child/path/image.png',
        'Works with https:// URLs':
            'https://firebasestorage.googleapis.com/v0/b/mybucket/o/child%2Fpath%2Fimage.png?downloadToken=hello'
            '|gs://mybucket/child/path/image.png',
        'Works with storage.googleapis.com URLs':
            'https://storage.googleapis.com/mybucket/path%20with%20space/image.png'
            '|gs://mybucket/path with space/image.png',
        'Works with storage.googleapis.com URLs with query params':
            'https://storage.googleapis.com/mybucket/path%20with%20space/image.png?X-Goog-Algorithm=\nGOOG4-RSA-SHA256'
            '|gs://mybucket/path with space/image.png',
        'Works with storage.cloud.google.com URLs':
            'https://storage.cloud.google.com/mybucket/path%20with%20space/image.png'
            '|gs://mybucket/path with space/image.png',
        'Works with storage.cloud.google.com URLs and escaped slash':
            'https://storage.cloud.google.com/mybucket/path%20with%20space%2Fimage.png'
            '|gs://mybucket/path with space/image.png',
      };
      for (final MapEntry<String, String> entry in cases.entries) {
        test(entry.key, () {
          final [String url, String expected] = entry.value.split('|');
          expect(storage().refFromUrl(url).toString(), expected);
        });
      }
      test('anything else is invalid-url', () {
        for (final String url in <String>[
          'notaurl',
          'ftp://mybucket/a',
          'https://example.com/mybucket/a',
          'https://storage.googleapis.com/mybucket',
        ]) {
          expect(
            () => storage().refFromUrl(url),
            throwsStorageCode('invalid-url'),
            reason: url,
          );
        }
      });
    });

    group('connectStorageEmulator(service, host, port, options)', () {
      test('sets emulator host correctly', () async {
        final FirebaseStorage instance = storage(
          emulatorHost: 'test.host.org:1234',
        );
        await instance.ref('test.png').metadata();
        expect(
          requests.single.url.toString(),
          'http://test.host.org:1234/v0/b/test-bucket/o/test.png',
        );
      });
      test('sets mock user token string if specified', () async {
        app.authProvider = FakeAuth(<String?>['real-token']);
        final FirebaseStorage instance = storage(
          emulatorHost: 'test.host.org:1234',
          mockUserToken: 'my-mock-user-token',
        );
        await instance.ref('test.png').metadata();
        expect(
          headersOf(requests.single)['authorization'],
          'Firebase my-mock-user-token',
        );
      });
      test('refFromUrl parses the URLs of the emulator host only', () {
        final FirebaseStorage instance = storage(
          emulatorHost: 'localhost:3001',
        );
        expect(
          instance
              .refFromUrl(
                'http://localhost:3001/v0/b/abcdefg.appspot.com/o/abcde.txt',
              )
              .toString(),
          'gs://abcdefg.appspot.com/abcde.txt',
        );
        expect(
          () => instance.refFromUrl(
            'https://firebasestorage.googleapis.com/v0/b/abcdefgh.appspot.com/o/abcde.txt',
          ),
          throwsStorageCode('invalid-url'),
        );
      });
      test('the download URL uses the emulator origin', () async {
        expect(
          await storage(emulatorHost: 'localhost:3001').ref('x').downloadUrl(),
          'http://localhost:3001/v0/b/b/o/${Uri.encodeComponent('foo/bar/baz.png')}?alt=media&token=a',
        );
      });
      test('mockUserToken without an emulator host is an ArgumentError', () {
        expect(() => storage(mockUserToken: 't'), throwsArgumentError);
      });
      // JS 'sets emulator host correctly with ssl' (cloud workstations) and 'creates mock user token from
      // object' have no Dart equivalent: the emulator is always plain HTTP and the token is a string.
    });

    group('ref(service, path)', () {
      test('Works with non URL paths', () {
        expect(storage().ref('child').toString(), 'gs://test-bucket/child');
      });
      test('Works with no path', () {
        expect(storage().ref().toString(), 'gs://test-bucket/');
      });
      test('a URL is a path (JS parses it; Dart has refFromUrl for that)', () {
        expect(
          storage().ref('gs://other/x').toString(),
          'gs://test-bucket/gs:/other/x',
        );
      });
    });

    group('ref(reference, path)', () {
      test(
        'Throws calling ref(reference, path) with a URL: Dart takes it as a path',
        () {
          // JS throws storage/invalid-argument; child() has no URL form, so it joins the components.
          final Reference root = storage().ref();
          expect(root.child('gs://bucket/child').fullPath, 'gs:/bucket/child');
          expect(root.child('https://a/b').fullPath, 'https:/a/b');
        },
      );
      test('Works with non URL paths', () {
        expect(
          storage().ref().child('child').toString(),
          'gs://test-bucket/child',
        );
      });
      test('Works with no path', () {
        expect(storage().ref().child('').toString(), 'gs://test-bucket/');
      });
    });

    group('Deletion', () {
      // JS deletes the app and sees storage/app-deleted; the Dart equivalent is close().
      test('Requests fail when started after the service is closed', () async {
        final FirebaseStorage instance = storage();
        instance.close();
        await expectLater(() => instance.ref('a').metadata(), throwsStateError);
        expect(requests, isEmpty);
      });
    });
  });

  group('Reference equality', () {
    test('same bucket and path are equal, toString is gs://', () {
      final FirebaseStorage instance = storage();
      expect(instance.ref('a/b'), instance.ref('a').child('b'));
      expect(
        instance.ref('a/b').hashCode,
        instance.ref('a').child('b').hashCode,
      );
      expect(instance.ref('a/b'), isNot(instance.refFromUrl('gs://other/a/b')));
      expect(instance.ref('a b').gsUri.toString(), 'gs://test-bucket/a%20b');
    });
  });

  test(
    'a 200 response that is not JSON is unknown (JS handler throws unknown())',
    () async {
      final FirebaseStorage instance = storageWith(
        app,
        (_) async => http.Response('<html>', 200),
        bucket: 'b',
      );
      instances.add(instance);
      await expectLater(
        instance.ref('x').metadata(),
        throwsStorageCode('unknown'),
      );
    },
  );
}
