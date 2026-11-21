// Threat model: storage_threat_model.md, "Header and MIME injection" (T12).
import 'dart:typed_data';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:test/test.dart';

import 'security_support.dart';

const String _injected = 'text/plain\r\nX-Evil: 1\r\n\r\n--';

void main() {
  late RecordingClient client;
  late FirebaseStorage storage;

  setUp(() {
    client = RecordingClient(
      (SentRequest r) => respondJson(objectResource('x')),
    );
    storage = securityStorage(securityApp(), client);
  });

  tearDown(() => storage.close());

  void expectNoRawLineBreaksInHeaders() {
    for (final SentRequest sent in client.sent) {
      sent.headers.forEach((String name, String value) {
        expect(value, isNot(matches(RegExp('[\r\n]'))), reason: name);
      });
    }
  }

  test(
    'a content type with CR/LF is refused before any request (multipart part header)',
    () async {
      await expectLater(
        storage
            .ref('x')
            .putBytes(
              Uint8List.fromList(<int>[1]),
              metadata: const SettableMetadata(contentType: _injected),
            ),
        throwsStorageCode('invalid-argument'),
      );
      expect(client.sent, isEmpty);
    },
  );

  test('a data URL media type cannot inject a part header', () async {
    try {
      await storage
          .ref('x')
          .putString(
            'data:text/plain%0D%0AX-Evil:%201;base64,AQ==',
            format: StringFormat.dataUrl,
          );
    } on FirebaseStorageException {
      // Refusing it is fine.
    }
    for (final SentRequest sent in client.sent) {
      expect(sent.body, isNot(contains('\r\nX-Evil')));
    }
    expectNoRawLineBreaksInHeaders();
  });

  test(
    'custom metadata with CR/LF travels JSON-escaped, never as raw lines',
    () async {
      await storage
          .ref('x')
          .putBytes(
            Uint8List.fromList(<int>[1]),
            metadata: const SettableMetadata(
              cacheControl: 'no-cache\r\nX-Evil: 1',
              contentDisposition: 'inline\r\nX-Evil: 1',
              customMetadata: <String, String>{
                'k\r\nX-Evil: 1': 'v\r\nX-Evil: 1',
              },
            ),
          );
      expect(client.sent.single.body, isNot(contains('\r\nX-Evil')));
      expectNoRawLineBreaksInHeaders();
    },
  );

  test('updateMetadata sends metadata only in the JSON body', () async {
    await storage
        .ref('x')
        .updateMetadata(
          const SettableMetadata(
            contentType: 'text/plain',
            customMetadata: <String, String>{'k': 'v\r\nX-Evil: 1'},
          ),
        );
    expect(client.sent.single.body, isNot(contains('\r\nX-Evil')));
    expectNoRawLineBreaksInHeaders();
  });

  test(
    'the multipart boundary is not derived from a predictable source',
    () async {
      // securityStorage injects random() == 0.5; a boundary that still varies comes from a secure source.
      final Set<String> boundaries = <String>{};
      for (int i = 0; i < 3; i++) {
        await storage.ref('x').putBytes(Uint8List.fromList(<int>[1]));
      }
      for (final SentRequest sent in client.sent) {
        boundaries.add(sent.headers['Content-Type']!);
      }
      expect(boundaries, hasLength(3));
    },
  );
}
