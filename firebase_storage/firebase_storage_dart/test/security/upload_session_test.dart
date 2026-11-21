// Threat model: storage_threat_model.md, "Resumable upload session URL" (T13, T14).
//
// Written against the contract (Reference.startUpload, UploadTask.result) before the upload code landed.
import 'dart:typed_data';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'security_support.dart';

const String _uploadId = 'UPLOAD-ID-SECRET-5e55';

/// Larger than the 256 KiB multipart threshold, so the upload is resumable.
const int _size = 300 * 1024;

/// A resumable server whose `start` answers with [uploadUrl]; `upload`/`finalize` go to [onChunk].
RecordingClient _server(
  String? uploadUrl, {
  http.StreamedResponse Function(SentRequest request)? onChunk,
}) {
  return RecordingClient((SentRequest r) {
    final String command = r.headers['X-Goog-Upload-Command'] ?? '';
    if (command == 'start') {
      return respond(
        200,
        body: 'OK',
        headers: <String, String>{
          'x-goog-upload-status': 'active',
          'x-goog-upload-url': ?uploadUrl,
        },
      );
    }
    if (onChunk != null) {
      return onChunk(r);
    }
    if (command.contains('finalize')) {
      return http.StreamedResponse(
        Stream<List<int>>.value(
          '{"name":"x","bucket":"b","size":"$_size"}'.codeUnits,
        ),
        200,
        headers: const <String, String>{'x-goog-upload-status': 'final'},
      );
    }
    return respond(
      200,
      body: 'OK',
      headers: const <String, String>{'x-goog-upload-status': 'active'},
    );
  });
}

Future<Object?> _run(FirebaseStorage storage) async {
  try {
    await storage.ref('x').startUpload(Uint8List(_size)).result;
    return null;
  } on Object catch (e) {
    return e;
  }
}

void main() {
  const String good =
      'https://firebasestorage.googleapis.com/v0/b/b/o?name=x&upload_id=$_uploadId&upload_protocol=resumable';

  test('a well-formed session URL on the API host is used', () async {
    final RecordingClient client = _server(good);
    final FirebaseStorage storage = securityStorage(securityApp(), client);
    addTearDown(storage.close);
    expect(await _run(storage), isNull);
    expect(client.sent.length, greaterThan(1));
    expect(
      client.sent.skip(1).map((SentRequest s) => s.url.toString()),
      everyElement(good),
    );
  });

  for (final MapEntry<String, String?> bad in <String, String?>{
    'another host': 'https://evil.example/upload?upload_id=$_uploadId',
    'a look-alike host':
        'https://firebasestorage.googleapis.com.evil.example/v0/b/b/o?upload_id=$_uploadId',
    'userinfo trick':
        'https://firebasestorage.googleapis.com@evil.example/v0/b/b/o?upload_id=$_uploadId',
    'an https -> http downgrade':
        'http://firebasestorage.googleapis.com/v0/b/b/o?upload_id=$_uploadId',
    'another port':
        'https://firebasestorage.googleapis.com:8443/v0/b/b/o?upload_id=$_uploadId',
    'a relative URL': '/v0/b/b/o?upload_id=$_uploadId',
    'no header': null,
    'an empty header': '',
  }.entries) {
    test(
      'a session URL with ${bad.key} fails the task and sends nothing to it',
      () async {
        final RecordingClient client = _server(bad.value);
        final FirebaseStorage storage = securityStorage(
          securityApp(),
          client,
          retry: const StorageRetryPolicy(upload: Duration(seconds: 1)),
        );
        addTearDown(storage.close);
        expect(await _run(storage), isA<FirebaseStorageException>());
        expect(
          client.sent,
          hasLength(1),
          reason:
              'only the start request: ${client.sent.map((SentRequest s) => s.url)}',
        );
      },
    );
  }

  test('the emulator session URL must stay on the emulator host', () async {
    final RecordingClient client = _server(
      'http://evil.example:9199/v0/b/b/o?name=x&upload_id=$_uploadId&upload_protocol=resumable',
    );
    final FirebaseStorage storage = securityStorage(
      securityApp(),
      client,
      emulatorHost: '127.0.0.1:9199',
      retry: const StorageRetryPolicy(upload: Duration(seconds: 1)),
    );
    addTearDown(storage.close);
    expect(await _run(storage), isA<FirebaseStorageException>());
    expect(client.sent, hasLength(1));
  });

  test(
    'the upload id never appears in the error of a failed session',
    () async {
      final RecordingClient client = _server(
        good,
        onChunk: (SentRequest r) =>
            throw http.ClientException('Connection reset by peer', r.url),
      );
      final FirebaseStorage storage = securityStorage(
        securityApp(),
        client,
        retry: const StorageRetryPolicy(upload: Duration(seconds: 5)),
      );
      addTearDown(storage.close);
      final Object? error = await _run(storage);
      expect(error, isA<FirebaseStorageException>());
      expect(everythingPrinted(error!), isNot(contains(_uploadId)));
      expect(everythingPrinted(error), isNot(contains(secretIdToken)));
    },
  );

  test(
    'a size-received beyond what was sent fails instead of skipping data',
    () async {
      final RecordingClient client = _server(
        good,
        onChunk: (SentRequest r) {
          if (r.headers['X-Goog-Upload-Command'] == 'query') {
            return respond(
              200,
              body: 'OK',
              headers: const <String, String>{
                'x-goog-upload-status': 'active',
                'x-goog-upload-size-received': '999999',
              },
            );
          }
          return respond(503);
        },
      );
      final FirebaseStorage storage = securityStorage(
        securityApp(),
        client,
        retry: const StorageRetryPolicy(upload: Duration(seconds: 30)),
      );
      addTearDown(storage.close);
      expect(await _run(storage), isA<FirebaseStorageException>());
    },
  );
}
