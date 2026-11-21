import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../fakes.dart';
import 'conformance.dart';

// Conformance with the metadata mapping of the JS SDK (`implementation/metadata.ts` getMappings, fromResource,
// toResourceString), as used by requests.test.ts: what is read from a resource, what is written in a body.
void main() {
  late FirebaseApp app;
  late FirebaseStorage storage;
  late List<Recorded> requests;
  late Object? resource;

  setUp(() {
    app = newApp();
    requests = <Recorded>[];
    resource = serverResource;
    storage = storageWith(app, (_) => json(resource), requests: requests);
  });

  tearDown(() async {
    storage.close();
    await app.delete();
  });

  test('a resource round-trips through FullMetadata.toJson', () async {
    final FullMetadata metadata = await storage.ref('x').metadata();
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
    // The JSON form is plain JSON.
    expect(jsonDecode(jsonEncode(metadata.toJson())), metadata.toJson());
  });

  test(
    'fields outside the mapping are dropped; missing ones are null',
    () async {
      resource = <String, Object?>{
        'name': 'a/b.txt',
        'bucket': 'b',
        'size': '0',
        'storageClass': 'STANDARD',
        'crc32c': '4043272850',
        'etag': 'xyz',
        'id': 'b/a/b.txt/1',
      };
      final FullMetadata metadata = await storage.ref('x').metadata();
      expect(metadata.toJson(), <String, Object?>{
        'bucket': 'b',
        'fullPath': 'a/b.txt',
        'name': 'b.txt',
        'size': 0,
        'downloadTokens': <String>[],
      });
    },
  );

  test(
    'name is the last component; a one-character name stays (xformPath)',
    () async {
      resource = <String, Object?>{'name': 'a', 'bucket': 'b'};
      expect((await storage.ref('x').metadata()).name, 'a');
      resource = <String, Object?>{'name': 'p/q/r', 'bucket': 'b'};
      expect((await storage.ref('x').metadata()).name, 'r');
    },
  );

  test('an unparsable time is null (JS keeps the raw string)', () async {
    resource = <String, Object?>{
      ...serverResource,
      'timeCreated': 'This is a real time',
      'updated': 'Also a real time',
    };
    final FullMetadata metadata = await storage.ref('x').metadata();
    expect(metadata.timeCreated, isNull);
    expect(metadata.updated, isNull);
  });

  test(
    'the downloadTokens string is split on commas (downloadUrlFromResourceString)',
    () async {
      resource = <String, Object?>{
        ...serverResource,
        'downloadTokens': 't1,t2',
      };
      expect((await storage.ref('x').metadata()).downloadTokens, <String>[
        't1',
        't2',
      ]);
      expect(
        await storage.ref('x').downloadUrl(),
        endsWith('?alt=media&token=t1'),
      );
    },
  );

  test('empty or missing downloadTokens is no-download-url', () async {
    for (final Object? tokens in <Object?>['', null, 7]) {
      resource = <String, Object?>{...serverResource, 'downloadTokens': tokens};
      await expectLater(
        storage.ref('x').downloadUrl(),
        throwsStorageCode('no-download-url'),
      );
    }
  });

  group('the written body (toResourceString)', () {
    test(
      'updateMetadata writes the settable fields in mapping order, nothing else',
      () async {
        await storage
            .ref('x')
            .updateMetadata(
              const SettableMetadata(
                customMetadata: <String, String>{'k': 'v'},
                contentType: 'text/plain',
                contentLanguage: 'ro',
                contentEncoding: 'gzip',
                contentDisposition: 'inline',
                cacheControl: 'no-cache',
              ),
            );
        expect(
          requests.single.body,
          '{"cacheControl":"no-cache","contentDisposition":"inline","contentEncoding":"gzip",'
          '"contentLanguage":"ro","contentType":"text/plain","metadata":{"k":"v"}}',
        );
      },
    );

    test('an empty SettableMetadata is an empty object', () async {
      await storage.ref('x').updateMetadata(const SettableMetadata());
      expect(requests.single.body, '{}');
    });

    test(
      'a deleted field is sent as null (JS: the field set to null)',
      () async {
        await storage
            .ref('x')
            .updateMetadata(
              const SettableMetadata(
                contentType: 'text/plain',
                delete: <MetadataField>{
                  MetadataField.cacheControl,
                  MetadataField.customMetadata,
                },
              ),
            );
        expect(
          requests.single.body,
          '{"cacheControl":null,"contentType":"text/plain","metadata":null}',
        );
      },
    );

    test('a null custom key is sent as null; the other keys as given', () async {
      // JS: customMetadata {k: null} serialises the null, and the backend removes that key.
      await storage
          .ref('x')
          .updateMetadata(
            const SettableMetadata(
              customMetadata: <String, String?>{'k': null, 'z': '3'},
            ),
          );
      expect(requests.single.body, '{"metadata":{"k":null,"z":"3"}}');
    });

    test('an upload leaves null custom keys out', () async {
      await storage
          .ref('x')
          .putString(
            'x',
            metadata: const SettableMetadata(
              customMetadata: <String, String?>{'k': null, 'z': '3'},
            ),
          );
      expect(
        multipartParts(requests.single).metadata,
        '{"name":"x","contentType":"application/octet-stream","metadata":{"z":"3"}}',
      );
    });

    test(
      'md5Hash is written by uploads (after name, as in the mapping) and not by updateMetadata',
      () async {
        const SettableMetadata withHash = SettableMetadata(
          md5Hash: 'deadbeef',
          contentType: 'text/plain',
        );
        await storage.ref('x').putString('x', metadata: withHash);
        expect(
          multipartParts(requests.single).metadata,
          '{"name":"x","md5Hash":"deadbeef","contentType":"text/plain"}',
        );
        requests.clear();
        await storage.ref('x').updateMetadata(withHash);
        expect(requests.single.body, '{"contentType":"text/plain"}');
      },
    );

    test(
      'an upload writes name and contentType, the other fields when given',
      () async {
        await storage
            .ref('dir/f.txt')
            .putString(
              'x',
              metadata: const SettableMetadata(
                cacheControl: 'no-cache',
                customMetadata: <String, String>{'k': 'v'},
                delete: <MetadataField>{MetadataField.contentLanguage},
              ),
            );
        expect(
          multipartParts(requests.single).metadata,
          '{"name":"dir/f.txt","cacheControl":"no-cache","contentType":"application/octet-stream",'
          '"metadata":{"k":"v"}}',
        );
      },
    );
  });

  test('a response with only a 200 and an empty body is unknown', () async {
    final FirebaseStorage empty = storageWith(
      app,
      (_) async => http.Response('', 200),
    );
    addTearDown(empty.close);
    await expectLater(empty.ref('x').metadata(), throwsStorageCode('unknown'));
  });
}
