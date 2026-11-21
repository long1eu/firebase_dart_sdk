import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../fakes.dart';
import 'conformance.dart';

// Conformance with requests.test.ts of the JS SDK: the exact request of each operation (method, URL, every
// header, body) and the parsing of its response, through the public API. The JS test builds RequestInfos; here
// the request is the one a MockClient receives.
//
// The JS locations: locationNormal = ('b', 'o'), locationEscapes = ('b/', 'o?').
void main() {
  late FirebaseApp app;
  late List<Recorded> requests;
  late Future<http.Response> Function(Recorded request) respond;
  final List<FirebaseStorage> instances = <FirebaseStorage>[];

  FirebaseStorage storage({String bucket = 'b'}) {
    final FirebaseStorage instance = storageWith(
      app,
      (Recorded r) => respond(r),
      requests: requests,
      bucket: bucket,
    );
    instances.add(instance);
    return instance;
  }

  Reference normal() => storage().ref('o');
  Reference escapes() => storage(bucket: 'b/').ref('o?');

  setUp(() {
    app = newApp(storageBucket: 'b');
    requests = <Recorded>[];
    respond = (_) => json(serverResource);
  });

  tearDown(() async {
    for (final FirebaseStorage instance in instances) {
      instance.close();
    }
    instances.clear();
    await app.delete();
  });

  // fromResourceString(serverResource) of the JS test, plus what Dart adds: typed size and dates, and the
  // download tokens (the JS mapping drops them).
  void expectServerMetadata(FullMetadata metadata) {
    expect(metadata.bucket, 'b');
    expect(metadata.generation, '1');
    expect(metadata.metageneration, '2');
    expect(metadata.fullPath, 'foo/bar/baz.png');
    expect(metadata.name, 'baz.png');
    expect(metadata.size, 10);
    expect(metadata.timeCreated, DateTime.utc(2026, 11, 20, 10));
    expect(metadata.updated, DateTime.utc(2026, 11, 21, 11, 30, 0, 500));
    expect(metadata.md5Hash, 'deadbeef');
    expect(metadata.cacheControl, 'max-age=604800');
    expect(metadata.contentDisposition, 'Attachment; filename=baz.png');
    expect(metadata.contentEncoding, isNull);
    expect(metadata.contentLanguage, 'en-US');
    expect(metadata.contentType, 'application/jason');
    expect(metadata.customMetadata, <String, String>{'foo': 'bar'});
    expect(metadata.downloadTokens, <String>['a', 'b', 'c']);
  }

  const SettableMetadata jsMetadata = SettableMetadata(
    contentType: 'application/jason',
    customMetadata: <String, String>{'foo': 'bar'},
  );

  test('getMetadata request info', () async {
    await normal().metadata();
    await escapes().metadata();
    expectRequest(
      requests[0],
      method: 'GET',
      url: '$prod/v0/b/b/o/o',
      headers: commonHeaders(),
    );
    expectRequest(
      requests[1],
      method: 'GET',
      url: '$prod/v0/b/b%2F/o/o%3F',
      headers: commonHeaders(),
    );
  });

  test('getMetadata handler', () async {
    expectServerMetadata(await normal().metadata());
  });

  test('list root request info', () async {
    respond = (_) => json(<String, Object?>{});
    await storage().ref().list();
    expectRequest(
      requests.single,
      method: 'GET',
      url: '$prod/v0/b/b/o?prefix=&delimiter=%2F',
      headers: commonHeaders(),
    );
  });

  test('list request info', () async {
    respond = (_) => json(<String, Object?>{});
    const String pageToken = 'pageToken-afeafeagef';
    await normal().list(maxResults: 13, pageToken: pageToken);
    await escapes().list(maxResults: 13, pageToken: pageToken);
    // Insertion order of the JS urlParams: prefix, delimiter, pageToken, maxResults.
    expectRequest(
      requests[0],
      method: 'GET',
      url:
          '$prod/v0/b/b/o?prefix=o%2F&delimiter=%2F'
          '&pageToken=$pageToken&maxResults=13',
      headers: commonHeaders(),
    );
    expectRequest(
      requests[1],
      method: 'GET',
      url:
          '$prod/v0/b/b%2F/o?prefix=o%3F%2F&delimiter=%2F'
          '&pageToken=$pageToken&maxResults=13',
      headers: commonHeaders(),
    );
  });

  test('list handler', () async {
    respond = (_) => json(<String, Object?>{
      'prefixes': <String>['a/f/'],
      'items': <Object?>[
        <String, Object?>{'name': 'a/a', 'bucket': 'b'},
        <String, Object?>{'name': 'a/b', 'bucket': 'b'},
      ],
      'nextPageToken': 'YS9mLw==',
    });
    final ListResult result = await normal().list();
    expect(result.prefixes.map((Reference r) => r.fullPath), <String>['a/f']);
    expect(result.items.map((Reference r) => r.fullPath), <String>[
      'a/a',
      'a/b',
    ]);
    expect(result.nextPageToken, 'YS9mLw==');
  });

  test('list handler with custom bucket', () async {
    respond = (_) => json(<String, Object?>{
      'items': <Object?>[
        <String, Object?>{'name': 'a/a', 'bucket': 'c'},
      ],
      'nextPageToken': 'YS9mLw==',
    });
    final ListResult result = await storage(bucket: 'c').ref().list();
    expect(result.items.single.bucket, 'c');
    expect(result.prefixes, isEmpty);
  });

  test(
    'list handler: the bucket of an item is ignored (the request bucket wins)',
    () async {
      respond = (_) => json(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{'name': 'x', 'bucket': 'other'},
        ],
      });
      final ListResult result = await normal().list();
      expect(result.items.single.bucket, 'b');
      expect(result.nextPageToken, isNull);
    },
  );

  test('getDownloadUrl request info', () async {
    await normal().downloadUrl();
    await escapes().downloadUrl();
    expectRequest(
      requests[0],
      method: 'GET',
      url: '$prod/v0/b/b/o/o',
      headers: commonHeaders(),
    );
    expectRequest(
      requests[1],
      method: 'GET',
      url: '$prod/v0/b/b%2F/o/o%3F',
      headers: commonHeaders(),
    );
  });

  test('getDownloadUrl handler', () async {
    // Built from the bucket and name of the response, with its first token.
    expect(
      await normal().downloadUrl(),
      '$prod/v0/b/b/o/${Uri.encodeComponent('foo/bar/baz.png')}'
      '?alt=media&token=a',
    );
  });

  test('getBytes handler', () async {
    respond = (_) async => http.Response.bytes(<int>[1, 128, 255], 200);
    expect(await normal().getBytes(), <int>[1, 128, 255]);
    expectRequest(
      requests.single,
      method: 'GET',
      url: '$prod/v0/b/b/o/o?alt=media',
      headers: commonHeaders(),
    );
  });

  test('updateMetadata requestinfo', () async {
    await normal().updateMetadata(jsMetadata);
    await escapes().updateMetadata(jsMetadata);
    const String body =
        '{"contentType":"application/jason","metadata":{"foo":"bar"}}';
    final Map<String, String> headers = commonHeaders(<String, String>{
      'content-type': 'application/json; charset=utf-8',
    });
    expectRequest(
      requests[0],
      method: 'PATCH',
      url: '$prod/v0/b/b/o/o',
      headers: headers,
      body: body,
    );
    expectRequest(
      requests[1],
      method: 'PATCH',
      url: '$prod/v0/b/b%2F/o/o%3F',
      headers: headers,
      body: body,
    );
  });

  test('updateMetadata handler', () async {
    expectServerMetadata(await normal().updateMetadata(jsMetadata));
  });

  test('deleteObject request info', () async {
    respond = (_) async => http.Response('', 204);
    await normal().delete();
    await escapes().delete();
    expectRequest(
      requests[0],
      method: 'DELETE',
      url: '$prod/v0/b/b/o/o',
      headers: commonHeaders(),
    );
    expectRequest(
      requests[1],
      method: 'DELETE',
      url: '$prod/v0/b/b%2F/o/o%3F',
      headers: commonHeaders(),
    );
  });

  test('deleteObject handler', () async {
    // Success codes [200, 204]; the body is ignored, even when it is not JSON.
    respond = (_) async => http.Response('not json', 200);
    await normal().delete();
    respond = (_) async => http.Response('', 204);
    await normal().delete();
  });

  test('multipartUpload request info', () async {
    for (final Reference ref in <Reference>[normal(), escapes()]) {
      requests.clear();
      await ref.putBytes(Uint8List.fromList(<int>[97]), metadata: jsMetadata);
      final Recorded request = requests.single;
      final String boundary = multipartParts(request).boundary;
      final String name = ref.fullPath;
      final String bucket = Uri.encodeComponent(ref.bucket);
      expectRequest(
        request,
        method: 'POST',
        url: '$prod/v0/b/$bucket/o?name=${Uri.encodeComponent(name)}',
        headers: commonHeaders(<String, String>{
          'x-goog-upload-protocol': 'multipart',
          'content-type': 'multipart/related; boundary=$boundary',
        }),
        body:
            '--$boundary\r\n'
            'Content-Type: application/json; charset=utf-8\r\n'
            '\r\n'
            '{"name":${jsonEncode(name)},"contentType":"application/jason",'
            '"metadata":{"foo":"bar"}}\r\n'
            '--$boundary\r\n'
            'Content-Type: application/jason\r\n'
            '\r\n'
            'a\r\n'
            '--$boundary--',
      );
    }
  });

  test('multipartUpload handler', () async {
    expectServerMetadata(
      await normal().putBytes(
        Uint8List.fromList(<int>[97]),
        metadata: jsMetadata,
      ),
    );
  });

  group('error handler', () {
    test('passes through unknown errors', () async {
      // The JS test hands 509 to the error handler directly. Through the request layer a 5xx is retried, so a
      // status that is not retried stands in for it; the 5xx path is in errors_conformance_test.dart.
      respond = (_) async => http.Response('conflict', 409);
      await expectLater(
        normal().metadata(),
        throwsA(
          isA<FirebaseStorageException>()
              .having((FirebaseStorageException e) => e.code, 'code', 'unknown')
              .having(
                (FirebaseStorageException e) => e.httpStatus,
                'status',
                409,
              ),
        ),
      );
    });

    test('converts 404 to not found', () async {
      respond = (_) async => http.Response('', 404);
      await expectLater(
        normal().metadata(),
        throwsStorageCode('object-not-found'),
      );
    });

    test('converts 402 to quota exceeded', () async {
      respond = (_) async => http.Response('', 402);
      await expectLater(
        normal().metadata(),
        throwsStorageCode('quota-exceeded'),
      );
    });
  });
}
