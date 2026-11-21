@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../fakes.dart';

// Pins every difference between the Storage emulator and production that emulator_probe.md lists (probed with
// firebase-tools 15.18.0), so that an emulator upgrade that changes one of them fails here first. Each group
// names the item of the probe's "Differences from production" list.
//
// Needs the emulator of tool/start_storage_emulator.sh:
//
//     STORAGE_HUB_PORT=9486 STORAGE_LOGGING_PORT=9586 tool/start_storage_emulator.sh 9386
//     FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9386 dart test test/integration/emulator_conformance_test.dart
//     tool/stop_storage_emulator.sh 9386
final String? _host = Platform.environment['FIREBASE_STORAGE_EMULATOR_HOST'];

const String _open = 'demo-test.appspot.com';
const String _auth = 'demo-test-auth.appspot.com';

/// An unsigned JWT like those of the Auth emulator: `{"alg":"none"}`, [claims], empty signature.
String _jwt(Map<String, Object?> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part(<String, String>{'alg': 'none', 'typ': 'JWT'})}.${part(claims)}.';
}

void main() {
  final String? host = _host;
  if (host == null) {
    test(
      'emulator conformance',
      () {},
      skip:
          'FIREBASE_STORAGE_EMULATOR_HOST is not set; see the comment at the top of the file',
    );
    return;
  }

  final String run = 'conformance/${DateTime.now().microsecondsSinceEpoch}';
  late FirebaseApp app;
  late FirebaseStorage storage;
  late http.Client raw;

  String objectUrl(String path, {String bucket = _open}) =>
      'http://$host/v0/b/$bucket/o/${Uri.encodeComponent(path)}';
  String collectionUrl({String bucket = _open}) =>
      'http://$host/v0/b/$bucket/o';

  Future<Map<String, Object?>> upload(
    String path,
    String content, {
    String bucket = _open,
    String? token = 'owner',
  }) async {
    final http.Response response = await raw.post(
      Uri.parse(
        '${collectionUrl(bucket: bucket)}?name=${Uri.encodeQueryComponent(path)}',
      ),
      headers: <String, String>{
        'Authorization': ?(token == null ? null : 'Firebase $token'),
      },
      body: content,
    );
    expect(response.statusCode, 200, reason: response.body);
    return jsonDecode(response.body) as Map<String, Object?>;
  }

  setUpAll(() {
    raw = http.Client();
  });

  tearDownAll(() {
    raw.close();
  });

  setUp(() {
    app = newApp(storageBucket: _open);
    storage = FirebaseStorage(app, emulatorHost: host);
  });

  tearDown(() async {
    storage.close();
    await app.delete();
  });

  // The two raw hang requests leave the emulator's rules runtime broken ("no Storage ruleset is
  // currently loaded"), so every later request on the same emulator is denied. They run only on an
  // emulator of their own, with STORAGE_EMULATOR_HANG_TESTS=1.
  final bool hangTestsEnabled =
      Platform.environment['STORAGE_EMULATOR_HANG_TESTS'] == '1';

  group('1. requests that never get an answer', () {
    Future<void> expectHang(http.BaseRequest request) async {
      final http.Client client = http.Client();
      try {
        await expectLater(
          client.send(request).timeout(const Duration(seconds: 3)),
          throwsA(isA<TimeoutException>()),
        );
      } finally {
        client.close();
      }
    }

    // Registered only when enabled: a skip would fail the CI job, which treats skips as a missing emulator.
    if (hangTestsEnabled) {
      test('a media upload with a JSON content type hangs', () async {
        await expectHang(
          http.Request(
              'POST',
              Uri.parse('${collectionUrl()}?name=$run%2Fhang.json'),
            )
            ..headers['Content-Type'] = 'application/json'
            ..body = '{"a":1}',
        );
      });

      test('a delimiter other than / hangs', () async {
        await expectHang(
          http.Request(
            'GET',
            Uri.parse('${collectionUrl()}?prefix=&delimiter=sub'),
          ),
        );
      });
    }

    test(
      'the client bounds the wait with requestTimeout (it sends only delimiter=/)',
      () async {
        final FirebaseStorage bounded = FirebaseStorage(
          app,
          emulatorHost: host,
          requestTimeout: const Duration(seconds: 1),
          retry: const StorageRetryPolicy(operation: Duration.zero),
        );
        addTearDown(bounded.close);
        // A list works: the client never sends another delimiter.
        await bounded.ref(run).list();
      },
    );
  });

  group('2. error bodies are plain text, not the GCS JSON envelope', () {
    test(
      '404 is text/plain "Not Found" for get, media, PATCH and DELETE',
      () async {
        final String url = objectUrl('$run/missing.txt');
        final List<http.Response> responses = <http.Response>[
          await raw.get(Uri.parse(url)),
          await raw.get(Uri.parse('$url?alt=media')),
          await raw.patch(
            Uri.parse(url),
            headers: <String, String>{'Content-Type': 'application/json'},
            body: '{}',
          ),
          await raw.delete(Uri.parse(url)),
        ];
        for (final http.Response response in responses) {
          expect(response.statusCode, 404);
          expect(response.headers['content-type'], startsWith('text/plain'));
          expect(response.body, 'Not Found');
        }
      },
    );

    test(
      'the client maps it to object-not-found with the status and the text body',
      () async {
        await expectLater(
          storage.ref('$run/missing.txt').metadata(),
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
                  'Not Found',
                ),
          ),
        );
      },
    );

    test('403 uses the JSON envelope', () async {
      final http.Response response = await raw.get(
        Uri.parse(objectUrl('users/u1/x', bucket: _auth)),
      );
      expect(response.statusCode, 403);
      expect(response.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(response.body), <String, Object?>{
        'error': <String, Object?>{
          'code': 403,
          'message': 'Permission denied. No READ permission.',
        },
      });
    });

    test(
      'a list prefix that does not end in / is a 400 with the JSON envelope',
      () async {
        final http.Response response = await raw.get(
          Uri.parse('${collectionUrl()}?prefix=abc'),
        );
        expect(response.statusCode, 400);
        expect((jsonDecode(response.body) as Map<String, Object?>)['error'], <
          String,
          Object?
        >{
          'code': 400,
          'message':
              'The prefix parameter is required to be empty or ends with a single / character.',
        });
      },
    );
  });

  group('3. Range', () {
    late String url;

    setUpAll(() async {
      await upload('$run/range.txt', 'hello world');
      url = '${objectUrl('$run/range.txt')}?alt=media';
    });

    Future<http.Response> get(String range) =>
        raw.get(Uri.parse(url), headers: <String, String>{'Range': range});

    test('a satisfiable range is 206 with Content-Range', () async {
      final http.Response response = await get('bytes=0-4');
      expect(response.statusCode, 206);
      expect(response.headers['content-range'], 'bytes 0-4/11');
      expect(response.body, 'hello');
      expect((await get('bytes=6-')).headers['content-range'], 'bytes 6-10/11');
      expect((await get('bytes=-3')).headers['content-range'], 'bytes 8-10/11');
    });

    test(
      'an unsatisfiable or inverted range is 200 with the whole body (production: 416)',
      () async {
        for (final String range in <String>['bytes=99-100', 'bytes=5-2']) {
          final http.Response response = await get(range);
          expect(response.statusCode, 200, reason: range);
          expect(response.body, 'hello world', reason: range);
        }
      },
    );

    test(
      'a multi-range answers the first range only, not multipart/byteranges',
      () async {
        final http.Response response = await get('bytes=0-1,4-5');
        expect(response.statusCode, 206);
        expect(response.body, 'he');
      },
    );

    test(
      'the client: getBytes(maxSize) asks for one byte more and tells a larger object',
      () async {
        final Reference ref = storage.ref('$run/range.txt');
        expect(utf8.decode(await ref.getBytes(maxSize: 11)), 'hello world');
        await expectLater(
          ref.getBytes(maxSize: 4),
          throwsA(
            isA<FirebaseStorageException>().having(
              (FirebaseStorageException e) => e.code,
              'code',
              'download-size-exceeded',
            ),
          ),
        );
        expect(utf8.decode(await ref.getBytes(maxSize: 1000)), 'hello world');
      },
    );
  });

  group('4. media uploads ignore the request Content-Type', () {
    test('a text/plain media upload is application/octet-stream', () async {
      final http.Response response = await raw.post(
        Uri.parse(
          '${collectionUrl()}?name=${Uri.encodeQueryComponent('$run/media.txt')}',
        ),
        headers: <String, String>{'Content-Type': 'text/plain'},
        body: 'x',
      );
      expect(response.statusCode, 200);
      expect(
        (jsonDecode(response.body) as Map<String, Object?>)['contentType'],
        'application/octet-stream',
      );
    });

    test('a multipart upload of the client keeps its content type', () async {
      final FullMetadata metadata = await storage
          .ref('$run/multipart.txt')
          .putString(
            'x',
            metadata: const SettableMetadata(contentType: 'text/x-mine'),
          );
      expect(metadata.contentType, 'text/x-mine');
    });

    test(
      'the uploadType=multipart query alone is ignored (the header selects multipart)',
      () async {
        final http.Response response = await raw.post(
          Uri.parse(
            '${collectionUrl()}?uploadType=multipart&name=${Uri.encodeQueryComponent('$run/q.txt')}',
          ),
          body: 'plain bytes',
        );
        expect(response.statusCode, 200);
        expect(
          (jsonDecode(response.body) as Map<String, Object?>)['size'],
          '11',
        );
      },
    );
  });

  group('5. list', () {
    late String prefix;

    setUpAll(() async {
      prefix = '$run/list';
      for (final String name in <String>['a.txt', 'b.txt', 'sub/c.txt']) {
        await upload('$prefix/$name', name);
      }
    });

    test(
      'nextPageToken is the name of the first object of the next page; items are name and bucket',
      () async {
        final http.Response response = await raw.get(
          Uri.parse(
            '${collectionUrl()}?prefix=${Uri.encodeQueryComponent('$prefix/')}&delimiter=%2F&maxResults=1',
          ),
        );
        final Map<String, Object?> body =
            jsonDecode(response.body) as Map<String, Object?>;
        expect(body['nextPageToken'], '$prefix/b.txt');
        expect(body['items'], <Object?>[
          <String, Object?>{'name': '$prefix/a.txt', 'bucket': _open},
        ]);
        expect(body['prefixes'], <Object?>['$prefix/sub/']);
      },
    );

    test(
      'the last page has no nextPageToken; the prefixes come again on every page',
      () async {
        final http.Response response = await raw.get(
          Uri.parse(
            '${collectionUrl()}?prefix=${Uri.encodeQueryComponent('$prefix/')}&delimiter=%2F'
            '&pageToken=${Uri.encodeQueryComponent('$prefix/b.txt')}',
          ),
        );
        final Map<String, Object?> body =
            jsonDecode(response.body) as Map<String, Object?>;
        expect(body.containsKey('nextPageToken'), isFalse);
        expect(body['items'], <Object?>[
          <String, Object?>{'name': '$prefix/b.txt', 'bucket': _open},
        ]);
        // emulator_probe.md said first page only; with a pageToken they repeat (firebase-tools 15.18.0).
        expect(body['prefixes'], <Object?>['$prefix/sub/']);
      },
    );

    test('maxResults=0 is an empty page with a token', () async {
      final http.Response response = await raw.get(
        Uri.parse(
          '${collectionUrl()}?prefix=${Uri.encodeQueryComponent('$prefix/')}&delimiter=%2F&maxResults=0',
        ),
      );
      final Map<String, Object?> body =
          jsonDecode(response.body) as Map<String, Object?>;
      expect(body['items'], isEmpty);
      expect(body['nextPageToken'], isA<String>());
    });

    test('the client pages through it and gets references only', () async {
      final List<ListResult> pages = await storage
          .ref(prefix)
          .listPages(pageSize: 1)
          .toList();
      expect(
        pages.expand((ListResult p) => p.items).map((Reference r) => r.name),
        <String>['a.txt', 'b.txt'],
      );
      expect(
        pages
            .expand((ListResult p) => p.prefixes)
            .map((Reference r) => r.fullPath),
        // The emulator repeats the prefix on every page, so collecting the pages repeats it (JS listAll too).
        List<String>.filled(pages.length, '$prefix/sub'),
      );
    });
  });

  group('6. resumable uploads are not checked', () {
    Future<String> start(String path) async {
      final http.Response response = await raw.post(
        Uri.parse('${collectionUrl()}?name=${Uri.encodeQueryComponent(path)}'),
        headers: <String, String>{
          'X-Goog-Upload-Protocol': 'resumable',
          'X-Goog-Upload-Command': 'start',
          'X-Goog-Upload-Header-Content-Length': '999',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode(<String, Object?>{
          'name': path,
          'contentType': 'application/x-test',
        }),
      );
      expect(response.statusCode, 200);
      expect(response.body, 'OK');
      expect(response.headers['x-goog-upload-status'], 'active');
      expect(response.headers['x-goog-upload-chunk-granularity'], '10000');
      final String url = response.headers['x-goog-upload-url']!;
      expect(url, startsWith('http://$host/v0/b/$_open/o?name='));
      expect(url, contains('upload_protocol=resumable'));
      return url;
    }

    Future<http.Response> command(
      String url,
      String command, {
      List<int>? body,
      String? offset,
    }) => raw.post(
      Uri.parse(url),
      headers: <String, String>{
        'X-Goog-Upload-Command': command,
        'X-Goog-Upload-Offset': ?offset,
      },
      body: body,
    );

    test(
      'the offset is ignored, the declared length is not validated, a second finalize is OK',
      () async {
        final String url = await start('$run/resumable.bin');
        final http.Response first = await command(
          url,
          'upload',
          body: utf8.encode('abc'),
          offset: '500',
        );
        expect(first.statusCode, 200);
        expect(first.headers['x-goog-upload-status'], 'active');
        final http.Response query = await command(url, 'query');
        expect(query.headers['x-goog-upload-size-received'], '3');
        final http.Response last = await command(
          url,
          'upload, finalize',
          body: utf8.encode('de'),
          offset: '0',
        );
        expect(last.headers['x-goog-upload-status'], 'final');
        final Map<String, Object?> object =
            jsonDecode(last.body) as Map<String, Object?>;
        expect(object['size'], '5');
        expect(object['contentType'], 'application/x-test');
        final http.Response again = await command(url, 'finalize');
        expect(again.statusCode, 200);
        expect(again.body, 'OK');
        expect((await command(url, 'upload', body: <int>[1])).statusCode, 400);
      },
    );

    test('cancel is 200 while active; an unknown upload id is 404', () async {
      final String url = await start('$run/canceled.bin');
      expect((await command(url, 'cancel')).statusCode, 200);
      final String unknown = url.replaceFirst(
        RegExp('upload_id=[^&]+'),
        'upload_id=nope',
      );
      expect((await command(unknown, 'query')).statusCode, 404);
    });
  });

  group('7. PATCH and generations', () {
    test(
      'PATCH bumps metageneration and updated, not etag; generation is a ms timestamp',
      () async {
        final int before = DateTime.now().millisecondsSinceEpoch;
        final Map<String, Object?> created = await upload(
          '$run/patch.txt',
          'x',
        );
        final int generation = int.parse(created['generation']! as String);
        expect(
          generation,
          inInclusiveRange(
            before - 60000,
            DateTime.now().millisecondsSinceEpoch + 60000,
          ),
        );
        final http.Response response = await raw.patch(
          Uri.parse(objectUrl('$run/patch.txt')),
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{'cacheControl': 'max-age=5'}),
        );
        final Map<String, Object?> patched =
            jsonDecode(response.body) as Map<String, Object?>;
        expect(patched['etag'], created['etag']);
        expect(
          patched['metageneration'],
          '${int.parse(created['metageneration']! as String) + 1}',
        );
        expect(patched['generation'], created['generation']);
      },
    );

    test(
      'a null custom key removes it, the others merge; delete: clears them all',
      () async {
        await storage
            .ref('$run/custom.txt')
            .putString(
              'x',
              metadata: const SettableMetadata(
                customMetadata: <String, String>{'k': '1', 'j': '2'},
              ),
            );
        // The client sends {"metadata":{"k":null,"z":"3"}} like the JS SDK; the emulator merges the rest.
        final FullMetadata merged = await storage
            .ref('$run/custom.txt')
            .updateMetadata(
              const SettableMetadata(
                customMetadata: <String, String?>{'k': null, 'z': '3'},
              ),
            );
        expect(merged.customMetadata, <String, String>{'j': '2', 'z': '3'});
        final FullMetadata cleared = await storage
            .ref('$run/custom.txt')
            .updateMetadata(
              const SettableMetadata(
                delete: <MetadataField>{MetadataField.customMetadata},
              ),
            );
        expect(cleared.customMetadata ?? <String, String>{}, isEmpty);
      },
    );
  });

  group('8. auth tokens are not verified', () {
    FirebaseStorage authStorage(String? token) {
      final FirebaseStorage instance = FirebaseStorage(
        app,
        bucket: _auth,
        emulatorHost: host,
        mockUserToken: token,
      );
      addTearDown(instance.close);
      return instance;
    }

    test('an unsigned JWT with user_id is that user', () async {
      final FirebaseStorage u1 = authStorage(
        _jwt(<String, Object?>{'user_id': 'u1', 'sub': 'u1'}),
      );
      await u1.ref('users/u1/$run.txt').putString('mine');
      final FirebaseStorage u2 = authStorage(
        _jwt(<String, Object?>{'user_id': 'u2', 'sub': 'u2'}),
      );
      await expectLater(
        u2.ref('users/u1/$run.txt').metadata(),
        throwsA(
          isA<FirebaseStorageException>()
              .having(
                (FirebaseStorageException e) => e.code,
                'code',
                'unauthorized',
              )
              .having(
                (FirebaseStorageException e) => e.httpStatus,
                'httpStatus',
                403,
              ),
        ),
      );
      await u2.ref('shared/$run.txt').putString('ours');
    });

    test('a token with sub only, or garbage, is signed out', () async {
      for (final String token in <String>[
        _jwt(<String, Object?>{'sub': 'u3'}),
        'garbage',
      ]) {
        await expectLater(
          authStorage(token).ref('users/u3/$run.txt').putString('x'),
          throwsA(
            isA<FirebaseStorageException>().having(
              (FirebaseStorageException e) => e.code,
              'code',
              'unauthorized',
            ),
          ),
        );
      }
    });

    test('owner is admin, with Firebase or Bearer', () async {
      await authStorage('owner').ref('anywhere/$run.txt').putString('x');
      final http.Response response = await raw.get(
        Uri.parse(objectUrl('anywhere/$run.txt', bucket: _auth)),
        headers: <String, String>{'Authorization': 'Bearer owner'},
      );
      expect(response.statusCode, 200);
    });

    test(
      'rules come before existence: a missing object is 403 signed out, 404 for an allowed user',
      () async {
        await expectLater(
          authStorage(null).ref('users/u1/none-$run').metadata(),
          throwsA(
            isA<FirebaseStorageException>().having(
              (FirebaseStorageException e) => e.code,
              'code',
              'unauthorized',
            ),
          ),
        );
        await expectLater(
          authStorage(
            _jwt(<String, Object?>{'user_id': 'u1'}),
          ).ref('users/u1/none-$run').metadata(),
          throwsA(
            isA<FirebaseStorageException>().having(
              (FirebaseStorageException e) => e.code,
              'code',
              'object-not-found',
            ),
          ),
        );
      },
    );
  });

  group('9. download tokens', () {
    test(
      'each upload gets one token, and downloadUrl serves the object without credentials',
      () async {
        final Reference ref = storage.ref('$run/token.txt');
        final FullMetadata metadata = await ref.putString('tok');
        expect(metadata.downloadTokens, hasLength(1));
        final String url = await ref.downloadUrl();
        expect(
          url,
          startsWith(
            'http://$host/v0/b/$_open/o/${Uri.encodeComponent('$run/token.txt')}?alt=media&token=',
          ),
        );
        expect((await raw.get(Uri.parse(url))).body, 'tok');
      },
    );

    test('token calls need admin credentials', () async {
      await upload('$run/admin.txt', 'x');
      final http.Response response = await raw.post(
        Uri.parse('${objectUrl('$run/admin.txt')}?create_token=true'),
      );
      expect(response.statusCode, 403);
      expect(jsonDecode(response.body), <String, Object?>{
        'error': <String, Object?>{
          'code': 403,
          'message': 'Missing admin credentials.',
        },
      });
    });

    test('deleting the only token issues a new one at once', () async {
      final Map<String, Object?> created = await upload(
        '$run/notoken.txt',
        'x',
      );
      final String token = created['downloadTokens']! as String;
      final http.Response deleted = await raw.post(
        Uri.parse('${objectUrl('$run/notoken.txt')}?delete_token=$token'),
        headers: <String, String>{'Authorization': 'Firebase owner'},
      );
      expect(deleted.statusCode, 200);
      // Deleting the only token issues a new one in the same response.
      final String fresh =
          (jsonDecode(deleted.body) as Map<String, Object?>)['downloadTokens']!
              as String;
      expect(fresh, isNot(token));
      expect(fresh, isNot(contains(',')));
      final FullMetadata metadata = await storage
          .ref('$run/notoken.txt')
          .metadata();
      expect(metadata.downloadTokens, <String>[fresh]);
    });

    test(
      'a valid token bypasses the rules; a wrong one falls back to them',
      () async {
        final Map<String, Object?> created = await upload(
          'users/u1/$run-t.txt',
          'secret',
          bucket: _auth,
        );
        final String url = objectUrl('users/u1/$run-t.txt', bucket: _auth);
        final String token = (created['downloadTokens']! as String)
            .split(',')
            .first;
        expect(
          (await raw.get(Uri.parse('$url?alt=media&token=$token'))).body,
          'secret',
        );
        expect(
          (await raw.get(Uri.parse('$url?alt=media&token=wrong'))).statusCode,
          403,
        );
      },
    );
  });

  group('10. only configured buckets exist', () {
    test(
      'any other bucket is 403 "no loaded ruleset"; the client says unauthorized',
      () async {
        final FirebaseStorage other = FirebaseStorage(
          app,
          bucket: 'not-configured.appspot.com',
          emulatorHost: host,
        );
        addTearDown(other.close);
        await expectLater(
          other.ref('x').metadata(),
          throwsA(
            isA<FirebaseStorageException>()
                .having(
                  (FirebaseStorageException e) => e.code,
                  'code',
                  'unauthorized',
                )
                .having(
                  (FirebaseStorageException e) => e.serverResponse,
                  'serverResponse',
                  contains('Storage Emulator has no loaded ruleset.'),
                ),
          ),
        );
      },
    );
  });

  group('responses', () {
    test('a media download carries the object headers', () async {
      await storage
          .ref('$run/headers.txt')
          .putBytes(
            Uint8List.fromList(utf8.encode('abc')),
            metadata: const SettableMetadata(contentType: 'text/plain'),
          );
      final http.Response response = await raw.get(
        Uri.parse('${objectUrl('$run/headers.txt')}?alt=media'),
      );
      expect(response.headers['content-type'], startsWith('text/plain'));
      expect(
        response.headers['content-disposition'],
        'inline; filename*=headers.txt',
      );
      expect(response.headers['accept-ranges'], 'bytes');
      expect(
        response.headers['x-goog-hash'],
        matches(RegExp(r'^crc32c=[^,]+,md5=.+$')),
      );
    });

    test('DELETE is 204, a second DELETE 404', () async {
      await upload('$run/delete.txt', 'x');
      final Reference ref = storage.ref('$run/delete.txt');
      await ref.delete();
      await expectLater(
        ref.delete(),
        throwsA(
          isA<FirebaseStorageException>().having(
            (FirebaseStorageException e) => e.code,
            'code',
            'object-not-found',
          ),
        ),
      );
    });
  });
}
