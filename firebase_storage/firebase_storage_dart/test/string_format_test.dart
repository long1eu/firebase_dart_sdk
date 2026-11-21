import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:firebase_storage_dart/src/string_format.dart';
import 'package:test/test.dart';

import 'fakes.dart';

// Ported from string.test.ts of the JS SDK.
void main() {
  const List<int> base64Bytes = <int>[
    0x0a, 0x96, 0x25, 0x33, 0x5f, 0x97, 0xb0, 0x6c, 0x53, 0x77, //
    0x59, 0xfa, 0x8b, 0x31, 0xcc, 0x53, 0xfc, 0x98, 0xdc, 0x1c,
  ];

  List<int> bytesOf(StringFormat format, String value) =>
      dataFromString(format, value).bytes;

  group('raw', () {
    test('ascii', () {
      expect(bytesOf(StringFormat.raw, 'Hello, world!\n'), <int>[
        0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x2c, 0x20, 0x77, 0x6f, 0x72, 0x6c, //
        0x64, 0x21, 0x0a,
      ]);
    });

    test('2-byte UTF-8 code points', () {
      expect(bytesOf(StringFormat.raw, 'aa\u0089'), <int>[
        0x61, 0x61, 0xc2, 0x89, //
      ]);
    });

    test('3-byte UTF-8 code points', () {
      expect(bytesOf(StringFormat.raw, 'aaｼ'), <int>[
        0x61, 0x61, 0xef, 0xbd, 0xbc, //
      ]);
    });

    test('4-byte UTF-8 code points', () {
      expect(bytesOf(StringFormat.raw, 'Hello! 😊'), <int>[
        0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0x20, 0xf0, 0x9f, 0x98, 0x8a, //
      ]);
    });

    test('missing low and high surrogates become U+FFFD', () {
      const List<int> expected = <int>[
        0x61,
        0x61,
        0xef,
        0xbf,
        0xbd,
        0x20,
        0x74,
      ];
      expect(bytesOf(StringFormat.raw, 'aa\ud83d t'), expected);
      expect(bytesOf(StringFormat.raw, 'aa\udc3d t'), expected);
    });

    test('has no content type', () {
      expect(dataFromString(StringFormat.raw, 'a').contentType, isNull);
    });
  });

  group('base64', () {
    test('with and without padding', () {
      expect(
        bytesOf(StringFormat.base64, 'CpYlM1+XsGxTd1n6izHMU/yY3Bw='),
        base64Bytes,
      );
      expect(
        bytesOf(StringFormat.base64, 'CpYlM1+XsGxTd1n6izHMU/yY3Bw'),
        base64Bytes,
      );
    });

    test('rejects base64url', () {
      expect(
        () => bytesOf(StringFormat.base64, 'CpYlM1-XsGxTd1n6izHMU_yY3Bw='),
        throwsStorageCode('invalid-format'),
      );
    });

    test('rejects other characters and impossible lengths', () {
      for (final String value in <String>['ab cd', 'ab*d', 'a', 'ab=c']) {
        expect(
          () => bytesOf(StringFormat.base64, value),
          throwsStorageCode('invalid-format'),
          reason: value,
        );
      }
    });

    test('the empty string is no bytes', () {
      expect(bytesOf(StringFormat.base64, ''), isEmpty);
    });
  });

  group('base64url', () {
    test('with and without padding', () {
      expect(
        bytesOf(StringFormat.base64Url, 'CpYlM1-XsGxTd1n6izHMU_yY3Bw='),
        base64Bytes,
      );
      expect(
        bytesOf(StringFormat.base64Url, 'CpYlM1-XsGxTd1n6izHMU_yY3Bw'),
        base64Bytes,
      );
    });

    test('rejects base64', () {
      expect(
        () => bytesOf(StringFormat.base64Url, 'CpYlM1+XsGxTd1n6izHMU/yY3Bw='),
        throwsA(
          isA<FirebaseStorageException>().having(
            (FirebaseStorageException e) => e.message,
            'message',
            "String does not match format 'base64url': Invalid character '+' found: is it base64 encoded?",
          ),
        ),
      );
    });
  });

  group('data URL', () {
    test('base64 with an embedded content type and parameters', () {
      final StringData data = dataFromString(
        StringFormat.dataUrl,
        'data:image/png;param1=value;base64,aaaa',
      );
      expect(data.bytes, <int>[0x69, 0xa6, 0x9a]);
      expect(data.contentType, 'image/png;param1=value');
    });

    test('not base64, no content type', () {
      final StringData data = dataFromString(
        StringFormat.dataUrl,
        'data:,aaaa',
      );
      expect(data.bytes, <int>[0x61, 0x61, 0x61, 0x61]);
      expect(data.contentType, isNull);
    });

    test('base64, no content type', () {
      final StringData data = dataFromString(
        StringFormat.dataUrl,
        'data:;base64,aaaa',
      );
      expect(data.bytes, <int>[0x69, 0xa6, 0x9a]);
      expect(data.contentType, isNull);
    });

    test('not base64, with a content type', () {
      final StringData data = dataFromString(
        StringFormat.dataUrl,
        'data:text/plain,arst',
      );
      expect(data.bytes, <int>[0x61, 0x72, 0x73, 0x74]);
      expect(data.contentType, 'text/plain');
    });

    test('URL-encoded text', () {
      expect(bytesOf(StringFormat.dataUrl, 'data:,a%20data'), <int>[
        0x61, 0x20, 0x64, 0x61, 0x74, 0x61, //
      ]);
    });

    test('URL-encoded non-BMP code points', () {
      expect(
        bytesOf(StringFormat.dataUrl, 'data:,%F0%9F%98%8A%E6%86%82%E9%AC%B1'),
        <int>[
          0xf0, 0x9f, 0x98, 0x8a, 0xe6, 0x86, 0x82, 0xe9, 0xac, 0xb1, //
        ],
      );
    });

    test('rejects invalid URL encodings', () {
      expect(
        () => bytesOf(StringFormat.dataUrl, 'data:,%%0'),
        throwsStorageCode('invalid-format'),
      );
    });

    test('rejects invalid URL-encoded byte sequences', () {
      expect(
        () => bytesOf(StringFormat.dataUrl, 'data:,%80%80%80'),
        throwsStorageCode('invalid-format'),
      );
    });

    test('rejects an invalid format', () {
      expect(
        () => bytesOf(StringFormat.dataUrl, 'dateeeep:,invalid'),
        throwsStorageCode('invalid-format'),
      );
    });

    test('rejects invalid base64 in a base64 data URL', () {
      expect(
        () => bytesOf(StringFormat.dataUrl, 'data:;base64,a-b_'),
        throwsStorageCode('invalid-format'),
      );
    });
  });
}
