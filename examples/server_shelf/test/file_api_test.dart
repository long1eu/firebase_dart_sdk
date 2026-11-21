// Runs the file API in this process against the Storage emulator:
//
//     FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199 dart test test/file_api_test.dart
//
// Skipped without FIREBASE_STORAGE_EMULATOR_HOST.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:server_shelf/file_api.dart';
import 'package:server_shelf/storage_from_env.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

void main() {
  final String? emulator =
      Platform.environment['FIREBASE_STORAGE_EMULATOR_HOST'];

  group(
    'file API',
    () {
      late FirebaseStorage storage;
      late HttpServer server;
      late HttpClient client;
      late String folder;

      setUp(() async {
        folder = 'server-test-${DateTime.now().microsecondsSinceEpoch}';
        storage = storageFromEnvironment(appName: folder);
        server = await shelf_io.serve(
          FileApi(storage).handler,
          InternetAddress.loopbackIPv4,
          0,
        );
        client = HttpClient();
      });

      tearDown(() async {
        client.close(force: true);
        await server.close(force: true);
        storage.close();
      });

      Future<HttpClientResponse> send(
        String method,
        String path, {
        List<int>? body,
        Map<String, String> headers = const <String, String>{},
      }) async {
        final HttpClientRequest request = await client.openUrl(
          method,
          Uri.parse('http://127.0.0.1:${server.port}$path'),
        );
        headers.forEach(request.headers.set);
        if (body != null) {
          request.contentLength = body.length;
          request.add(body);
        }
        return request.close();
      }

      Future<List<int>> bytesOf(HttpClientResponse response) async {
        final BytesBuilder builder = BytesBuilder();
        await response.forEach(builder.add);
        return builder.takeBytes();
      }

      test('stores a body larger than one chunk and serves it back', () async {
        final Uint8List body = Uint8List.fromList(
          List<int>.generate(600 * 1024, (int i) => i % 251),
        );
        final HttpClientResponse created = await send(
          'PUT',
          '/files/$folder/data.bin',
          body: body,
          headers: <String, String>{'content-type': 'application/x-test'},
        );
        expect(created.statusCode, 201);
        final Map<String, Object?> json =
            jsonDecode(utf8.decode(await bytesOf(created)))
                as Map<String, Object?>;
        expect(json['size'], body.length);
        expect(json['contentType'], 'application/x-test');

        final HttpClientResponse read = await send(
          'GET',
          '/files/$folder/data.bin',
        );
        expect(read.statusCode, 200);
        expect(read.headers.contentType?.mimeType, 'application/x-test');
        expect(await bytesOf(read), body);

        // The object is in the bucket, not only behind the API.
        expect(await storage.ref('$folder/data.bin').getBytes(), body);
      });

      test('answers a range with 206', () async {
        await storage.ref('$folder/digits.txt').putString('0123456789');
        final HttpClientResponse part = await send(
          'GET',
          '/files/$folder/digits.txt',
          headers: <String, String>{'range': 'bytes=2-5'},
        );
        expect(part.statusCode, 206);
        expect(part.headers.value('content-range'), 'bytes 2-5/10');
        expect(utf8.decode(await bytesOf(part)), '2345');

        final HttpClientResponse tail = await send(
          'GET',
          '/files/$folder/digits.txt',
          headers: <String, String>{'range': 'bytes=-3'},
        );
        expect(utf8.decode(await bytesOf(tail)), '789');
      });

      test('maps a missing object to 404 and deletes with 204', () async {
        final HttpClientResponse missing = await send(
          'GET',
          '/files/$folder/none.txt',
        );
        expect(missing.statusCode, 404);
        expect(
          (jsonDecode(utf8.decode(await bytesOf(missing)))
              as Map<String, Object?>)['error'],
          'object-not-found',
        );

        await storage.ref('$folder/gone.txt').putString('x');
        final HttpClientResponse deleted = await send(
          'DELETE',
          '/files/$folder/gone.txt',
        );
        expect(deleted.statusCode, 204);
        await bytesOf(deleted);
        final HttpClientResponse again = await send(
          'GET',
          '/files/$folder/gone.txt',
        );
        expect(again.statusCode, 404);
        await bytesOf(again);
      });

      test('refuses an upload without a length', () async {
        final HttpClientRequest request = await client.openUrl(
          'PUT',
          Uri.parse('http://127.0.0.1:${server.port}/files/$folder/x.txt'),
        );
        request.headers.chunkedTransferEncoding = true;
        request.add(utf8.encode('chunked'));
        final HttpClientResponse response = await request.close();
        expect(response.statusCode, 411);
        await bytesOf(response);
      });
    },
    skip: emulator == null
        ? 'Set FIREBASE_STORAGE_EMULATOR_HOST to run against the emulator.'
        : null,
  );
}
