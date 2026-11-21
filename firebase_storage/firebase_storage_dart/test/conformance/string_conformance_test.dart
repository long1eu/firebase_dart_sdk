import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:test/test.dart';

import '../fakes.dart';
import 'conformance.dart';

// Conformance with string.test.ts of the JS SDK (`dataFromString`), through `Reference.putString`: the bytes
// are those of the data part of the multipart body, the content type that of its metadata.
void main() {
  late FirebaseApp app;
  late FirebaseStorage storage;
  late List<Recorded> requests;

  setUp(() {
    app = newApp();
    requests = <Recorded>[];
    storage = storageWith(app, (_) => json(serverResource), requests: requests);
  });

  tearDown(() async {
    storage.close();
    await app.delete();
  });

  Future<({List<int> data, String contentType})> put(
    String value,
    StringFormat format,
  ) async {
    requests.clear();
    await storage.ref('s').putString(value, format: format);
    final parts = multipartParts(requests.single);
    expect(
      parts.metadata,
      contains('"contentType":${'"${parts.contentType}"'}'),
    );
    return (data: parts.data, contentType: parts.contentType);
  }

  Future<void> rejects(
    String value,
    StringFormat format,
    String jsFormat,
  ) async {
    requests.clear();
    await expectLater(
      storage.ref('s').putString(value, format: format),
      throwsA(
        isA<FirebaseStorageException>()
            .having(
              (FirebaseStorageException e) => e.code,
              'code',
              'invalid-format',
            )
            .having(
              (FirebaseStorageException e) => e.message,
              'message',
              startsWith("String does not match format '$jsFormat': "),
            ),
      ),
    );
    expect(requests, isEmpty, reason: 'rejected before any request');
  }

  const List<int> base64Bytes = <int>[
    0x0a, 0x96, 0x25, 0x33, 0x5f, 0x97, 0xb0, 0x6c, 0x53, 0x77, //
    0x59, 0xfa, 0x8b, 0x31, 0xcc, 0x53, 0xfc, 0x98, 0xdc, 0x1c,
  ];

  group('raw', () {
    final Map<String, List<int>> cases = <String, List<int>>{
      'Encodes raw strings with ascii correctly|Hello, world!\n': <int>[
        0x48,
        0x65,
        0x6c,
        0x6c,
        0x6f,
        0x2c,
        0x20,
        0x77,
        0x6f,
        0x72,
        0x6c,
        0x64, //
        0x21, 0x0a,
      ],
      'Encodes raw strings with 2-byte UTF8 codepoints correctly|aa\u0089':
          <int>[
            0x61, 0x61, 0xc2, 0x89, //
          ],
      'Encodes raw strings with 3-byte UTF8 codepoints correctly|aaｼ': <int>[
        0x61, 0x61, 0xef, 0xbd, 0xbc, //
      ],
      'Encodes raw strings with 4-byte UTF8 codepoints correctly|Hello! 😊':
          <int>[
            0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0x20, 0xf0, 0x9f, 0x98, 0x8a, //
          ],
      'Encodes raw strings with missing low surrogates correctly|aa\ud83d t':
          <int>[
            0x61, 0x61, 0xef, 0xbf, 0xbd, 0x20, 0x74, //
          ],
      'Encodes raw strings with missing high surrogates correctly|aa\udc3d t':
          <int>[
            0x61, 0x61, 0xef, 0xbf, 0xbd, 0x20, 0x74, //
          ],
    };
    for (final MapEntry<String, List<int>> entry in cases.entries) {
      final int bar = entry.key.indexOf('|');
      test(entry.key.substring(0, bar), () async {
        final result = await put(
          entry.key.substring(bar + 1),
          StringFormat.raw,
        );
        expect(result.data, entry.value);
        expect(result.contentType, 'application/octet-stream');
      });
    }
  });

  group('base64', () {
    test('Encodes base64 strings correctly', () async {
      expect(
        (await put('CpYlM1+XsGxTd1n6izHMU/yY3Bw=', StringFormat.base64)).data,
        base64Bytes,
      );
    });
    test('Encodes base64 strings without padding correctly', () async {
      expect(
        (await put('CpYlM1+XsGxTd1n6izHMU/yY3Bw', StringFormat.base64)).data,
        base64Bytes,
      );
    });
    test('Rejects invalid base64 strings', () async {
      await rejects(
        'CpYlM1-XsGxTd1n6izHMU_yY3Bw=',
        StringFormat.base64,
        'base64',
      );
    });
    test(
      'Rejects characters outside the alphabet (the Node pre-check)',
      () async {
        await rejects('CpYl!M1+', StringFormat.base64, 'base64');
      },
    );
    test('Encodes base64url strings correctly', () async {
      expect(
        (await put(
          'CpYlM1-XsGxTd1n6izHMU_yY3Bw=',
          StringFormat.base64Url,
        )).data,
        base64Bytes,
      );
    });
    test('Encodes base64url strings without padding correctly', () async {
      expect(
        (await put('CpYlM1-XsGxTd1n6izHMU_yY3Bw', StringFormat.base64Url)).data,
        base64Bytes,
      );
    });
    test('Rejects invalid base64url strings', () async {
      await rejects(
        'CpYlM1+XsGxTd1n6izHMU/yY3Bw=',
        StringFormat.base64Url,
        'base64url',
      );
    });
  });

  group('data_url', () {
    test(
      'Encodes base64 data URLs (including embedded content type and parameters) correctly',
      () async {
        final result = await put(
          'data:image/png;param1=value;base64,aaaa',
          StringFormat.dataUrl,
        );
        expect(result.data, <int>[0x69, 0xa6, 0x9a]);
        expect(result.contentType, 'image/png;param1=value');
      },
    );
    test('Encodes non-base64 data URLs with no content type correctly', () async {
      // JS contentType null: the upload falls back to application/octet-stream.
      final result = await put('data:,aaaa', StringFormat.dataUrl);
      expect(result.data, <int>[0x61, 0x61, 0x61, 0x61]);
      expect(result.contentType, 'application/octet-stream');
    });
    test('Encodes base64 data URLs with no content type correctly', () async {
      final result = await put('data:;base64,aaaa', StringFormat.dataUrl);
      expect(result.data, <int>[0x69, 0xa6, 0x9a]);
      expect(result.contentType, 'application/octet-stream');
    });
    test('Encodes non-base64 data URLs with content type correctly', () async {
      final result = await put('data:text/plain,arst', StringFormat.dataUrl);
      expect(result.data, <int>[0x61, 0x72, 0x73, 0x74]);
      expect(result.contentType, 'text/plain');
    });
    test(
      'Encodes non-base64 data URLs with URL-encoded text correctly',
      () async {
        expect((await put('data:,a%20data', StringFormat.dataUrl)).data, <int>[
          0x61, 0x20, 0x64, 0x61, 0x74, 0x61, //
        ]);
      },
    );
    test(
      'Encodes non-base64 data URLs with URL-encoded non-BMP codepoints correctly',
      () async {
        expect(
          (await put(
            'data:,%F0%9F%98%8A%E6%86%82%E9%AC%B1',
            StringFormat.dataUrl,
          )).data,
          <int>[
            0xf0, 0x9f, 0x98, 0x8a, 0xe6, 0x86, 0x82, 0xe9, 0xac, 0xb1, //
          ],
        );
      },
    );
    test('Rejects data URLs with invalid URL encodings', () async {
      await rejects('data:,%%0', StringFormat.dataUrl, 'data_url');
    });
    test('Rejects data URLs with invalid URL-encoded byte sequences', () async {
      await rejects('data:,%80%80%80', StringFormat.dataUrl, 'data_url');
    });
    test('Rejects data URLs with an invalid format', () async {
      await rejects('dateeeep:,invalid', StringFormat.dataUrl, 'data_url');
    });
    test('Rejects a base64 data URL whose payload is base64url', () async {
      // dataFromString(DATA_URL) decodes a ;base64 payload as BASE64, which rejects '-' and '_'.
      await rejects('data:;base64,a-_a', StringFormat.dataUrl, 'base64');
    });
  });
}
