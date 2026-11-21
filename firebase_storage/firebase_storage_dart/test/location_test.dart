import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/src/location.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fakes.dart';

// Ported from location.test.ts, reference.test.ts and service.test.ts of the JS SDK.
void main() {
  late FirebaseApp app;
  late FirebaseStorage storage;

  setUp(() {
    app = newApp(storageBucket: 'test-bucket');
    storage = storageWith(app, (_) async => http.Response('', 500));
  });

  tearDown(() async {
    storage.close();
    await app.delete();
  });

  Reference fromUrl(String url) => storage.refFromUrl(url);

  group('Location.fromUrl', () {
    test('emulator url', () {
      final Location location = Location.fromUrl(
        'http://localhost:3001/v0/b/abcdefg.appspot.com/o/abcde.txt',
        'localhost:3001',
      );
      expect(location.bucket, 'abcdefg.appspot.com');
      expect(location.path, 'abcde.txt');
    });

    test('Firebase Storage url', () {
      final Location location = Location.fromUrl(
        'https://firebasestorage.googleapis.com/v0/b/abcdefgh.appspot.com/o/abcde.txt',
        defaultHost,
      );
      expect(location.bucket, 'abcdefgh.appspot.com');
    });

    test('gs url', () {
      final Location location = Location.fromUrl(
        'gs://mybucket/child/path/abcde.txt',
        defaultHost,
      );
      expect(location.bucket, 'mybucket');
      expect(location.path, 'child/path/abcde.txt');
    });

    test('Cloud Storage url', () {
      final Location location = Location.fromUrl(
        'https://storage.googleapis.com/mybucket/abcde.txt',
        defaultHost,
      );
      expect(location.bucket, 'mybucket');
    });

    test('is case-insensitive on the scheme and host', () {
      expect(
        Location.fromUrl('GS://mybucket/a', defaultHost),
        const Location('mybucket', 'a'),
      );
      expect(
        Location.fromUrl(
          'HTTPS://FIREBASESTORAGE.GOOGLEAPIS.COM/v0/b/mybucket/o/a',
          defaultHost,
        ),
        const Location('mybucket', 'a'),
      );
    });

    test('a Cloud Storage url of the emulator host', () {
      expect(
        Location.fromUrl(
          'http://localhost:9199/mybucket/a%20b',
          'localhost:9199',
        ),
        const Location('mybucket', 'a b'),
      );
    });

    test('the dots of the host are literal', () {
      expect(
        () => Location.fromUrl(
          'https://firebasestorageXgoogleapis.com/v0/b/b/o/a',
          defaultHost,
        ),
        throwsStorageCode('invalid-url'),
      );
    });

    test('a url of another host than the current one is invalid', () {
      expect(
        () => Location.fromUrl('http://localhost:9199/v0/b/b/o/a', defaultHost),
        throwsStorageCode('invalid-url'),
      );
    });

    test('rejects other urls with invalid-url', () {
      for (final String url in <String>[
        'https://example.com/b/o/a',
        'https://storage.googleapis.com/b',
        'ftp://b/a',
        'gs://',
        'not a url',
      ]) {
        expect(
          () => Location.fromUrl(url, defaultHost),
          throwsStorageCode('invalid-url'),
          reason: url,
        );
      }
    });

    test('a malformed percent-encoding is invalid-url', () {
      expect(
        () => Location.fromUrl(
          'https://firebasestorage.googleapis.com/v0/b/b/o/%E0%A4%A',
          defaultHost,
        ),
        throwsStorageCode('invalid-url'),
      );
    });
  });

  group('Location url parts', () {
    test('escape the bucket and the whole path', () {
      const Location normal = Location('b', 'o');
      expect(normal.fullUrlPart, '/b/b/o/o');
      expect(normal.bucketOnlyUrlPart, '/b/b/o');
      const Location escapes = Location('b/', 'o?');
      expect(escapes.fullUrlPart, '/b/b%2F/o/o%3F');
      expect(escapes.bucketOnlyUrlPart, '/b/b%2F/o');
    });

    test('encode like encodeURIComponent', () {
      expect(percentEncode("a/b c!~*'()-_.é"), "a%2Fb%20c!~*'()-_.%C3%A9");
    });
  });

  group('Path constructor', () {
    test('root', () {
      expect(fromUrl('gs://test-bucket/').toString(), 'gs://test-bucket/');
    });

    test('keeps characters after ? on a gs:// string', () {
      expect(
        fromUrl('gs://test-bucket/this/ismyobject?hello').toString(),
        'gs://test-bucket/this/ismyobject?hello',
      );
    });

    test("doesn't URL-decode on a gs:// string", () {
      expect(
        fromUrl('gs://test-bucket/%3F').toString(),
        'gs://test-bucket/%3F',
      );
    });

    for (final String scheme in <String>['http', 'https']) {
      test('ignores URL params and fragments on an $scheme URL', () {
        expect(
          fromUrl(
            '$scheme://$defaultHost/v0/b/test-bucket/o/my/object.txt?ignoreme#please',
          ).toString(),
          'gs://test-bucket/my/object.txt',
        );
      });

      test('URL-decodes and ignores fragment on an $scheme URL', () {
        expect(
          fromUrl(
            '$scheme://$defaultHost/v0/b/test-bucket/o/%3F?ignore',
          ).toString(),
          'gs://test-bucket/?',
        );
      });
    }
  });

  group('refFromUrl', () {
    test('gs:// URLs', () {
      expect(
        fromUrl('gs://mybucket/child/path/image.png').toString(),
        'gs://mybucket/child/path/image.png',
      );
    });

    test('download URLs', () {
      for (final String scheme in <String>['http', 'https']) {
        expect(
          fromUrl(
            '$scheme://$defaultHost/v0/b/mybucket/o/child%2Fpath%2Fimage.png?downloadToken=hello',
          ).toString(),
          'gs://mybucket/child/path/image.png',
        );
      }
    });

    test('storage.googleapis.com and storage.cloud.google.com URLs', () {
      for (final String url in <String>[
        'https://storage.googleapis.com/mybucket/path%20with%20space/image.png',
        'https://storage.googleapis.com/mybucket/path%20with%20space/image.png?X-Goog-Algorithm=GOOG4-RSA-SHA256',
        'https://storage.cloud.google.com/mybucket/path%20with%20space/image.png',
        'https://storage.cloud.google.com/mybucket/path%20with%20space%2Fimage.png',
      ]) {
        expect(
          fromUrl(url).toString(),
          'gs://mybucket/path with space/image.png',
          reason: url,
        );
      }
    });

    test('keeps the bucket of the URL', () {
      final Reference ref = fromUrl('gs://other-bucket/a');
      expect(ref.bucket, 'other-bucket');
      expect(ref.storage, same(storage));
    });

    test('emulator download URLs parse against the emulator host', () async {
      final FirebaseApp other = newApp();
      final FirebaseStorage emulated = storageWith(
        other,
        (_) async => http.Response('', 500),
        emulatorHost: '127.0.0.1:9199',
      );
      addTearDown(other.delete);
      addTearDown(emulated.close);
      expect(
        emulated
            .refFromUrl(
              'http://127.0.0.1:9199/v0/b/b/o/a%2Fb.txt?alt=media&token=t',
            )
            .toString(),
        'gs://b/a/b.txt',
      );
      expect(
        () => emulated.refFromUrl(
          'https://firebasestorage.googleapis.com/v0/b/b/o/a',
        ),
        throwsStorageCode('invalid-url'),
      );
    });
  });

  group('Reference', () {
    Reference root() => fromUrl('gs://test-bucket/');
    Reference child() => fromUrl('gs://test-bucket/hello');

    test("toString doesn't add a trailing slash", () {
      expect(
        fromUrl('gs://test-bucket/foo').toString(),
        'gs://test-bucket/foo',
      );
    });

    test('toString strips a trailing slash', () {
      expect(
        fromUrl('gs://test-bucket/foo/').toString(),
        'gs://test-bucket/foo',
      );
    });

    test('parent is null at root', () {
      expect(root().parent, isNull);
    });

    test('parent is the root one level down', () {
      expect(child().parent.toString(), 'gs://test-bucket/');
    });

    test('parent works with empty levels', () {
      expect(
        fromUrl('gs://test-bucket/a///').parent.toString(),
        'gs://test-bucket/a/',
      );
    });

    test('root returns self at root', () {
      expect(root().root, root());
    });

    test('root multiple levels down', () {
      expect(
        fromUrl('gs://test-bucket/a/b/c/d').root.toString(),
        'gs://test-bucket/',
      );
    });

    test('bucket, fullPath and name', () {
      final Reference ref = fromUrl('gs://test-bucket/full/path');
      expect(root().bucket, 'test-bucket');
      expect(ref.fullPath, 'full/path');
      expect(ref.name, 'path');
      expect(fromUrl('gs://test-bucket/toplevel.txt').name, 'toplevel.txt');
      expect(root().name, '');
    });

    test('child with a simple string', () {
      expect(root().child('a').toString(), 'gs://test-bucket/a');
    });

    test('child drops a trailing slash', () {
      expect(root().child('ab/').toString(), 'gs://test-bucket/ab');
    });

    test('child compresses repeated slashes', () {
      expect(root().child('//a///b/////').toString(), 'gs://test-bucket/a/b');
    });

    test('child chained multiple times with leading slashes', () {
      expect(
        root().child('a').child('/b').child('c').child('d/e').toString(),
        'gs://test-bucket/a/b/c/d/e',
      );
    });

    test('child of an empty path is the same reference', () {
      expect(child().child(''), child());
      expect(child().child('///'), child());
    });

    test('gsUri', () {
      expect(
        storage.ref('a b/c.txt').gsUri,
        Uri.parse('gs://test-bucket/a%20b/c.txt'),
      );
      expect(root().gsUri.toString(), 'gs://test-bucket/');
    });

    test('equality is by bucket and path', () {
      expect(storage.ref('a/b'), storage.ref('a').child('b'));
      expect(storage.ref('a/b').hashCode, storage.ref('a').child('b').hashCode);
      expect(storage.ref('a'), isNot(fromUrl('gs://other/a')));
      expect(storage.ref('a'), isNot(storage.ref('b')));
    });
  });

  group('FirebaseStorage bucket', () {
    late FirebaseApp other;

    setUp(() => other = newApp(storageBucket: null));
    tearDown(() => other.delete());

    String bucketOf(String? bucket, {String? optionsBucket}) {
      final FirebaseApp a = newApp(storageBucket: optionsBucket);
      addTearDown(a.delete);
      final FirebaseStorage s = FirebaseStorage(a, bucket: bucket);
      addTearDown(s.close);
      return s.bucket;
    }

    test('custom buckets', () {
      for (final String spec in <String>[
        'gs://foo-bar.appspot.com',
        'gs://foo-bar.appspot.com/',
        'http://$defaultHost/v1/b/foo-bar.appspot.com/o',
        'https://$defaultHost/v1/b/foo-bar.appspot.com/o',
        'foo-bar.appspot.com',
      ]) {
        expect(bucketOf(spec), 'foo-bar.appspot.com', reason: spec);
      }
    });

    test('the default bucket of the options', () {
      expect(bucketOf(null, optionsBucket: 'gs://mybucket'), 'mybucket');
      expect(bucketOf(null, optionsBucket: 'gs://mybucket/'), 'mybucket');
      expect(bucketOf(null, optionsBucket: 'mybucket'), 'mybucket');
    });

    test('an explicit bucket wins over the options', () {
      expect(bucketOf('explicit', optionsBucket: 'options'), 'explicit');
    });

    test('a bucket with an object path is an ArgumentError', () {
      expect(() => bucketOf('gs://bucket/object/'), throwsArgumentError);
      expect(
        () => bucketOf(null, optionsBucket: 'gs://bucket/object'),
        throwsArgumentError,
      );
    });

    test('no bucket is an ArgumentError', () {
      expect(() => FirebaseStorage(other), throwsArgumentError);
      expect(() => FirebaseStorage(other, bucket: ''), throwsArgumentError);
    });

    test('ref without a path is the root, with a path a child', () {
      final FirebaseStorage s = FirebaseStorage(other, bucket: 'mybucket');
      addTearDown(s.close);
      expect(s.ref().toString(), 'gs://mybucket/');
      expect(
        s.ref('child/path/image.png').toString(),
        'gs://mybucket/child/path/image.png',
      );
      expect(s.ref('gs://x/y').fullPath, 'gs:/x/y');
    });
  });

  group('FirebaseStorage emulator', () {
    test('accepts host:port', () {
      final FirebaseStorage s = FirebaseStorage(
        app,
        emulatorHost: '127.0.0.1:9199',
      );
      addTearDown(s.close);
      expect(s.emulatorHost, '127.0.0.1:9199');
      expect(s.origin, 'http://127.0.0.1:9199');
      final FirebaseStorage ipv6 = FirebaseStorage(
        app,
        emulatorHost: '[::1]:9199',
      );
      addTearDown(ipv6.close);
      expect(ipv6.origin, 'http://[::1]:9199');
    });

    test('rejects anything else', () {
      for (final String host in <String>[
        'localhost',
        'http://localhost:9199',
        'localhost:9199/path',
        'user@localhost:9199',
        'localhost:9199?a=b',
        '',
        'localhost:port',
      ]) {
        expect(
          () => FirebaseStorage(app, emulatorHost: host),
          throwsArgumentError,
          reason: host,
        );
      }
    });

    test('the production origin', () {
      expect(storage.origin, 'https://firebasestorage.googleapis.com');
      expect(storage.emulatorHost, isNull);
    });

    test('mockUserToken needs an emulator', () {
      expect(
        () => FirebaseStorage(app, mockUserToken: 'owner'),
        throwsArgumentError,
      );
    });
  });
}
