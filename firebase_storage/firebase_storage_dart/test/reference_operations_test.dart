import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'fakes.dart';

// The request of each operation and the handling of its response, after requests.test.ts and
// reference.test.ts of the JS SDK.
void main() {
  late FirebaseApp app;
  late List<Recorded> requests;
  late Future<http.Response> Function(Recorded request) respond;
  late FirebaseStorage storage;

  const String origin = 'https://firebasestorage.googleapis.com';

  setUp(() {
    app = newApp();
    requests = <Recorded>[];
    respond = (_) => json(serverResource);
    storage = storageWith(app, (Recorded r) => respond(r), requests: requests);
  });

  tearDown(() async {
    storage.close();
    await app.delete();
  });

  final FullMetadata expectedMetadata = FullMetadata(
    bucket: 'b',
    fullPath: 'foo/bar/baz.png',
    generation: '1',
    metageneration: '2',
    size: 10,
    md5Hash: 'deadbeef',
    timeCreated: DateTime.utc(2026, 11, 20, 10),
    updated: DateTime.utc(2026, 11, 21, 11, 30, 0, 500),
    cacheControl: 'max-age=604800',
    contentDisposition: 'Attachment; filename=baz.png',
    contentLanguage: 'en-US',
    contentType: 'application/jason',
    customMetadata: const <String, String>{'foo': 'bar'},
    downloadTokens: const <String>['a', 'b', 'c'],
  );

  group('metadata', () {
    test('GET of the object URL, escaped', () async {
      expect(await storage.ref('o').metadata(), expectedMetadata);
      await storage.refFromUrl('gs://b/o?').metadata();
      expect(requests.map((Recorded r) => '${r.method} ${r.url}'), <String>[
        'GET $origin/v0/b/b/o/o',
        'GET $origin/v0/b/b/o/o%3F',
      ]);
      expect(requests.first.bodyBytes, isEmpty);
    });

    test('a nested path is one escaped component', () async {
      await storage.ref('a/b c.png').metadata();
      expect(requests.single.url.toString(), '$origin/v0/b/b/o/a%2Fb%20c.png');
    });

    test('reads the fields with types', () async {
      final FullMetadata metadata = await storage.ref('o').metadata();
      expect(metadata.name, 'baz.png');
      expect(metadata.size, 10);
      expect(metadata.timeCreated, DateTime.utc(2026, 11, 20, 10));
      expect(metadata.contentEncoding, isNull);
      expect(metadata.toJson(), <String, Object?>{
        'bucket': 'b',
        'fullPath': 'foo/bar/baz.png',
        'name': 'baz.png',
        'generation': '1',
        'metageneration': '2',
        'size': 10,
        'md5Hash': 'deadbeef',
        'timeCreated': '2026-11-20T10:00:00.000Z',
        'updated': '2026-11-21T11:30:00.500Z',
        'cacheControl': 'max-age=604800',
        'contentDisposition': 'Attachment; filename=baz.png',
        'contentLanguage': 'en-US',
        'contentType': 'application/jason',
        'customMetadata': <String, String>{'foo': 'bar'},
        'downloadTokens': <String>['a', 'b', 'c'],
      });
      expect(metadata.toString(), isNot(contains('a, b, c')));
    });

    test('a resource without optional fields', () async {
      respond = (_) => json(<String, Object?>{'name': 'x', 'size': 5});
      final FullMetadata metadata = await storage.ref('x').metadata();
      expect(metadata.bucket, 'b');
      expect(metadata.size, 5);
      expect(metadata.downloadTokens, isEmpty);
      expect(metadata.customMetadata, isNull);
    });

    test('a body that is not a JSON object is unknown', () async {
      for (final String body in <String>['[]', 'not json', '']) {
        respond = (_) async => http.Response(body, 200);
        await expectLater(
          storage.ref('o').metadata(),
          throwsStorageCode('unknown'),
          reason: body,
        );
      }
    });
  });

  group('updateMetadata', () {
    test('PATCH with the given fields only', () async {
      final FullMetadata result = await storage
          .ref('o')
          .updateMetadata(
            const SettableMetadata(
              contentType: 'application/jason',
              customMetadata: <String, String>{'foo': 'bar'},
            ),
          );
      expect(result, expectedMetadata);
      final Recorded request = requests.single;
      expect(request.method, 'PATCH');
      expect(request.url.toString(), '$origin/v0/b/b/o/o');
      expect(
        request.headers['Content-Type'],
        'application/json; charset=utf-8',
      );
      expect(
        request.body,
        '{"contentType":"application/jason","metadata":{"foo":"bar"}}',
      );
    });

    test('sends the deleted fields as null', () async {
      await storage
          .ref('o')
          .updateMetadata(
            const SettableMetadata(
              cacheControl: 'no-cache',
              contentLanguage: 'ignored',
              delete: <MetadataField>{
                MetadataField.contentLanguage,
                MetadataField.customMetadata,
              },
            ),
          );
      expect(
        requests.single.body,
        '{"cacheControl":"no-cache","contentLanguage":null,"metadata":null}',
      );
    });

    test('a null custom value removes that key, the others are set', () async {
      await storage
          .ref('o')
          .updateMetadata(
            const SettableMetadata(
              customMetadata: <String, String?>{'gone': null, 'kept': 'v'},
            ),
          );
      expect(requests.single.body, '{"metadata":{"gone":null,"kept":"v"}}');
    });

    test('an upload leaves out the custom keys with a null value', () async {
      await storage
          .ref('o')
          .putBytes(
            Uint8List(0),
            metadata: const SettableMetadata(
              customMetadata: <String, String?>{'gone': null, 'kept': 'v'},
            ),
          );
      expect(
        requests.single.body,
        contains(
          '{"name":"o","contentType":"application/octet-stream","metadata":{"kept":"v"}}',
        ),
      );
    });

    test('equality tells a null value from a missing key', () {
      const SettableMetadata withNull = SettableMetadata(
        customMetadata: <String, String?>{'a': null},
      );
      const SettableMetadata other = SettableMetadata(
        customMetadata: <String, String?>{'b': null},
      );
      expect(withNull, isNot(other));
      expect(
        withNull,
        const SettableMetadata(customMetadata: <String, String?>{'a': null}),
      );
      expect(
        withNull.hashCode,
        const SettableMetadata(
          customMetadata: <String, String?>{'a': null},
        ).hashCode,
      );
    });

    test('every field, in the order of the JS SDK', () async {
      await storage
          .ref('o')
          .updateMetadata(
            const SettableMetadata(
              customMetadata: <String, String>{'k': 'v'},
              contentType: 'ct',
              contentLanguage: 'cl',
              contentEncoding: 'ce',
              contentDisposition: 'cd',
              cacheControl: 'cc',
            ),
          );
      expect(
        requests.single.body,
        '{"cacheControl":"cc","contentDisposition":"cd","contentEncoding":"ce",'
        '"contentLanguage":"cl","contentType":"ct","metadata":{"k":"v"}}',
      );
    });
  });

  group('downloadUrl', () {
    test(
      'built from the first token, the bucket and the name of the response',
      () async {
        expect(
          await storage.ref('o').downloadUrl(),
          '$origin/v0/b/b/o/foo%2Fbar%2Fbaz.png?alt=media&token=a',
        );
        expect(requests.single.method, 'GET');
        expect(requests.single.url.toString(), '$origin/v0/b/b/o/o');
      },
    );

    test('escapes the token', () async {
      respond = (_) => json(<String, Object?>{
        'bucket': 'b',
        'name': 'x',
        'downloadTokens': 'a&b=c',
      });
      expect(
        await storage.ref('x').downloadUrl(),
        '$origin/v0/b/b/o/x?alt=media&token=a%26b%3Dc',
      );
    });

    test('uses the emulator origin', () async {
      final FirebaseApp other = newApp();
      addTearDown(other.delete);
      final FirebaseStorage emulated = storageWith(
        other,
        (_) => json(serverResource),
        emulatorHost: '127.0.0.1:9199',
        requests: requests,
      );
      addTearDown(emulated.close);
      expect(
        await emulated.ref('o').downloadUrl(),
        'http://127.0.0.1:9199/v0/b/b/o/foo%2Fbar%2Fbaz.png?alt=media&token=a',
      );
      expect(
        requests.single.url.toString(),
        'http://127.0.0.1:9199/v0/b/b/o/o',
      );
    });

    test('no tokens is no-download-url', () async {
      for (final Object? tokens in <Object?>[null, '', ',', 3]) {
        respond = (_) => json(<String, Object?>{
          'bucket': 'b',
          'name': 'x',
          'downloadTokens': tokens,
        });
        await expectLater(
          storage.ref('x').downloadUrl(),
          throwsStorageCode('no-download-url'),
          reason: '$tokens',
        );
      }
    });
  });

  group('delete', () {
    test('DELETE of the object URL; 200 and 204 succeed', () async {
      for (final int status in <int>[200, 204]) {
        respond = (_) async => http.Response('', status);
        await storage.ref('o?').delete();
      }
      expect(requests.map((Recorded r) => '${r.method} ${r.url}'), <String>[
        'DELETE $origin/v0/b/b/o/o%3F',
        'DELETE $origin/v0/b/b/o/o%3F',
      ]);
    });

    test('404 is object-not-found with the status', () async {
      respond = (_) async => http.Response('{"error":{"code":404}}', 404);
      await expectLater(
        storage.ref('o').delete(),
        throwsA(
          isA<FirebaseStorageException>()
              .having(
                (FirebaseStorageException e) => e.code,
                'code',
                'object-not-found',
              )
              .having(
                (FirebaseStorageException e) => e.httpStatus,
                'httpStatus',
                404,
              )
              .having(
                (FirebaseStorageException e) => e.serverResponse,
                'serverResponse',
                '{"error":{"code":404}}',
              )
              .having(
                (FirebaseStorageException e) => e.message,
                'message',
                "Object 'o' does not exist.",
              ),
        ),
      );
    });
  });

  group('list', () {
    test('root: prefix is empty, delimiter /', () async {
      respond = (_) => json(<String, Object?>{});
      final ListResult result = await storage.ref().list();
      expect(requests.single.method, 'GET');
      expect(
        requests.single.url.toString(),
        '$origin/v0/b/b/o?prefix=&delimiter=%2F',
      );
      expect(result.items, isEmpty);
      expect(result.prefixes, isEmpty);
      expect(result.nextPageToken, isNull);
    });

    test('a path, a page token and maxResults, escaped', () async {
      respond = (_) => json(<String, Object?>{});
      await storage
          .ref('o')
          .list(pageToken: 'pageToken-afeafeagef', maxResults: 13);
      await storage
          .refFromUrl('gs://b/o?')
          .list(pageToken: 'a/b', maxResults: 1000);
      expect(requests.map((Recorded r) => r.url.toString()), <String>[
        '$origin/v0/b/b/o?prefix=o%2F&delimiter=%2F&pageToken=pageToken-afeafeagef&maxResults=13',
        '$origin/v0/b/b/o?prefix=o%3F%2F&delimiter=%2F&pageToken=a%2Fb&maxResults=1000',
      ]);
    });

    test('reads prefixes, items and the next page token', () async {
      respond = (_) => json(<String, Object?>{
        'prefixes': <String>['a/f/'],
        'items': <Object?>[
          <String, Object?>{'name': 'a/a', 'bucket': 'b'},
          <String, Object?>{'name': 'a/b', 'bucket': 'other'},
        ],
        'nextPageToken': 'YS9mLw==',
      });
      final ListResult result = await storage.ref('a').list();
      expect(result.prefixes.map((Reference r) => r.fullPath), <String>['a/f']);
      expect(result.items.map((Reference r) => r.fullPath), <String>[
        'a/a',
        'a/b',
      ]);
      expect(result.items.map((Reference r) => r.bucket), <String>['b', 'b']);
      expect(result.nextPageToken, 'YS9mLw==');
    });

    test('items are in the bucket of the request', () async {
      respond = (_) => json(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{'name': 'a/a', 'bucket': 'c'},
        ],
      });
      final ListResult result = await storage.refFromUrl('gs://c').list();
      expect(result.items.single.bucket, 'c');
    });

    test('rejects maxResults out of range before any request', () async {
      for (final int max in <int>[0, -4, 1001]) {
        await expectLater(
          storage.ref('hello').list(maxResults: max),
          throwsStorageCode('invalid-argument'),
          reason: '$max',
        );
      }
      expect(requests, isEmpty);
    });

    test('404 stays unknown (shared error handler)', () async {
      respond = (_) async => http.Response('not found', 404);
      await expectLater(
        storage.ref('a').list(),
        throwsA(
          isA<FirebaseStorageException>()
              .having((FirebaseStorageException e) => e.code, 'code', 'unknown')
              .having(
                (FirebaseStorageException e) => e.httpStatus,
                'httpStatus',
                404,
              ),
        ),
      );
    });

    test('a body that is not a JSON object is unknown', () async {
      respond = (_) async => http.Response('[1]', 200);
      await expectLater(storage.ref('a').list(), throwsStorageCode('unknown'));
    });

    test('listAll follows the pages and collects prefixes and items', () async {
      int page = 0;
      respond = (_) {
        page++;
        return json(<String, Object?>{
          'prefixes': <String>['p$page/'],
          'items': <Object?>[
            <String, Object?>{'name': 'i$page'},
          ],
          if (page < 3) 'nextPageToken': 't$page',
        });
      };
      final ListResult all = await storage.ref().listAll();
      expect(all.items.map((Reference r) => r.fullPath), <String>[
        'i1',
        'i2',
        'i3',
      ]);
      expect(all.prefixes.map((Reference r) => r.fullPath), <String>[
        'p1',
        'p2',
        'p3',
      ]);
      expect(all.nextPageToken, isNull);
      expect(
        requests.map((Recorded r) => r.url.queryParameters['pageToken']),
        <String?>[null, 't1', 't2'],
      );
      expect(
        requests.every(
          (Recorded r) => !r.url.queryParameters.containsKey('maxResults'),
        ),
        isTrue,
      );
    });

    test('an empty next page token ends the listing', () async {
      respond = (_) => json(<String, Object?>{'nextPageToken': ''});
      await storage.ref().listAll();
      expect(requests, hasLength(1));
    });

    test('a repeated next page token ends listAll with unknown', () async {
      respond = (_) => json(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{'name': 'i'},
        ],
        'nextPageToken': 'same',
      });
      await expectLater(storage.ref().listAll(), throwsStorageCode('unknown'));
      expect(requests, hasLength(2));
    });

    test(
      'listPages requests a page only when the previous one was taken',
      () async {
        int page = 0;
        respond = (_) {
          page++;
          return json(<String, Object?>{'nextPageToken': 't$page'});
        };
        final List<ListResult> pages = await storage
            .ref()
            .listPages(pageSize: 2)
            .take(2)
            .toList();
        expect(pages.map((ListResult p) => p.nextPageToken), <String>[
          't1',
          't2',
        ]);
        expect(requests, hasLength(2));
        expect(
          requests.map((Recorded r) => r.url.queryParameters['maxResults']),
          <String>['2', '2'],
        );
      },
    );
  });

  group('getBytes', () {
    test('GET with alt=media and no Range', () async {
      respond = (_) async => http.Response.bytes(<int>[1, 128, 255], 200);
      expect(await storage.ref('o').getBytes(), <int>[1, 128, 255]);
      expect(requests.single.url.toString(), '$origin/v0/b/b/o/o?alt=media');
      expect(requests.single.headers.containsKey('Range'), isFalse);
    });

    test('maxSize asks for one byte more and accepts 206', () async {
      respond = (_) async => http.Response.bytes(<int>[1, 2, 3], 206);
      expect(await storage.ref('o').getBytes(maxSize: 3), <int>[1, 2, 3]);
      expect(requests.single.headers['Range'], 'bytes=0-3');
    });

    test('an object larger than maxSize is download-size-exceeded', () async {
      respond = (_) async => http.Response.bytes(<int>[1, 2, 3, 4], 206);
      await expectLater(
        storage.ref('o').getBytes(maxSize: 3),
        throwsStorageCode('download-size-exceeded'),
      );
    });

    test('a server that ignores Range for a small file', () async {
      respond = (_) async => http.Response.bytes(<int>[1, 2], 200);
      expect(await storage.ref('o').getBytes(maxSize: 10), <int>[1, 2]);
    });

    test('206 without maxSize is not a success', () async {
      respond = (_) async => http.Response.bytes(<int>[1], 206);
      await expectLater(
        storage.ref('o').getBytes(),
        throwsStorageCode('unknown'),
      );
    });

    test('negative maxSize is invalid-argument', () async {
      await expectLater(
        storage.ref('o').getBytes(maxSize: -1),
        throwsStorageCode('invalid-argument'),
      );
      expect(requests, isEmpty);
    });

    test('416 is unknown with the status', () async {
      respond = (_) async => http.Response('', 416);
      await expectLater(
        storage.ref('o').getBytes(maxSize: 0),
        throwsA(
          isA<FirebaseStorageException>()
              .having((FirebaseStorageException e) => e.code, 'code', 'unknown')
              .having(
                (FirebaseStorageException e) => e.httpStatus,
                'httpStatus',
                416,
              ),
        ),
      );
    });

    test('404 is object-not-found', () async {
      respond = (_) async => http.Response('', 404);
      await expectLater(
        storage.ref('o').getBytes(),
        throwsStorageCode('object-not-found'),
      );
    });
  });

  group('putBytes', () {
    final RegExp boundaryRegExp = RegExp(
      r'^multipart/related; boundary=([A-Za-z0-9]+)$',
    );

    String multipartBody(
      String boundary,
      String metadataJson,
      String contentType,
      String data,
    ) =>
        '--$boundary\r\n'
        'Content-Type: application/json; charset=utf-8\r\n\r\n'
        '$metadataJson\r\n'
        '--$boundary\r\n'
        'Content-Type: $contentType\r\n\r\n'
        '$data\r\n'
        '--$boundary--';

    test('a multipart POST, escaped', () async {
      const SettableMetadata metadata = SettableMetadata(
        contentType: 'application/jason',
        customMetadata: <String, String>{'foo': 'bar'},
      );
      for (final Reference ref in <Reference>[
        storage.ref('o'),
        storage.refFromUrl('gs://b/o?'),
      ]) {
        expect(
          await ref.putBytes(Uint8List.fromList(<int>[97]), metadata: metadata),
          expectedMetadata,
        );
      }
      expect(requests.map((Recorded r) => '${r.method} ${r.url}'), <String>[
        'POST $origin/v0/b/b/o?name=o',
        'POST $origin/v0/b/b/o?name=o%3F',
      ]);
      for (final (int i, String name) in <(int, String)>[(0, 'o'), (1, 'o?')]) {
        final Recorded request = requests[i];
        expect(request.headers['X-Goog-Upload-Protocol'], 'multipart');
        final RegExpMatch? match = boundaryRegExp.firstMatch(
          request.headers['Content-Type']!,
        );
        expect(match, isNotNull);
        expect(
          request.body,
          multipartBody(
            match!.group(1)!,
            jsonEncode(<String, Object?>{
              'name': name,
              'contentType': 'application/jason',
              'metadata': <String, String>{'foo': 'bar'},
            }),
            'application/jason',
            'a',
          ),
        );
      }
    });

    test('defaults the content type to application/octet-stream', () async {
      await storage.ref('a/b').putBytes(Uint8List(0));
      final Recorded request = requests.single;
      final String boundary = boundaryRegExp
          .firstMatch(request.headers['Content-Type']!)!
          .group(1)!;
      expect(
        request.body,
        multipartBody(
          boundary,
          '{"name":"a/b","contentType":"application/octet-stream"}',
          'application/octet-stream',
          '',
        ),
      );
      expect(request.url.toString(), '$origin/v0/b/b/o?name=a%2Fb');
    });

    test('sends the binary content unchanged', () async {
      await storage
          .ref('bin')
          .putBytes(Uint8List.fromList(<int>[0, 255, 13, 10]));
      final List<int> body = requests.single.bodyBytes;
      final int start = body.indexOf(0);
      expect(body.sublist(start, start + 4), <int>[0, 255, 13, 10]);
    });

    test('sends every settable field', () async {
      await storage
          .ref('o')
          .putBytes(
            Uint8List(0),
            metadata: const SettableMetadata(
              cacheControl: 'cc',
              contentDisposition: 'cd',
              contentEncoding: 'ce',
              contentLanguage: 'cl',
              delete: <MetadataField>{MetadataField.cacheControl},
            ),
          );
      expect(
        requests.single.body,
        contains(
          '{"name":"o","cacheControl":"cc","contentDisposition":"cd","contentEncoding":"ce",'
          '"contentLanguage":"cl","contentType":"application/octet-stream"}',
        ),
      );
    });

    test('404 stays unknown (shared error handler)', () async {
      respond = (_) async => http.Response('', 404);
      await expectLater(
        storage.ref('o').putBytes(Uint8List(1)),
        throwsStorageCode('unknown'),
      );
    });
  });

  group('putString', () {
    test('raw uses metadata.contentType', () async {
      await storage
          .ref('test')
          .putString(
            'hello',
            metadata: const SettableMetadata(contentType: 'lol/wut'),
          );
      expect(requests.single.body, contains('"contentType":"lol/wut"'));
      expect(requests.single.body, contains('\r\n\r\nhello\r\n'));
    });

    test('data URL uses its embedded content type', () async {
      await storage
          .ref('test')
          .putString('data:lol/wat;base64,aaaa', format: StringFormat.dataUrl);
      expect(requests.single.body, contains('"contentType":"lol/wat"'));
      expect(requests.single.body, contains('Content-Type: lol/wat\r\n'));
    });

    test('metadata.contentType overrides the embedded content type', () async {
      await storage
          .ref('test')
          .putString(
            'data:ignore/me;base64,aaaa',
            format: StringFormat.dataUrl,
            metadata: const SettableMetadata(
              contentType: 'tomato/soup',
              cacheControl: 'cc',
            ),
          );
      expect(requests.single.body, contains('"contentType":"tomato/soup"'));
      expect(requests.single.body, contains('"cacheControl":"cc"'));
    });

    test('a data URL keeps the other metadata', () async {
      await storage
          .ref('test')
          .putString(
            'data:text/plain,hi',
            format: StringFormat.dataUrl,
            metadata: const SettableMetadata(cacheControl: 'cc'),
          );
      expect(
        requests.single.body,
        contains('"cacheControl":"cc","contentType":"text/plain"'),
      );
    });

    test('base64 and base64url are decoded', () async {
      await storage.ref('a').putString('aGk=', format: StringFormat.base64);
      await storage.ref('b').putString('aGk', format: StringFormat.base64Url);
      for (final Recorded request in requests) {
        expect(request.body, contains('\r\n\r\nhi\r\n'));
      }
    });

    test('an invalid string is invalid-format, before any request', () async {
      await expectLater(
        storage.ref('a').putString('a-b', format: StringFormat.base64),
        throwsStorageCode('invalid-format'),
      );
      expect(requests, isEmpty);
    });
  });

  group('root operations throw invalid-root-operation', () {
    final Map<String, Future<Object?> Function(Reference root)> operations =
        <String, Future<Object?> Function(Reference)>{
          'metadata': (Reference r) => r.metadata(),
          'updateMetadata': (Reference r) =>
              r.updateMetadata(const SettableMetadata()),
          'downloadUrl': (Reference r) => r.downloadUrl(),
          'delete': (Reference r) => r.delete(),
          'getBytes': (Reference r) => r.getBytes(),
          'putBytes': (Reference r) => r.putBytes(Uint8List(0)),
          'putString': (Reference r) => r.putString('raw'),
        };
    for (final MapEntry<String, Future<Object?> Function(Reference)> entry
        in operations.entries) {
      test(entry.key, () async {
        await expectLater(
          () => entry.value(storage.ref()),
          throwsA(
            isA<FirebaseStorageException>()
                .having(
                  (FirebaseStorageException e) => e.code,
                  'code',
                  'invalid-root-operation',
                )
                .having(
                  (FirebaseStorageException e) => e.message,
                  'message',
                  contains("'${entry.key}'"),
                ),
          ),
        );
        expect(requests, isEmpty);
      });
    }
  });

  group('error mapping', () {
    Future<FirebaseStorageException> errorOf(
      int status,
      String body, {
      bool object = true,
    }) async {
      respond = (_) async => http.Response(body, status);
      try {
        if (object) {
          await storage.ref('dir/o').metadata();
        } else {
          await storage.ref('dir').list();
        }
      } on FirebaseStorageException catch (e) {
        return e;
      }
      fail('No exception for $status');
    }

    test('401 is unauthenticated', () async {
      final FirebaseStorageException e = await errorOf(
        401,
        '{"error":{"code":401}}',
      );
      expect(e.code, 'unauthenticated');
      expect(e.httpStatus, 401);
      expect(e.serverResponse, '{"error":{"code":401}}');
    });

    test('401 with the App Check message is unauthorized-app', () async {
      final FirebaseStorageException e = await errorOf(
        401,
        '{"error":{"code":401,"message":"Firebase App Check token is invalid."}}',
      );
      expect(e.code, 'unauthorized-app');
    });

    test('402 is quota-exceeded', () async {
      final FirebaseStorageException e = await errorOf(402, '');
      expect(e.code, 'quota-exceeded');
      expect(e.message, contains("bucket 'b'"));
      expect(e.httpStatus, 402);
    });

    test('403 is unauthorized', () async {
      final FirebaseStorageException e = await errorOf(403, 'denied');
      expect(e.code, 'unauthorized');
      expect(e.message, "User does not have permission to access 'dir/o'.");
      expect(
        e.toString(),
        '[firebase_storage/unauthorized] ${e.message} (HTTP 403)\ndenied',
      );
    });

    test(
      '404 is object-not-found on object operations, unknown on list',
      () async {
        expect((await errorOf(404, '')).code, 'object-not-found');
        expect((await errorOf(404, '', object: false)).code, 'unknown');
      },
    );

    test('other statuses are unknown with the status', () async {
      for (final int status in <int>[400, 409, 412]) {
        final FirebaseStorageException e = await errorOf(status, 'bad');
        expect(e.code, 'unknown', reason: '$status');
        expect(e.httpStatus, status);
        expect(e.serverResponse, 'bad');
      }
    });

    test('the shared mapping also applies to list', () async {
      expect((await errorOf(401, '', object: false)).code, 'unauthenticated');
      expect((await errorOf(402, '', object: false)).code, 'quota-exceeded');
      expect((await errorOf(403, '', object: false)).code, 'unauthorized');
    });
  });
}
